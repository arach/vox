import SwiftUI

@main
struct VoxApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        Window("Vox", id: "settings") {
            SettingsView()
                .environmentObject(delegate.monitor)
                .environmentObject(delegate.bridgeState)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 520, height: 480)
    }
}
