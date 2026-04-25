import AppKit
import SwiftUI

@main
struct VoxMinimalExampleApp: App {
    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        DispatchQueue.main.async {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    var body: some Scene {
        Window("Vox Voice Loop", id: "main") {
            ContentView()
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1120, height: 860)
    }
}
