import org.gradle.api.publish.maven.tasks.PublishToMavenRepository
import org.gradle.process.ExecOperations
import java.security.MessageDigest
import java.util.Properties
import javax.inject.Inject

plugins {
    alias(libs.plugins.android.library)
    // AGP 9 has Kotlin support built in (see android.enableKotlin below); the
    // standalone org.jetbrains.kotlin.android plugin must not be applied.
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.ktlint)
    `maven-publish`
}

group = "io.github.dooop"
version = providers.gradleProperty("scummvm.version").getOrElse("0.0.0-SNAPSHOT")

ktlint {
    android.set(true)
    outputToConsole.set(true)
}

// ---------------------------------------------------------------------------
// Upstream engine location
// ---------------------------------------------------------------------------
// Everything C/C++ and the JNI-facing Java classes are consumed straight out of
// the git submodule; nothing under scummvm is ever modified.
val upstreamDir: File = rootProject.file("scummvm")
val upstreamAndroidJavaDir = File(upstreamDir, "backends/platform/android/org/scummvm/scummvm")

require(File(upstreamDir, "configure").isFile) {
    "The ScummVM submodule is not checked out at ${upstreamDir.path}.\n" +
        "Run: git submodule update --init --recursive"
}

/**
 * Java sources vendored out of the upstream Android backend, relative to
 * `backends/platform/android/org/scummvm/scummvm/`.
 *
 * Deliberately a hand-picked subset rather than the whole tree: every file here
 * depends on neither `ScummVMActivity` nor any Android resource, so they can
 * ship inside a library AAR without dragging in upstream's launcher UI, its
 * manifest entries or its `res/` folder. `ScummVM.java` is the JNI contract with
 * `jni-android.cpp`, and the `net/` package is looked up by `FindClass` from
 * `backends/networking/basic/android/jni.cpp` (the Android port builds with
 * libcurl disabled and talks HTTP through Java); both must stay byte-identical
 * to upstream.
 *
 * Deliberately excluded: `ScummVMActivity`, `ScummVMEvents`, `SplashActivity`,
 * `ShortcutCreatorActivity`, `BackupManager`, the custom keyboard views and the
 * `zip/` package -- all of them are launcher-app concerns or need `R`.
 */
val upstreamJavaSources =
    listOf(
        "ScummVM.java",
        "CompatHelpers.java",
        "SAFFSTree.java",
        "ExternalStorage.java",
        "INIParser.java",
        "Version.java",
        "net/HTTPManager.java",
        "net/HTTPRequest.java",
        "net/LETrustManager.java",
        "net/SSocket.java",
        "net/TLSSocketFactory.java",
    )

val abis: List<String> =
    (providers.gradleProperty("scummvm.abis").orNull ?: "arm64-v8a")
        .split(",")
        .map(String::trim)
        .filter(String::isNotEmpty)

val prebuiltLibsDir: String? =
    providers
        .gradleProperty("scummvm.prebuiltLibsDir")
        .orNull
        ?.takeIf(String::isNotBlank)

android {
    namespace = "org.scummvm"
    compileSdk {
        version = release(37)
    }
    enableKotlin = true

    defaultConfig {
        minSdk = 21
        consumerProguardFiles("consumer-rules.pro")
    }

    buildFeatures {
        compose = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    packaging {
        // libscummvm.so is stripped by the upstream build already; let AGP pass
        // it through untouched rather than re-stripping it.
        jniLibs.keepDebugSymbols += "**/libscummvm.so"
    }

    lint {
        abortOnError = false
    }

    publishing {
        singleVariant("release") {
            withSourcesJar()
        }
    }
}

dependencies {
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.foundation)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.kotlinx.coroutines.android)
    // Referenced by the vendored upstream Java sources (@Keep, @NonNull, ...).
    api(libs.androidx.annotation)
}

// ---------------------------------------------------------------------------
// SDK / NDK discovery
// ---------------------------------------------------------------------------

// NDK r28+ builds 16 KB-aligned libraries (including libc++_shared.so) by
// default. Upstream still pins r23 for its standalone app, so this wrapper uses
// a generated configure copy that keeps every upstream check except the exact
// NDK revision comparison.
val ndkVersion: Provider<String> =
    providers
        .gradleProperty("scummvm.ndkVersion")
        .orElse("29.0.14206865")

