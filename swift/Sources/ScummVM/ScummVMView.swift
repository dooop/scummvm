//
//  ScummVMView.swift
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

#if os(macOS)
    import AppKit

    public struct ScummVMView: NSViewRepresentable {
        public init() {}

        public func makeNSView(context: Context) -> NSView {
            // SDL creates and manages its own window; provide an empty host view.
            return NSView()
        }

        public func updateNSView(_ nsView: NSView, context: Context) {
            // No updates needed
        }
    }
#else
    import UIKit

    public struct ScummVMView: UIViewControllerRepresentable {
        public init() {}

        public func makeUIViewController(context: Context) -> UIViewController {
            let controller = ScummVMEngineSharedInstance().ui()
            if let controller {
                return controller
            }

            // Avoid a SwiftUI trap if the ObjC bridge returns nil unexpectedly.
            return UIViewController()
        }

        public func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
            // No updates needed
        }
    }
#endif
