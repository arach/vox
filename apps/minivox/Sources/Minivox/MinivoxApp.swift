import AppKit
import MinivoxSupport
import SwiftUI

@main
struct MinivoxApp: App {
    @StateObject private var model: MinivoxModel
    private let commandReceiver: MinivoxCommandReceiver

    init() {
        let model = MinivoxModel()
        _model = StateObject(wrappedValue: model)
        commandReceiver = MinivoxCommandReceiver(model: model)

        NSApplication.shared.setActivationPolicy(.accessory)

        Task { @MainActor in
            model.loadIfNeeded()
        }
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
