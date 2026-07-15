import AppKit
import Foundation
import MinivoxSupport
import SwiftUI

@MainActor
final class MinivoxCommandReceiver {
    private var appDidFinishLaunching = false
    private var pendingCommand: MinivoxCommand?
    private var launchObserver: NSObjectProtocol?
    private var commandObserver: NSObjectProtocol?
    private let model: MinivoxModel
    private var settingsWindow: NSWindow?

    init(model: MinivoxModel) {
        self.model = model
        launchObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didFinishLaunchingNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.appDidFinishLaunching = true
                self?.consumePersistedCommand()
                self?.dispatchPendingCommand()
            }
        }

        commandObserver = DistributedNotificationCenter.default().addObserver(
            forName: MinivoxCommandProtocol.notificationName,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let rawValue = notification.object as? String,
                  let command = MinivoxCommand(rawValue: rawValue)
            else { return }
            Task { @MainActor [weak self, command] in
                self?.pendingCommand = command
                self?.clearPersistedCommand()
                self?.dispatchPendingCommand()
            }
        }
    }

    private func consumePersistedCommand() {
        let defaults = UserDefaults.standard
        if let rawValue = defaults.string(forKey: MinivoxCommandProtocol.pendingCommandDefaultsKey),
           let command = MinivoxCommand(rawValue: rawValue) {
            pendingCommand = command
        }
        clearPersistedCommand()
    }

    private func clearPersistedCommand() {
        UserDefaults.standard.removeObject(forKey: MinivoxCommandProtocol.pendingCommandDefaultsKey)
    }

    private func dispatchPendingCommand() {
        guard appDidFinishLaunching, let command = pendingCommand else { return }
        pendingCommand = nil

        switch command {
        case .launch:
            break
        case .settings:
            showSettingsWindow()
        case .quit:
            NSApp.terminate(nil)
        }
    }

    private func showSettingsWindow() {
        NSApp.activate(ignoringOtherApps: true)

        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            return
        }

        let rootView = MinivoxSettingsView(model: model)
            .frame(width: 336)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 336, height: 330),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Minivox Settings"
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: rootView)
        window.center()
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
    }
}
