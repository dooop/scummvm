//
//  ScummVM.swift
//  ScummVM
//
//  Created by Dominic Opitz on 2/14/25.
//

import SwiftUI

public struct ScummVM: View {
  @StateObject private var viewModel: ScummVMViewModel

  public init(gamePath: String? = nil) {
    _viewModel = StateObject(wrappedValue: ScummVMViewModel(gamePath: gamePath))
  }

  public var body: some View {
    ScummVMView()
      .onAppear {
        viewModel.start()
      }
      .onDisappear {
        viewModel.stop()
      }
  }
}

#Preview {
  ScummVM()
}