fun localProperty(name: String): String? {
    val file = rootProject.file("local.properties")
    if (!file.isFile) return null
    val props = Properties()
    file.inputStream().use(props::load)
    return props.getProperty(name)?.takeIf(String::isNotBlank)
}

fun resolveSdkDir(): File {
    val candidate =
        localProperty("sdk.dir")
            ?: System.getenv("ANDROID_SDK_ROOT")
            ?: System.getenv("ANDROID_HOME")
            ?: error(
                "Android SDK not found. Set sdk.dir in local.properties or export ANDROID_SDK_ROOT.",
            )
    return File(candidate).also {
        require(it.isDirectory) { "Android SDK directory does not exist: $it" }
    }
}

fun resolveNdkDir(): File {
    val version = ndkVersion.get()
    val major = version.substringBefore('.').toIntOrNull()
    require(major != null && major >= 28) {
        "scummvm.ndkVersion must be r28 or newer for 16 KB page-size support (was $version)."
    }
    val candidate =
        localProperty("ndk.dir")
            ?: System.getenv("ANDROID_NDK_ROOT")
            ?: System.getenv("ANDROID_NDK_HOME")
            ?: File(resolveSdkDir(), "ndk/$version").path
    val dir = File(candidate)
    require(dir.isDirectory) {
        "Android NDK $version not found at $dir.\n" +
            "Install it with:\n" +
            "  \"\$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager\" \"ndk;$version\"\n" +
            "or point ANDROID_NDK_ROOT at an existing install of that revision."
    }
    val revision =
        File(dir, "source.properties")
            .takeIf(File::isFile)
            ?.readLines()
            ?.firstOrNull { it.startsWith("Pkg.Revision") }
            ?.substringAfter('=')
            ?.trim()
    require(revision == null || revision == version) {
        "The configured ScummVM NDK is $version but $dir is $revision.\n" +
            "Install that exact revision or update scummvm.ndkVersion."
    }
    return dir
}

fun resolveCxxRuntime(abi: String): File {
    // A fully self-contained prebuilt directory may supply the runtime used to
    // link its libraries. Prefer that exact copy when it is available.
    prebuiltLibsDir?.let { root ->
        val alongside = File(root, "$abi/libc++_shared.so")
        if (alongside.isFile) return alongside
    }

    val targetTriple =
        when (abi) {
            "armeabi-v7a" -> "arm-linux-androideabi"
            "arm64-v8a" -> "aarch64-linux-android"
            "x86" -> "i686-linux-android"
            "x86_64" -> "x86_64-linux-android"
            else -> error("Unsupported Android ABI: $abi")
        }
    val prebuiltRoot = File(resolveNdkDir(), "toolchains/llvm/prebuilt")
    val runtime =
        prebuiltRoot
            .listFiles()
            .orEmpty()
            .asSequence()
            .filter(File::isDirectory)
            .map { host -> File(host, "sysroot/usr/lib/$targetTriple/libc++_shared.so") }
            .firstOrNull(File::isFile)

    return requireNotNull(runtime) {
        "libc++_shared.so for $abi was not found under ${prebuiltRoot.path}.\n" +
            "Install the required NDK or place it next to the prebuilt engine at " +
            "<scummvm.prebuiltLibsDir>/$abi/libc++_shared.so."
    }
}

// ---------------------------------------------------------------------------
// Oboe
// ---------------------------------------------------------------------------
// Upstream's Android mixer backend links against Oboe (`-loboe`, appended by
// `configure` for the android host; see backends/mixer/android/android-mixer.cpp
// and configure's android host block). It isn't part of the submodule, and
// this build shells out to upstream's own configure/make rather than
// reimplementing it via AGP's native/CMake integration, so there is no
// automatic Prefab wiring -- fetch the AAR from Google's Maven repository
// ourselves and pass its headers/libs to configure via CPPFLAGS/LDFLAGS.
val oboeVersion = "1.10.0"

val oboe: Configuration by configurations.creating {
    isCanBeConsumed = false
    isCanBeResolved = true
}

dependencies {
    oboe("com.google.oboe:oboe:$oboeVersion")
}

