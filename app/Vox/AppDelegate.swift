import AppKit
import SwiftUI
import VoxBridge
import VoxCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    private var statusItem: NSStatusItem!
    let monitor = DaemonMonitor()
    let bridgeState = BridgeState()
    private var proxy: DaemonProxy?
    private var bridge: HTTPBridgeServer?
    private var allowlist: OriginAllowlist?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        startBridge()

        // First launch: install LaunchAgent
        if !LaunchAgentManager.isInstalled() {
            LaunchAgentManager.install()
        }

        monitor.start()

        // Show settings on first launch
        if !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
            showSettings()
            UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        NSApp.setActivationPolicy(.accessory)
        return false
    }

    // MARK: - Menu bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "waveform.circle.fill", accessibilityDescription: "Vox")
            button.image?.size = NSSize(width: 18, height: 18)
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "Vox v\(VoxVersion.current)", action: nil, keyEquivalent: "")
        menu.addItem(.separator())

        let statusMenuItem = NSMenuItem(title: "Checking daemon...", action: nil, keyEquivalent: "")
        statusMenuItem.tag = 100
        menu.addItem(statusMenuItem)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Open Settings...", action: #selector(showSettings), keyEquivalent: ",")
        menu.addItem(withTitle: "Restart Daemon", action: #selector(restartDaemon), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Vox", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        statusItem.menu = menu

        Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateMenuBarState()
            }
        }
        updateMenuBarState()
    }

    private func updateMenuBarState() {
        guard let button = statusItem.button,
              let menu = statusItem.menu,
              let statusMenuItem = menu.item(withTag: 100)
        else { return }

        if monitor.isRunning {
            button.contentTintColor = .systemGreen
            statusMenuItem.title = "Daemon: Running (port \(monitor.port ?? 0))"
        } else {
            button.contentTintColor = .systemRed
            statusMenuItem.title = "Daemon: Stopped"
        }
    }

    // MARK: - Actions

    @objc func showSettings() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.title == "Vox" }) {
            window.makeKeyAndOrderFront(nil)
        }
    }

    @objc func restartDaemon() {
        LaunchAgentManager.restart()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            monitor.checkNow()
        }
    }

    // MARK: - HTTP Bridge

    private nonisolated func startBridge() {
        let p = DaemonProxy()
        let a = OriginAllowlist()
        let b = HTTPBridgeServer(proxy: p, allowlist: a)

        Task { @MainActor in
            proxy = p
            allowlist = a
            bridge = b

            try? await p.connect()
            bridgeState.isRunning = true
            bridgeState.port = HTTPBridgeServer.defaultPort
        }

        b.start()
    }

    // MARK: - URL Scheme

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard url.scheme == "vox" else { continue }
            switch url.host {
            case "settings":
                showSettings()
            case "restart":
                restartDaemon()
            default:
                showSettings()
            }
        }
    }
}
