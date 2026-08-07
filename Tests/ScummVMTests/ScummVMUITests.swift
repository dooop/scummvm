//
//  ScummVMUITests.swift
//  ScummVMTests
//
//  End-to-end UI tests for the public `ScummVM` SwiftUI view: mounts it in a
//  real NSWindow (the same onAppear/onDisappear lifecycle a host app drives)
//  and verifies it actually renders the engine's own GUI window, not just
//  that SwiftUI produced a placeholder view. Runs only on macOS, and only
//  against the prebuilt engine - see ci.yml's build-binary job, the only
//  place `swift test` runs in this repo.
//

#if os(macOS)
  import AppKit
  import SwiftUI
  @preconcurrency import XCTest

  import ScummVM
  @preconcurrency import ScummVMmacOS

  @MainActor
  final class ScummVMUITests: XCTestCase {
    private var hostWindow: NSWindow?

    override func tearDown() async throws {
      hostWindow?.close()
      hostWindow = nil

      // Safety net: a failed assertion mid-test should never leave the engine
      // running into the next test.
      ScummVMEngineSharedInstance().stop()
      XCTAssertTrue(
        ScummVMEngineWindowWaiter.waitUntil(timeout: 30) {
          ScummVMEngineWindowWaiter.engineWindows().isEmpty
        },
        "engine window still open after tearDown's stop()")
      try await super.tearDown()
    }

    func testMountingScummVMStartsAndRendersTheEngineWindow() {
      XCTAssertTrue(
        ScummVMEngineWindowWaiter.engineWindows().isEmpty,
        "no ScummVM window should exist before the view appears")

      let hostingController = NSHostingController(rootView: ScummVM())
      let window = NSWindow(contentViewController: hostingController)
      window.setContentSize(NSSize(width: 800, height: 600))
      window.makeKeyAndOrderFront(nil)
      hostWindow = window

      let didAppear = ScummVMEngineWindowWaiter.waitUntil(timeout: 30) {
        !ScummVMEngineWindowWaiter.engineWindows().isEmpty
      }
      XCTAssertTrue(didAppear, "mounting ScummVM() did not start and render the engine window")

      window.close()
      hostWindow = nil

      let didDisappear = ScummVMEngineWindowWaiter.waitUntil(timeout: 30) {
        ScummVMEngineWindowWaiter.engineWindows().isEmpty
      }
      XCTAssertTrue(didDisappear, "closing the host window did not stop the engine (onDisappear)")
    }

    func testMountingScummVMWithAGamePathStillRendersTheEngineWindow() throws {
      // No installed game matches this directory - the engine should fall
      // back to an empty launcher instead of crashing or blocking on a
      // dialog, exercising the --path/--auto-detect argument wiring.
      let gameDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ScummVMUITests-\(UUID().uuidString)", isDirectory: true)
      try FileManager.default.createDirectory(
        at: gameDirectory, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: gameDirectory) }
      try Data("not-a-real-game".utf8).write(
        to: gameDirectory.appendingPathComponent("dummy.dat"))

      let hostingController = NSHostingController(rootView: ScummVM(game: gameDirectory))
      let window = NSWindow(contentViewController: hostingController)
      window.setContentSize(NSSize(width: 800, height: 600))
      window.makeKeyAndOrderFront(nil)
      hostWindow = window

      let didAppear = ScummVMEngineWindowWaiter.waitUntil(timeout: 30) {
        !ScummVMEngineWindowWaiter.engineWindows().isEmpty
      }
      XCTAssertTrue(
        didAppear, "mounting ScummVM(game:) did not start and render the engine window")
    }
  }
#endif