val oboeDir: Provider<Directory> = layout.buildDirectory.dir("oboe")

val extractOboe =
    tasks.register<Copy>("extractOboe") {
        group = "scummvm"
        description = "Unpacks the Oboe AAR's Prefab headers and per-ABI libraries."
        from({ project.zipTree(oboe.singleFile) })
        into(oboeDir)
    }

fun oboeIncludeDir(): Provider<String> = oboeDir.map { it.dir("prefab/modules/oboe/include").asFile.absolutePath }

fun oboeLibDir(abi: String): Provider<String> =
    oboeDir.map { it.dir("prefab/modules/oboe/libs/android.$abi").asFile.absolutePath }

// ---------------------------------------------------------------------------
// Task types
// ---------------------------------------------------------------------------

/**
 * Copies an explicit set of files into a generated source/asset/jniLibs folder.
 *
 * The layout is spelled out file by file rather than as copy specs so that the
 * task has precise inputs -- Gradle must never be asked to snapshot the ~2 GB
 * engine submodule.
 */
abstract class StageFiles : DefaultTask() {
    @get:Inject abstract val fs: FileSystemOperations

    /** Destination path (relative to [outputDir]) -> absolute source path. */
    @get:Input abstract val entries: MapProperty<String, String>

    /** Same files again, so Gradle tracks their contents and producing tasks. */
    @get:InputFiles
    @get:PathSensitive(PathSensitivity.NONE)
    abstract val sourceFiles: ConfigurableFileCollection

    /**
     * Writes the `MD5SUMS` manifest upstream's `android.mk` generates, which
     * `ScummVMAssets` uses to decide whether to re-extract on the device.
     */
    @get:Input abstract val writeChecksums: Property<Boolean>

    @get:OutputDirectory abstract val outputDir: DirectoryProperty

    @TaskAction
    fun stage() {
        val out = outputDir.get().asFile
        fs.delete { delete(out) }
        out.mkdirs()

        entries.get().forEach { (relative, source) ->
            val target = File(out, relative)
            target.parentFile?.mkdirs()
            File(source).copyTo(target, overwrite = true)
        }

        if (!writeChecksums.get()) return

        val manifest =
            out
                .walkTopDown()
                .filter(File::isFile)
                .map { md5(it) to it.relativeTo(out).invariantSeparatorsPath }
                .sortedBy { it.second }
                .joinToString("\n", postfix = "\n") { (digest, path) -> "$digest  $path" }
        File(out, "MD5SUMS").writeText(manifest)
    }

