import SwiftUI

@main
struct VoxApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        Window("Vox", id: "settings") {
            VoxRootView()
                .environmentObject(delegate.monitor)
                .environmentObject(delegate.bridgeState)
                .frame(minWidth: 920, minHeight: 640)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 960, height: 680)
    }
}
