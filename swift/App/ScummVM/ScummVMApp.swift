//
//  ScummVMApp.swift
//  ScummVM
//
//  Created by Dominic Opitz on 23.08.26.
//

import SwiftUI

@main
struct ScummVMApp: App {
    @State private var gameURL: URL?
    @State private var presentsEngine = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                Color.black
                    .ignoresSafeArea()

                if presentsEngine {
                    ContentView(gameURL: gameURL)
                }
            }
            .onOpenURL(perform: openGame)
            #if os(iOS) || os(tvOS)
                .task {
                    UIApplication.shared.isIdleTimerDisabled = true
                }
            #endif
        }
    }

    private func openGame(_ url: URL) {
        guard url.isFileURL else { return }

        // Removing the host first gives the process-wide engine singleton a
        // deterministic stop-before-restart sequence for documents opened
        // while the launcher is already running.
        presentsEngine = false
        gameURL = url

        Task { @MainActor in
            await Task.yield()
            presentsEngine = true
        }
    }
}
