//
//  ScummVMGamePathResolverTests.swift
//  ScummVMTests
//

import XCTest

@testable import ScummVM

#if os(macOS)
  final class ScummVMGamePathResolverTests: XCTestCase {
    private var resolver: ScummVMGamePathResolver!
    private var tempDirectory: URL!

    override func setUpWithError() throws {
      resolver = ScummVMGamePathResolver()
      tempDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(
          "ScummVMGamePathResolverTests-\(UUID().uuidString)", isDirectory: true)
      try FileManager.default.createDirectory(
        at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
      try? FileManager.default.removeItem(at: tempDirectory)
    }

    func testNilGameResolvesToNil() async {
      let result = await resolver.resolveGamePath(nil)
      XCTAssertNil(result)
    }

    func testNonexistentPathResolvesToOriginalURL() async {
      let missingURL = tempDirectory.appendingPathComponent("does-not-exist.game")
      let result = await resolver.resolveGamePath(missingURL)
      XCTAssertEqual(result, missingURL)
    }

    func testDirectoryPassesThroughUnchangedOnMacOS() async throws {
      let directoryURL = tempDirectory.appendingPathComponent("GameDirectory", isDirectory: true)
      try FileManager.default.createDirectory(
        at: directoryURL, withIntermediateDirectories: true)
      try Data("data".utf8).write(to: directoryURL.appendingPathComponent("game.dat"))

      let result = await resolver.resolveGamePath(directoryURL)
      XCTAssertEqual(result?.standardizedFileURL, directoryURL.standardizedFileURL)
    }

    func testRegularFileIsImportedAndCachedOnRepeatedResolution() async throws {
      let sourceFile = tempDirectory.appendingPathComponent("game.d64")
      try Data("fixture-contents".utf8).write(to: sourceFile)

      guard let firstResolved = await resolver.resolveGamePath(sourceFile) else {
        XCTFail("Expected a resolved URL for an importable file")
        return
      }
      XCTAssertNotEqual(firstResolved.standardizedFileURL, sourceFile.standardizedFileURL)
      XCTAssertEqual(try Data(contentsOf: firstResolved), Data("fixture-contents".utf8))

      guard let secondResolved = await resolver.resolveGamePath(sourceFile) else {
        XCTFail("Expected the cached URL to resolve again")
        return
      }
      XCTAssertEqual(secondResolved, firstResolved)
    }

    func testZipArchiveIsExtractedAndDescendsIntoSingleTopLevelDirectory() async throws {
      let archiveURL = try makeZipFixture(named: "fixture-\(UUID().uuidString).zip")

      guard let resolved = await resolver.resolveGamePath(archiveURL) else {
        XCTFail("Expected archive extraction to resolve to a directory")
        return
      }

      XCTAssertEqual(resolved.lastPathComponent, "InnerGame")
      let extractedFile = resolved.appendingPathComponent("game.dat")
      XCTAssertEqual(try Data(contentsOf: extractedFile), Data("payload".utf8))
    }

    private func makeZipFixture(named archiveName: String) throws -> URL {
      let stagingRoot = tempDirectory.appendingPathComponent(
        "staging-\(UUID().uuidString)", isDirectory: true)
      let innerDirectory = stagingRoot.appendingPathComponent("InnerGame", isDirectory: true)
      try FileManager.default.createDirectory(
        at: innerDirectory, withIntermediateDirectories: true)
      try Data("payload".utf8).write(to: innerDirectory.appendingPathComponent("game.dat"))

      let archiveURL = tempDirectory.appendingPathComponent(archiveName)

      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
      process.currentDirectoryURL = stagingRoot
      process.arguments = ["-r", "-q", archiveURL.path, "InnerGame"]
      try process.run()
      process.waitUntilExit()

      guard process.terminationStatus == 0 else {
        throw NSError(
          domain: "ScummVMGamePathResolverTests", code: Int(process.terminationStatus))
      }

      return archiveURL
    }
  }
#endif
