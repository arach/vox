import SwiftUI

@main
struct VoxApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        // Empty Settings scene satisfies App's "at least one Scene" requirement
        // without auto-creating a window. AppDelegate owns window creation so
        // deep links and menu actions land in a single deduped NSWindow.
        Settings {
            EmptyView()
        }
    }
}
