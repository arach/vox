import AppKit
import SwiftUI

@main
struct MinivoxApp: App {
    @StateObject private var model = MinivoxModel()

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            ContentView(model: model)
        } label: {
            Label(
                "Minivox",
                systemImage: menuBarSymbol
            )
        }
        .menuBarExtraStyle(.window)
    }

    private var menuBarSymbol: String {
        if model.isRecording { return "waveform.circle.fill" }
        if model.isWorking || model.isWarmingASR { return "ellipsis.circle" }
        if model.asrReadyInMemory { return "checkmark.circle" }
        return "waveform.circle"
    }
}
