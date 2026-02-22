//
//  ScummVMGamePathResolver.swift
//  ScummVM
//
//  Created by Dominic Opitz on 2/22/26.
//

import Foundation
import ZIPFoundation

actor ScummVMGamePathResolver {
  private static let supportedArchiveExtensions: Set<String> = ["zip", "scummvm"]

  func resolveGamePath(_ gamePath: URL?) async -> URL? {
    guard let sourceURL = gamePath else { return nil }
    guard sourceURL.isFileURL else {
      print("ScummVM: Unsupported non-file game URL: \(sourceURL)")
      return nil
    }

    let fileManager = FileManager.default
    var isDirectory: ObjCBool = false

    guard fileManager.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory) else {
      return sourceURL
    }

    if isDirectory.boolValue {
      #if os(iOS) || os(tvOS)
        do {
          if Task.isCancelled {
            return sourceURL
          }

          let launchDirectory = try importDirectoryIfNeeded(at: sourceURL, using: fileManager)
          guard try isUsableGamePath(launchDirectory, using: fileManager) else {
            print("ScummVM: Imported directory path missing or empty at \(launchDirectory.path)")
            return sourceURL
          }
          return launchDirectory
        } catch {
          print("ScummVM: Failed to import directory at \(sourceURL.path): \(error)")
          return sourceURL
        }
      #else
        return sourceURL
      #endif
    }

    guard Self.supportedArchiveExtensions.contains(sourceURL.pathExtension.lowercased()) else {
      do {
        if Task.isCancelled {
          return sourceURL
        }

        let importedFileURL = try importFileIfNeeded(at: sourceURL, using: fileManager)
        guard try isUsableGamePath(importedFileURL, using: fileManager) else {
          print("ScummVM: Imported file path missing at \(importedFileURL.path)")
          return sourceURL
        }
        return importedFileURL
      } catch {
        print("ScummVM: Failed to import file at \(sourceURL.path): \(error)")
        return sourceURL
      }
    }

    do {
      if Task.isCancelled {
        return sourceURL
      }

      let extractedDirectory = try extractArchive(at: sourceURL, using: fileManager)
      guard try isUsableGamePath(extractedDirectory, using: fileManager) else {
        print("ScummVM: Extracted path missing or empty at \(extractedDirectory.path)")
        return sourceURL
      }
      return extractedDirectory
    } catch {
      print("ScummVM: Failed to extract archive at \(sourceURL.path): \(error)")
      return sourceURL
    }
  }

  private func extractArchive(at archiveURL: URL, using fileManager: FileManager) throws -> URL {
    let extractionRoot = try extractionRootDirectory(using: fileManager)
    let destination = extractionRoot.appendingPathComponent(
      Self.extractionDirectoryName(for: archiveURL),
      isDirectory: true
    )

    if fileManager.fileExists(atPath: destination.path) {
      let cachedDirectory = try preferredGameDirectory(in: destination, using: fileManager)
      if try isUsableGamePath(cachedDirectory, using: fileManager) {
        return cachedDirectory
      }

      try? fileManager.removeItem(at: destination)
    }

    try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
    try fileManager.unzipItem(at: archiveURL, to: destination)

    let extractedDirectory = try preferredGameDirectory(in: destination, using: fileManager)
    if !(try isUsableGamePath(extractedDirectory, using: fileManager)) {
      throw CocoaError(.fileNoSuchFile)
    }
    return extractedDirectory
  }

  private func importFileIfNeeded(at sourceURL: URL, using fileManager: FileManager) throws -> URL {
    if try isManagedLaunchPath(sourceURL, using: fileManager) {
      return sourceURL
    }

    let importRoot = try importedFilesRootDirectory(using: fileManager)
    let destination = importRoot.appendingPathComponent(
      Self.importedFileName(for: sourceURL),
      isDirectory: false
    )

    if fileManager.fileExists(atPath: destination.path) {
      if try isUsableGamePath(destination, using: fileManager) {
        return destination
      }

      try? fileManager.removeItem(at: destination)
    }

    try fileManager.copyItem(at: sourceURL, to: destination)

    if !(try isUsableGamePath(destination, using: fileManager)) {
      throw CocoaError(.fileNoSuchFile)
    }

    return destination
  }

  #if os(iOS) || os(tvOS)
    private func importDirectoryIfNeeded(at sourceURL: URL, using fileManager: FileManager) throws
      -> URL
    {
      if try isLaunchableInPlaceOnSandboxedPlatforms(sourceURL, using: fileManager) {
        return sourceURL
      }

      let importRoot = try importedDirectoriesRootDirectory(using: fileManager)
      let destination = importRoot.appendingPathComponent(
        Self.extractionDirectoryName(for: sourceURL),
        isDirectory: true
      )

      if fileManager.fileExists(atPath: destination.path) {
        if try isUsableGamePath(destination, using: fileManager) {
          return destination
        }

        try? fileManager.removeItem(at: destination)
      }

      try fileManager.copyItem(at: sourceURL, to: destination)

      if !(try isUsableGamePath(destination, using: fileManager)) {
        throw CocoaError(.fileNoSuchFile)
      }

      return destination
    }

    private func importedDirectoriesRootDirectory(using fileManager: FileManager) throws -> URL {
      try importedContentRootDirectory(named: "ImportedDirectories", using: fileManager)
    }

    private func runtimeLaunchRootDirectory(using fileManager: FileManager) throws -> URL {
      let directory: FileManager.SearchPathDirectory = {
        #if os(tvOS)
          .cachesDirectory
        #else
          .documentDirectory
        #endif
      }()

      return try fileManager.url(
        for: directory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
      )
    }

    private func isLaunchableInPlaceOnSandboxedPlatforms(
      _ sourceURL: URL, using fileManager: FileManager
    )
      throws -> Bool
    {
      let runtimeRootURL = try runtimeLaunchRootDirectory(using: fileManager)

      if Self.path(sourceURL, isWithin: runtimeRootURL) {
        return true
      }

      #if os(iOS)
        if let bundleResourceURL = Bundle.main.resourceURL,
          Self.path(sourceURL, isWithin: bundleResourceURL)
        {
          return true
        }
      #elseif os(tvOS)
        if let bundleResourceURL = Bundle.main.resourceURL,
          Self.path(sourceURL, isWithin: bundleResourceURL)
        {
          return true
        }
      #endif

      return false
    }
  #endif

  private func importedFilesRootDirectory(using fileManager: FileManager) throws -> URL {
    try importedContentRootDirectory(named: "ImportedFiles", using: fileManager)
  }

  private func extractionRootDirectory(using fileManager: FileManager) throws -> URL {
    try importedContentRootDirectory(named: "ImportedArchives", using: fileManager)
  }

  private func managedContentBaseDirectory(using fileManager: FileManager) throws -> URL {
    let baseURL: URL
    #if os(iOS)
      baseURL = try fileManager.url(
        for: .documentDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
      )
    #elseif os(tvOS)
      baseURL = try fileManager.url(
        for: .cachesDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
      )
    #else
      baseURL = try fileManager.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
      )
    #endif

    let rootURL = baseURL.appendingPathComponent("ScummVM", isDirectory: true)
    try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
    return rootURL
  }

  private func importedContentRootDirectory(
    named leafDirectory: String, using fileManager: FileManager
  )
    throws -> URL
  {
    let rootURL = try managedContentBaseDirectory(using: fileManager)
      .appendingPathComponent(leafDirectory, isDirectory: true)
    try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
    return rootURL
  }

  private func isManagedLaunchPath(_ sourceURL: URL, using fileManager: FileManager) throws -> Bool {
    let managedContentBaseURL = try managedContentBaseDirectory(using: fileManager)
    if Self.path(sourceURL, isWithin: managedContentBaseURL) {
      return true
    }

    if let bundleResourceURL = Bundle.main.resourceURL,
      Self.path(sourceURL, isWithin: bundleResourceURL)
    {
      return true
    }

    return false
  }

  private func preferredGameDirectory(in extractionDirectory: URL, using fileManager: FileManager)
    throws
    -> URL
  {
    var currentDirectory = extractionDirectory

    while true {
      let contents = try meaningfulContents(in: currentDirectory, using: fileManager)

      guard contents.count == 1 else {
        return currentDirectory
      }

      let onlyItem = contents[0]
      let values = try onlyItem.resourceValues(forKeys: [.isDirectoryKey])
      guard values.isDirectory == true else {
        return currentDirectory
      }

      currentDirectory = onlyItem
    }
  }

  private func meaningfulContents(in directory: URL, using fileManager: FileManager) throws -> [URL]
  {
    try fileManager.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles]
    ).filter { !Self.shouldIgnoreExtractedEntry(named: $0.lastPathComponent) }
  }

  private func isUsableGamePath(_ path: URL, using fileManager: FileManager) throws -> Bool {
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: path.path, isDirectory: &isDirectory) else {
      return false
    }

    if !isDirectory.boolValue {
      return true
    }

    let contents = try meaningfulContents(in: path, using: fileManager)
    return !contents.isEmpty
  }

  private static func shouldIgnoreExtractedEntry(named name: String) -> Bool {
    switch name.lowercased() {
    case "__macosx":
      return true
    default:
      return false
    }
  }

  private static func extractionDirectoryName(for archiveURL: URL) -> String {
    let baseName = archiveURL.deletingPathExtension().lastPathComponent
    let sanitizedBaseName = sanitizedPathComponent(baseName)
    let hash = fnv1a64(archiveURL.standardizedFileURL.path)
    return "\(sanitizedBaseName)-\(String(hash, radix: 16))"
  }

  private static func importedFileName(for fileURL: URL) -> String {
    let baseName = fileURL.deletingPathExtension().lastPathComponent
    let fileExtension = fileURL.pathExtension
    let sanitizedBaseName = sanitizedPathComponent(baseName)
    let hash = fnv1a64(fileURL.standardizedFileURL.path)
    let stem = "\(sanitizedBaseName)-\(String(hash, radix: 16))"

    guard !fileExtension.isEmpty else {
      return stem
    }

    return "\(stem).\(fileExtension)"
  }

  private static func sanitizedPathComponent(_ value: String) -> String {
    value.replacingOccurrences(of: "/", with: "-")
  }

  private static func fnv1a64(_ string: String) -> UInt64 {
    let offsetBasis: UInt64 = 0xcbf2_9ce4_8422_2325
    let prime: UInt64 = 0x100_0000_01b3
    var hash = offsetBasis

    for byte in string.utf8 {
      hash = (hash ^ UInt64(byte)) &* prime
    }

    return hash
  }

  private static func path(_ childURL: URL, isWithin parentURL: URL) -> Bool {
    let childPath = childURL.resolvingSymlinksInPath().standardizedFileURL.path
    let parentPath = parentURL.resolvingSymlinksInPath().standardizedFileURL.path

    if childPath == parentPath {
      return true
    }

    let parentPrefix = parentPath.hasSuffix("/") ? parentPath : "\(parentPath)/"
    return childPath.hasPrefix(parentPrefix)
  }
}
