//
//  ScummVM.swift
//  ScummVM
//
//  Created by Dominic Opitz on 2/14/25.
//

import SwiftUI

#if os(tvOS)
  import ScummVMtvOS
#elseif os(iOS)
  import ScummVMiOS
#elseif os(macOS)
  import ScummVMmacOS
#endif

public struct ScummVM: View {
  private let gamePath: String?

  public init(gamePath: String? = nil) {
    self.gamePath = gamePath
    _ = ScummVMEngineSharedInstance()
  }

  public var body: some View {
    ScummVMView()
      .onAppear {
        ScummVMEngineSharedInstance().start(gamePath: gamePath)
      }
      .onDisappear {
        ScummVMEngineSharedInstance().stop()
      }
  }
}

#Preview {
  ScummVM()
}
