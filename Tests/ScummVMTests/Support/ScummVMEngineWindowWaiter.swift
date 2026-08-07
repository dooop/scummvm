//
//  ScummVMEngineWindowWaiter.swift
//  ScummVMTests
//

#if os(macOS)
  import AppKit
  import Foundation

  /// Polls the process's on-screen windows to observe the real engine GUI
  /// (a separate SDL-owned NSWindow, not anything SwiftUI/ScummVMView renders
  /// itself) starting and stopping. Every wait is bounded by `timeout` so a
  /// stuck engine fails the test instead of hanging the run.
  @MainActor
  enum ScummVMEngineWindowWaiter {
    /// The engine's main GUI window uses this title by default (see
    /// `sdl-window.cpp`'s `_windowCaption`).
    static let engineWindowTitle = "ScummVM"

    static func engineWindows() -> [NSWindow] {
      NSApplication.shared.windows.filter { $0.title == engineWindowTitle }
    }

    @discardableResult
    static func waitUntil(
      timeout: TimeInterval,
      pollInterval: TimeInterval = 0.05,
      condition: () -> Bool
    ) -> Bool {
      let deadline = Date().addingTimeInterval(timeout)
      while !condition() {
        if Date() >= deadline {
          return condition()
        }
        // Drains the main dispatch queue (where the engine's start/stop work is
        // dispatched) and AppKit's window/event bookkeeping.
        RunLoop.main.run(until: Date().addingTimeInterval(pollInterval))
      }
      return true
    }
  }
#endif
