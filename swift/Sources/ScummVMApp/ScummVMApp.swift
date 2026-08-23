//
//  ScummVM.swift
//  ScummVM
//
//  Created by Dominic Opitz on 2/14/26.
//

#if os(macOS)
    import SwiftUI
    import ScummVM

    @main
    struct ScummVMApp: App {
        var body: some Scene {
            WindowGroup {
                ScummVM()
                    .frame(minWidth: 800, minHeight: 600)
            }
        }
    }
#else
    import Foundation

    @main
    enum ScummVMApp {
        static func main() {
            fputs("ScummVMTestApp is only supported on macOS.\n", stderr)
        }
    }
#endif