    private fun md5(file: File): String {
        val digest = MessageDigest.getInstance("MD5")
        file.inputStream().use { input ->
            val buffer = ByteArray(64 * 1024)
            while (true) {
                val read = input.read(buffer)
                if (read <= 0) break
                digest.update(buffer, 0, read)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }
}

abstract class ScummVMConfigure : DefaultTask() {
    @get:Inject abstract val execOps: ExecOperations

    @get:Input abstract val abi: Property<String>

    @get:Input abstract val extraArgs: ListProperty<String>

    @get:Input abstract val sdkDir: Property<String>

    @get:Input abstract val ndkDir: Property<String>

    @get:Input abstract val oboeIncludeDir: Property<String>

    @get:Input abstract val oboeLibDir: Property<String>

    @get:Internal abstract val configurePath: Property<String>

    @get:Internal abstract val nativeBuildDir: DirectoryProperty

    @get:OutputFile abstract val configMk: RegularFileProperty

    @TaskAction
    fun run() {
        val workDir = nativeBuildDir.get().asFile
        workDir.mkdirs()
        val args =
            buildList {
                add(configurePath.get())
                add("--host=android-${abi.get()}")
                addAll(extraArgs.get())
            }
        logger.lifecycle("ScummVM configure (${abi.get()}): ${args.joinToString(" ")}")
        execOps.exec {
            workingDir = workDir
            commandLine(args)
            environment("ANDROID_SDK_ROOT", sdkDir.get())
            environment("ANDROID_NDK_ROOT", ndkDir.get())
            // Picked up by configure (folded into CXXFLAGS/LDFLAGS and baked
            // into the generated config.mk) so android-mixer.cpp finds Oboe.
            // Keep both flags explicit even though NDK r28+ applies them by
            // default. This also protects the build if upstream changes flags.
            environment("CPPFLAGS", "-I${oboeIncludeDir.get()}")
            environment(
                "LDFLAGS",
                "-L${oboeLibDir.get()} -Wl,-z,max-page-size=16384 " +
                    "-Wl,-z,common-page-size=16384",
            )
        }
    }
}

abstract class ScummVMMake : DefaultTask() {
    @get:Inject abstract val execOps: ExecOperations

    @get:Input abstract val jobs: Property<Int>

    @get:Input abstract val sdkDir: Property<String>

    @get:Input abstract val ndkDir: Property<String>

    @get:Internal abstract val nativeBuildDir: DirectoryProperty

    @get:OutputFile abstract val library: RegularFileProperty

    @TaskAction
    fun run() {
        execOps.exec {
            workingDir = nativeBuildDir.get().asFile
            commandLine(listOf("make", "-j${jobs.get()}", "libscummvm.so"))
            environment("ANDROID_SDK_ROOT", sdkDir.get())
            environment("ANDROID_NDK_ROOT", ndkDir.get())
        }
    }
}

// ---------------------------------------------------------------------------
// Native build: upstream ./configure + make, one out-of-tree build per ABI
// ---------------------------------------------------------------------------

val configureArgs: List<String> =
    (providers.gradleProperty("scummvm.configureArgs").orNull ?: "")
        .split(Regex("\\s+"))
        .filter(String::isNotEmpty)

val makeJobs: Int =
    providers
        .gradleProperty("scummvm.buildJobs")
        .orNull
        ?.toIntOrNull()
        ?: Runtime.getRuntime().availableProcessors()

// Resolved lazily so a `-Pscummvm.prebuiltLibsDir` build never needs an NDK.
val sdkDirProvider: Provider<String> = providers.provider { resolveSdkDir().absolutePath }
val ndkDirProvider: Provider<String> = providers.provider { resolveNdkDir().absolutePath }

val generatedConfigure = layout.buildDirectory.file("generated/scummvm-configure/configure")
val prepareScummVMConfigure =
    tasks.register("prepareScummVMConfigure") {
        group = "scummvm"
        description = "Generates a configure script that permits the wrapper's modern Android NDK."
        val upstreamConfigure = File(upstreamDir, "configure")
        inputs.file(upstreamConfigure)
        inputs.property("ndkVersion", ndkVersion)
        outputs.file(generatedConfigure)

        doLast {
            val sourceDir = upstreamDir.absolutePath.replace("'", "'\\''")
            var script = upstreamConfigure.readText()
            val sourceAssignment = "_srcdir=`dirname \$0`"
            require(script.contains(sourceAssignment)) { "Could not locate _srcdir in upstream configure" }
            script = script.replace(sourceAssignment, "_srcdir='$sourceDir'", ignoreCase = false)

            val checkStart = "\t# Check that we have the correct NDK version"
            val checkEnd = "\n\t# Try to use a known to work toolchain"
            val start = script.indexOf(checkStart)
            val end = script.indexOf(checkEnd, startIndex = start)
            require(start >= 0 && end > start) {
                "Could not locate the upstream Android NDK version check in configure"
            }
            val replacement =
                "\t# The Compose wrapper deliberately supports a newer NDK than the standalone\n" +
                    "\t# upstream Android project so all ELF files support 16 KB pages.\n" +
                    "\techo \"Using wrapper-selected Android NDK: ${ndkVersion.get()}\""
            script = script.replaceRange(start, end, replacement)

            val output = generatedConfigure.get().asFile
            output.parentFile.mkdirs()
            output.writeText(script)
            output.setExecutable(true)
        }
    }

val nativeLibraryTasks: Map<String, TaskProvider<ScummVMMake>> =
    if (prebuiltLibsDir != null) {
        emptyMap()
    } else {
        abis.associateWith { abi ->
            val suffix =
                abi.split(Regex("[-_]")).joinToString("") { part ->
                    part.replaceFirstChar(Char::uppercaseChar)
                }
            val nativeBuild = layout.buildDirectory.dir("native/${ndkVersion.get()}/$abi")

            val configureTask =
                tasks.register<ScummVMConfigure>("configureScummVM$suffix") {
                    group = "scummvm"
                    description = "Runs upstream ./configure for $abi."
                    this.abi.set(abi)
                    extraArgs.set(configureArgs)
                    sdkDir.set(sdkDirProvider)
                    ndkDir.set(ndkDirProvider)
                    oboeIncludeDir.set(oboeIncludeDir())
                    oboeLibDir.set(oboeLibDir(abi))
                    configurePath.set(generatedConfigure.map { it.asFile.absolutePath })
                    nativeBuildDir.set(nativeBuild)
                    configMk.set(nativeBuild.map { it.file("config.mk") })
                    dependsOn(extractOboe, prepareScummVMConfigure)
                }

            tasks.register<ScummVMMake>("buildScummVM$suffix") {
                group = "scummvm"
                description = "Builds libscummvm.so for $abi."
                dependsOn(configureTask)
                jobs.set(makeJobs)
                sdkDir.set(sdkDirProvider)
                ndkDir.set(ndkDirProvider)
                nativeBuildDir.set(nativeBuild)
                library.set(nativeBuild.map { it.file("libscummvm.so") })
                // `make` is already incremental and knows far better than Gradle
                // whether 3000+ translation units are stale, so always defer to it.
                outputs.upToDateWhen { false }
            }
        }
    }

// ---------------------------------------------------------------------------
// Generated sources, assets and jniLibs
// ---------------------------------------------------------------------------

val stageUpstreamJava =
    tasks.register<StageFiles>("stageUpstreamJava") {
        group = "scummvm"
        description = "Copies the JNI-facing upstream Java classes into the build."
        writeChecksums.set(false)
        upstreamJavaSources.forEach { relative ->
            val source = File(upstreamAndroidJavaDir, relative)
            require(source.isFile) {
                "Upstream Java source $relative is missing from ${upstreamAndroidJavaDir.path}.\n" +
                    "Re-check upstreamJavaSources in android/scummvm/build.gradle.kts after a submodule sync."
            }
            entries.put("org/scummvm/scummvm/$relative", source.absolutePath)
            sourceFiles.from(source)
        }
    }

/**
 * Runtime data the engine loads by path: themes, engine data, soundfonts, the
 * virtual keyboard packs and the bundled documentation.
 *
 * Everything lands under `assets/`, which `ScummVMAssets` unpacks to
 * `<filesDir>/assets` and hands to the engine as its sys-archive search path.
 * The lists mirror `DIST_FILES_*` in upstream's `Makefile.common`.
 */
val stageAssets =
    tasks.register<StageFiles>("stageScummVMAssets") {
        group = "scummvm"
        description = "Stages ScummVM's runtime data files as library assets."
        writeChecksums.set(true)

        fun stage(
            sourceDir: File,
            destination: String,
            filter: (File) -> Boolean,
        ) {
            val files = sourceDir.listFiles()?.filter { it.isFile && filter(it) }.orEmpty()
            require(files.isNotEmpty()) { "No files matched in ${sourceDir.path}" }
            files.forEach { file ->
                entries.put("$destination/${file.name}", file.absolutePath)
                sourceFiles.from(file)
            }
        }

        fun named(
            sourceDir: File,
            destination: String,
            vararg names: String,
        ) = stage(sourceDir, destination) { it.name in names }

        named(
            File(upstreamDir, "gui/themes"),
            "assets",
            "scummmodern.zip",
            "scummclassic.zip",
            "scummremastered.zip",
            "residualvm.zip",
            "gui-icons.dat",
            "shaders.dat",
            "translations.dat",
        )
        // Top-level payload files only: engine-data's fonts/ and patches/ folders are
        // build inputs for the .dat bundles, and *.mk / *.sh / README are plumbing.
        stage(File(upstreamDir, "dists/engine-data"), "assets") { file ->
            file.extension !in setOf("mk", "sh") && file.name != "README"
        }
        named(File(upstreamDir, "dists/networking"), "assets", "wwwroot.zip")
        named(
            File(upstreamDir, "dists/soundfonts"),
            "assets",
            "Roland_SC-55.sf2",
            "COPYRIGHT.Roland_SC-55",
        )
        named(
            File(upstreamDir, "backends/vkeybd/packs"),
            "assets",
            "vkeybd_default.zip",
            "vkeybd_small.zip",
        )
        named(File(upstreamDir, "dists/android"), "assets", "android-help.zip", "gamepad.svg")
        named(File(upstreamDir, "dists"), "assets", "pred.dic")
        named(upstreamDir, "doc", "COPYING", "COPYRIGHT", "AUTHORS", "NEWS.md", "README.md")
    }

val stageJniLibs =
    tasks.register<StageFiles>("stageScummVMJniLibs") {
        group = "scummvm"
        description = "Stages ScummVM, Oboe, and the shared C++ runtime into jniLibs."
        writeChecksums.set(false)
        dependsOn(extractOboe)

        if (prebuiltLibsDir != null) {
            val root = file(prebuiltLibsDir)
            abis.forEach { abi ->
                val library = File(root, "$abi/libscummvm.so")
                require(library.isFile) {
                    "scummvm.prebuiltLibsDir is set but ${library.path} is missing."
                }
                entries.put("$abi/libscummvm.so", library.absolutePath)
                sourceFiles.from(library)
            }
        } else {
            nativeLibraryTasks.forEach { (abi, makeTask) ->
                val library = makeTask.flatMap { it.library }
                entries.put("$abi/libscummvm.so", library.map { it.asFile.absolutePath })
                sourceFiles.from(library)
            }
        }

        abis.forEach { abi ->
            val oboeLibrary =
                oboeDir.map {
                    it.file("prefab/modules/oboe/libs/android.$abi/liboboe.so").asFile
                }
            entries.put("$abi/liboboe.so", oboeLibrary.map { it.absolutePath })
            sourceFiles.from(oboeLibrary)

            val cxxRuntime = providers.provider { resolveCxxRuntime(abi) }
            entries.put("$abi/libc++_shared.so", cxxRuntime.map { it.absolutePath })
            sourceFiles.from(cxxRuntime)
        }
    }

androidComponents {
    onVariants { variant ->
        // addGeneratedSourceDirectory picks the output location and wires the
        // task dependency, so these folders are always built before they are read.
        variant.sources.java?.addGeneratedSourceDirectory(stageUpstreamJava, StageFiles::outputDir)
        variant.sources.assets?.addGeneratedSourceDirectory(stageAssets, StageFiles::outputDir)
        variant.sources.jniLibs?.addGeneratedSourceDirectory(stageJniLibs, StageFiles::outputDir)
    }
}

// ---------------------------------------------------------------------------
// Maven publication
// ---------------------------------------------------------------------------

publishing {
    publications {
        register<MavenPublication>("release") {
            artifactId = "scummvm"

            afterEvaluate {
                from(components["release"])
            }

            pom {
                name.set("ScummVM Android")
                description.set("Android AAR and Jetpack Compose host for the ScummVM engine.")
                url.set("https://github.com/dooop/scummvm")
                licenses {
                    license {
                        name.set("GNU General Public License v3.0 or later")
                        url.set("https://www.gnu.org/licenses/gpl-3.0.html")
                        distribution.set("repo")
                    }
                }
                developers {
                    developer {
                        id.set("dooop")
                        name.set("Dominic Szablewski")
                    }
                }
                scm {
                    connection.set("scm:git:https://github.com/dooop/scummvm.git")
                    developerConnection.set("scm:git:ssh://git@github.com/dooop/scummvm.git")
                    url.set("https://github.com/dooop/scummvm")
                }
            }
        }
    }

    repositories {
        maven {
            name = "GitHubPackages"
            url =
                uri(
                    "https://maven.pkg.github.com/" +
                        providers.gradleProperty("scummvm.githubRepository").getOrElse("dooop/scummvm"),
                )
            credentials {
                username =
                    providers
                        .gradleProperty("gpr.user")
                        .orElse(providers.environmentVariable("GITHUB_ACTOR"))
                        .orNull
                password =
                    providers
                        .gradleProperty("gpr.key")
                        .orElse(providers.environmentVariable("GITHUB_TOKEN"))
                        .orNull
            }
        }
    }
}

tasks.withType<PublishToMavenRepository>().configureEach {
    doFirst {
        require(project.version != "0.0.0-SNAPSHOT") {
            "Publishing requires an explicit version, for example -Pscummvm.version=1.2.3."
        }
    }
}
