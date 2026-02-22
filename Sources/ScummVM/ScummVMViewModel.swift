//
//  ScummVM.swift
//  ScummVM
//
//  Created by Dominic Opitz on 2/22/26.
//

import Foundation
import SwiftUI

#if os(tvOS)
  import ScummVMtvOS
#elseif os(iOS)
  import ScummVMiOS
#elseif os(macOS)
  import ScummVMmacOS
#endif

@MainActor
final class ScummVMViewModel: ObservableObject {
  private enum DesiredEngineState: Equatable {
    case stopped
    case running
  }

  private enum LifecyclePhase: Equatable {
    case idle
    case resolvingPath(startToken: UInt64)
    case startRequested(startToken: UInt64)
    case stopRequested
  }

  private var gamePath: URL?
  private let pathResolver = ScummVMGamePathResolver()
  private var startTask: Task<Void, Never>?
  private var desiredEngineState: DesiredEngineState = .stopped
  private var lifecyclePhase: LifecyclePhase = .idle
  private var nextStartToken: UInt64 = 1
  #if os(iOS)
    private var attachedHostViewCount = 0
    private var lastObservedScenePhase: ScenePhase = .active
  #endif

  #if os(iOS)
    static let sharedIOSHost = ScummVMViewModel(gamePath: nil)
  #endif

  init(gamePath: URL?) {
    self.gamePath = gamePath
    _ = ScummVMEngineSharedInstance()
  }

  deinit {
    startTask?.cancel()
    ScummVMEngineSharedInstance().stop()
  }

  func start() {
    desiredEngineState = .running

    switch lifecyclePhase {
    case .idle:
      beginStartResolution()
    case .stopRequested:
      beginStartResolution()
    case .resolvingPath, .startRequested:
      return
    }
  }

  #if os(iOS)
    func hostAttach(gamePath: URL?, scenePhase: ScenePhase) {
      attachedHostViewCount += 1
      lastObservedScenePhase = scenePhase
      setGamePathWithoutLaunching(gamePath)

      // iOS host policy: view attachment expresses intent to keep the runtime available.
      desiredEngineState = .running
      if scenePhase == .active {
        start()
      }
    }

    func hostDetach(scenePhase: ScenePhase) {
      lastObservedScenePhase = scenePhase
      attachedHostViewCount = max(0, attachedHostViewCount - 1)
      // If the last visible host goes away while the app is still active, treat it as an
      // explicit user close and issue a best-effort stop.
      if attachedHostViewCount == 0 && scenePhase == .active {
        hostExplicitStop()
      }
    }

    func hostScenePhaseChanged(_ scenePhase: ScenePhase) {
      lastObservedScenePhase = scenePhase

      guard attachedHostViewCount > 0 else {
        return
      }

      switch scenePhase {
      case .active:
        start()
      case .inactive:
        // Avoid full stop on transient lifecycle changes.
        break
      case .background:
        // Best-effort stop when the app actually backgrounds.
        hostExplicitStop()
      @unknown default:
        break
      }
    }

    func hostUpdateGamePath(_ gamePath: URL?) {
      let shouldAttemptLaunch = attachedHostViewCount > 0 && lastObservedScenePhase == .active
      if shouldAttemptLaunch {
        updateGamePath(gamePath)
      } else {
        setGamePathWithoutLaunching(gamePath)
      }
    }

    func hostExplicitStop() {
      stop()
    }
  #endif

  func updateGamePath(_ gamePath: URL?) {
    guard self.gamePath != gamePath else {
      return
    }

    self.gamePath = gamePath

    guard desiredEngineState == .running else {
      return
    }

    switch lifecyclePhase {
    case .resolvingPath:
      beginStartResolution()
    case .startRequested:
      stop()
      start()
    case .idle, .stopRequested:
      start()
    }
  }

  func stop() {
    desiredEngineState = .stopped
    cancelPendingStartResolution()

    if case .stopRequested = lifecyclePhase {
      return
    }

    lifecyclePhase = .stopRequested
    ScummVMEngineSharedInstance().stop()
  }

  private func beginStartResolution() {
    cancelPendingStartResolution()

    let startToken = nextStartToken
    nextStartToken &+= 1
    lifecyclePhase = .resolvingPath(startToken: startToken)

    let requestedGamePath = gamePath
    let pathResolver = self.pathResolver
    startTask = Task {
      let resolvedGameURL = await pathResolver.resolveGamePath(requestedGamePath)
      completeResolvedStartPath(startToken: startToken, resolvedGameURL: resolvedGameURL)
    }
  }

  private func completeResolvedStartPath(startToken: UInt64, resolvedGameURL: URL?) {
    guard !Task.isCancelled else {
      clearStartTaskIfNeeded(for: startToken)
      return
    }

    guard lifecyclePhase == .resolvingPath(startToken: startToken) else {
      clearStartTaskIfNeeded(for: startToken)
      return
    }

    guard desiredEngineState == .running else {
      startTask = nil
      lifecyclePhase = .idle
      return
    }

    startTask = nil
    lifecyclePhase = .startRequested(startToken: startToken)
    ScummVMEngineSharedInstance().start(gamePath: resolvedGameURL?.path)
  }

  private func clearStartTaskIfNeeded(for startToken: UInt64) {
    guard lifecyclePhase == .resolvingPath(startToken: startToken) else {
      return
    }

    startTask = nil
    if desiredEngineState == .stopped {
      lifecyclePhase = .stopRequested
    } else {
      lifecyclePhase = .idle
    }
  }

  private func cancelPendingStartResolution() {
    startTask?.cancel()
    startTask = nil

    if case .resolvingPath = lifecyclePhase {
      lifecyclePhase = .idle
    }
  }

  private func setGamePathWithoutLaunching(_ gamePath: URL?) {
    self.gamePath = gamePath
  }
}
