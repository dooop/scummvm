//
//  ContentView.swift
//  ScummVM
//
//  Created by Dominic Opitz on 23.08.26.
//

import ScummVM
import SwiftUI

struct ContentView: View {
    let gameURL: URL?

    var body: some View {
        ScummVM(game: gameURL)
            .ignoresSafeArea()
            .background(Color.black)
    }
}

#Preview {
    ContentView(gameURL: nil)
}
