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
  private var game: URL?
  private let pathResolver = ScummVMGamePathResolver()
  private var startTask: Task<Void, Never>?
  private var shouldRunEngine = false
  private var isEngineRunning = false
  private var startRequestToken: UInt64 = 0
  #if os(iOS) || os(tvOS)
    private var attachedHostViewCount = 0
    private var lastObservedScenePhase: ScenePhase = .active
  #endif

  // iOS and tvOS share the same process-wide engine singleton (tvOS compiles the
  // same ios7 backend as a platform slice of ScummVMiOS), so both need a shared
  // view model to track host-view attach count across recreated `ScummVM()` views.
  // macOS instead runs one `ScummVM()` view for the app's whole lifetime.
  #if os(iOS) || os(tvOS)
    static let sharedHost = ScummVMViewModel(game: nil)
  #endif

  init(game: URL?) {
    self.game = game
    _ = ScummVMEngineSharedInstance()
  }

  deinit {
    startTask?.cancel()
    if isEngineRunning {
      ScummVMEngineSharedInstance().stop()
    }
  }

  func start() {
    if shouldRunEngine {
      if !isEngineRunning && startTask == nil {
        beginStartResolution()
      }
      return
    }

    shouldRunEngine = true
    beginStartResolution()
  }

  #if os(iOS) || os(tvOS)
    func hostAttach(game: URL?, scenePhase: ScenePhase) {
      attachedHostViewCount += 1
      lastObservedScenePhase = scenePhase
      setGameWithoutLaunching(game)
      applyHostLifecyclePolicy()
    }

    func hostDetach(scenePhase: ScenePhase) {
      lastObservedScenePhase = scenePhase
      attachedHostViewCount = max(0, attachedHostViewCount - 1)
      applyHostLifecyclePolicy()
    }

    func hostScenePhaseChanged(_ scenePhase: ScenePhase) {
      lastObservedScenePhase = scenePhase
      applyHostLifecyclePolicy()
    }
  #endif

  func stop() {
    shouldRunEngine = false
    cancelPendingStartResolution()

    guard isEngineRunning else {
      return
    }

    ScummVMEngineSharedInstance().stop()
    isEngineRunning = false
  }

  private func beginStartResolution() {
    cancelPendingStartResolution()

    startRequestToken &+= 1
    let startToken = startRequestToken

    let requestedGame = game
    let pathResolver = self.pathResolver
    startTask = Task {
      let resolvedGameURL = await pathResolver.resolveGamePath(requestedGame)
      completeResolvedStartPath(startToken: startToken, resolvedGameURL: resolvedGameURL)
    }
  }

  private func completeResolvedStartPath(startToken: UInt64, resolvedGameURL: URL?) {
    guard !Task.isCancelled else {
      return
    }

    guard startToken == startRequestToken else {
      return
    }

    startTask = nil

    guard shouldRunEngine else {
      return
    }

    if isEngineRunning {
      ScummVMEngineSharedInstance().stop()
      isEngineRunning = false
    }

    ScummVMEngineSharedInstance().start(gamePath: resolvedGameURL?.path)
    isEngineRunning = true
  }

  private func cancelPendingStartResolution() {
    startTask?.cancel()
    startTask = nil
  }

  #if os(iOS) || os(tvOS)
    private func applyHostLifecyclePolicy() {
      guard attachedHostViewCount > 0 else {
        stop()
        return
      }

      switch lastObservedScenePhase {
      case .active:
        start()
      case .inactive:
        break
      case .background:
        stop()
      @unknown default:
        break
      }
    }
  #endif

  private func setGameWithoutLaunching(_ game: URL?) {
    self.game = game
  }
}
