//
//  ScummVM.swift
//  ScummVM
//
//  Created by Dominic Opitz on 2/14/25.
//

import Foundation
import SwiftUI

public struct ScummVM: View {
  private let game: URL?
  @StateObject private var viewModel: ScummVMViewModel
  @State private var isVisible = false
  @Environment(\.scenePhase) private var scenePhase

  public init(game: URL? = nil) {
    self.game = game
    #if os(iOS)
      _viewModel = StateObject(wrappedValue: ScummVMViewModel.sharedIOSHost)
    #else
      _viewModel = StateObject(wrappedValue: ScummVMViewModel(game: game))
    #endif
  }

  public var body: some View {
    ScummVMView()
      .onAppear {
        isVisible = true
        #if os(iOS)
          viewModel.hostAttach(game: game, scenePhase: scenePhase)
        #else
          viewModel.start()
        #endif
      }
      .onDisappear {
        isVisible = false
        #if os(iOS)
          viewModel.hostDetach(scenePhase: scenePhase)
        #else
          viewModel.stop()
        #endif
      }
      .onChange(of: scenePhase) { newScenePhase in
        guard isVisible else {
          return
        }

        #if os(iOS)
          viewModel.hostScenePhaseChanged(newScenePhase)
        #else
          switch newScenePhase {
          case .active:
            viewModel.start()
          case .background, .inactive:
            viewModel.stop()
          @unknown default:
            break
          }
        #endif
      }
  }
}

#Preview {
  ScummVM()
}
