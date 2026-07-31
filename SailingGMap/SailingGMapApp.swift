//
//  SailingGMapApp.swift
//  SailingGMap
//
//  macOS SwiftUI entry point.
//

import SwiftUI

@main
struct SailingGMapApp: App {
    var body: some Scene {
        WindowGroup("SailingGMap — Tacking Unfolding") {
            ContentView()
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
    }
}
