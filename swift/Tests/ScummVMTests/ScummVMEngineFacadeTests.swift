//
//  ScummVMEngineFacadeTests.swift
//  ScummVMTests
//
//  Exercises the ObjC++ engine facade (`ScummVMEngine.h`) directly, one layer
//  below the SwiftUI wrapper. Runs only on macOS, and only against the
//  prebuilt engine - see ci.yml's build-binary job, the only place `swift
//  test` runs in this repo.
//

#if os(macOS)
  import AppKit
  @preconcurrency import XCTest

  @preconcurrency import ScummVMmacOS

  @MainActor
  final class ScummVMEngineFacadeTests: XCTestCase {
    override func tearDown() async throws {
      ScummVMEngineSharedInstance().stop()
      XCTAssertTrue(
        ScummVMEngineWindowWaiter.waitUntil(timeout: 30) {
          ScummVMEngineWindowWaiter.engineWindows().isEmpty
        },
        "engine window still open after tearDown's stop()")
      try await super.tearDown()
    }

    func testSharedInstanceIsAProcessWideSingleton() {
      let first = ScummVMEngineSharedInstance()
      let second = ScummVMEngineSharedInstance()
      XCTAssertTrue(first === second)
    }

    func testStoppingBeforeStartingIsANoOp() {
      ScummVMEngineSharedInstance().stop()
      XCTAssertTrue(ScummVMEngineWindowWaiter.engineWindows().isEmpty)
    }
  }
#endif
