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
  public init() {
    _ = ScummVMEngineSharedInstance()
  }

  public var body: some View {
    ScummVMView()
      .onAppear {
        ScummVMEngineSharedInstance().start()
      }
      .onDisappear {
        ScummVMEngineSharedInstance().stop()
      }
  }
}

#Preview {
  ScummVM()
}
