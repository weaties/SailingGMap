//
//  ContentView.swift
//  Sailing
//

import SailingCore
import SwiftUI

struct ContentView: View {
    @StateObject private var vm = SailingGMapViewModel()

    var body: some View {
        HSplitView {
            ControlsView(vm: vm)
                .frame(minWidth: 260, idealWidth: 300, maxWidth: 360)

            VSplitView {
                SailingGMapCanvasView(vm: vm, mode: .courseFrame)
                    .frame(minHeight: 220)
                SailingGMapCanvasView(vm: vm, mode: .unfolded)
                    .frame(minHeight: 180)
            }
        }
        .padding(0)
    }
}

#Preview {
    ContentView()
}
