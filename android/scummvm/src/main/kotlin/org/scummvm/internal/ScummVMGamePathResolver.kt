package org.scummvm.internal

import android.content.ContentResolver
import android.database.Cursor
import android.net.Uri
import android.provider.OpenableColumns
import java.io.File
import java.io.IOException
import java.util.zip.ZipInputStream

/** Imports `.zip` and `.scummvm` documents into the app's private games folder. */
internal class ScummVMGamePathResolver(
    private val contentResolver: ContentResolver,
    private val paths: ScummVMPaths,
) {
    fun resolve(uri: Uri?): File? {
        uri ?: return null

        val displayName = queryDisplayName(uri) ?: uri.lastPathSegment ?: "game.scummvm"
        val extension = displayName.substringAfterLast('.', missingDelimiterValue = "").lowercase()
        val mimeType = contentResolver.getType(uri)
        require(extension in ARCHIVE_EXTENSIONS || mimeType == ZIP_MIME_TYPE) {
            "Unsupported game document '$displayName'. Select a .zip or .scummvm archive."
        }

        paths.importedGamesDir.mkdirs()
        check(paths.importedGamesDir.isDirectory) {
            "Could not create ${paths.importedGamesDir.path}"
        }

        val stem =
            displayName
                .substringBeforeLast('.', displayName)
                .replace(Regex("[^A-Za-z0-9._-]"), "-")
                .trim('-', '.')
                .ifEmpty { "game" }
        val destination =
            File(
                paths.importedGamesDir,
                "$stem-${fnv1a64(uri.toString()).toString(16)}",
            )

        preferredGameDirectory(destination)?.let { return it }

        val temporary = File(destination.parentFile, ".${destination.name}.partial")
        temporary.deleteRecursively()
        check(temporary.mkdirs()) { "Could not create temporary import directory ${temporary.path}" }

        try {
            contentResolver.openInputStream(uri)?.buffered()?.use { input ->
                ZipInputStream(input).use { archive -> extract(archive, temporary) }
            } ?: throw IOException("Could not open $uri")

            preferredGameDirectory(temporary)
                ?: throw IOException("The archive does not contain any game files")

            destination.deleteRecursively()
            check(temporary.renameTo(destination)) {
                "Could not move imported game to ${destination.path}"
            }
            return preferredGameDirectory(destination)
                ?: throw IOException("The imported game directory is empty")
        } catch (error: Throwable) {
            temporary.deleteRecursively()
            throw error
        }
    }

    private fun extract(
        archive: ZipInputStream,
        destination: File,
    ) {
        val rootPath = destination.canonicalPath + File.separator
        val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
        var entryCount = 0
        var extractedBytes = 0L

        while (true) {
            val entry = archive.nextEntry ?: break
            entryCount += 1
            require(entryCount <= MAX_ENTRY_COUNT) { "Archive contains too many entries" }

            val components =
                entry.name
                    .replace('\\', '/')
                    .split('/')
                    .filter(String::isNotEmpty)
            if (components.isEmpty() || components.first().equals("__MACOSX", ignoreCase = true)) {
                archive.closeEntry()
                continue
            }

            val output = File(destination, components.joinToString(File.separator)).canonicalFile
            require(output.path.startsWith(rootPath)) { "Archive entry escapes the game directory" }

            if (entry.isDirectory) {
                check(output.mkdirs() || output.isDirectory) { "Could not create ${output.path}" }
            } else {
                val parent = requireNotNull(output.parentFile)
                check(parent.mkdirs() || parent.isDirectory) { "Could not create ${parent.path}" }
                output.outputStream().buffered().use { fileOutput ->
                    while (true) {
                        val count = archive.read(buffer)
                        if (count < 0) break
                        extractedBytes += count
                        require(extractedBytes <= MAX_EXTRACTED_BYTES) { "Archive is too large" }
                        fileOutput.write(buffer, 0, count)
                    }
                }
            }
            archive.closeEntry()
        }
    }

    /** Descends through a single wrapper directory, matching the Apple resolver. */
    private fun preferredGameDirectory(root: File): File? {
        if (!root.isDirectory) return null
        var current = root
        while (true) {
            val contents =
                current
                    .listFiles()
                    ?.filterNot { it.name.equals("__MACOSX", ignoreCase = true) || it.isHidden }
                    .orEmpty()
            if (contents.isEmpty()) return null
            if (contents.size != 1 || !contents.single().isDirectory) return current
            current = contents.single()
        }
    }

    private fun queryDisplayName(uri: Uri): String? =
        contentResolver
            .query(
                uri,
                arrayOf(OpenableColumns.DISPLAY_NAME),
                null,
                null,
                null,
            )?.use { cursor: Cursor ->
                if (!cursor.moveToFirst()) return@use null
                cursor.getString(cursor.getColumnIndexOrThrow(OpenableColumns.DISPLAY_NAME))
            }

    private fun fnv1a64(value: String): ULong {
        var hash = 0xcbf29ce484222325uL
        value.encodeToByteArray().forEach { byte ->
            hash = (hash xor byte.toUByte().toULong()) * 0x100000001b3uL
        }
        return hash
    }

    private companion object {
        val ARCHIVE_EXTENSIONS = setOf("zip", "scummvm")
        const val ZIP_MIME_TYPE = "application/zip"
        const val MAX_ENTRY_COUNT = 100_000
        const val MAX_EXTRACTED_BYTES = 16L * 1024 * 1024 * 1024
    }
}
