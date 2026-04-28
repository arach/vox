import AppKit
import Combine
import SwiftUI
import VoxBridge
import VoxCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject, NSMenuDelegate {
    private struct BridgeHealthResponse: Decodable, Sendable {
        let ok: Bool
        let port: UInt16?
        let service: String?
        let version: String?
    }

    private var statusItem: NSStatusItem!
    let monitor = DaemonMonitor()
    let bridgeState = BridgeState()
    private var proxy: DaemonProxy?
    private var bridge: HTTPBridgeServer?
    private var allowlist: OriginAllowlist?
    private var monitorObserver: AnyCancellable?
    private let processInfo = ProcessInfo.processInfo

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        startBridge()

        // First launch: install LaunchAgent
        if !LaunchAgentManager.isInstalled() {
            LaunchAgentManager.install()
        }

        monitor.start()

        // Show settings on first launch or when explicitly requested for demos/tests.
        if shouldShowSettingsOnLaunch() {
            showSettings()
            if !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
                UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        NSApp.setActivationPolicy(.accessory)
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
        bridge?.stop()
        Task {
            await proxy?.disconnect()
        }
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

        menu.delegate = self
        statusItem.menu = menu
        monitorObserver = monitor.objectWillChange.sink { [weak self] _ in
            Task { @MainActor [weak self] in
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
    }

    func menuWillOpen(_ menu: NSMenu) {
        updateMenuBarState()
    }

    // MARK: - HTTP Bridge

    private func startBridge() {
        let p = DaemonProxy()
        let a = OriginAllowlist()
        let port = HTTPBridgeServer.defaultPort

        proxy = p
        allowlist = a
        bridge = nil
        bridgeState.bind(allowlist: a)
        bridgeState.port = port
        bridgeState.isRunning = false
        bridgeState.statusDetail = "Starting bridge..."

        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.runBridgeStartup(proxy: p, allowlist: a, port: port)
        }
    }

    private func runBridgeStartup(proxy: DaemonProxy, allowlist: OriginAllowlist, port: UInt16) async {
        if let existingBridge = await Self.fetchBridgeHealth(port: port) {
            VoxLog.service.info("Using existing HTTP bridge on http://127.0.0.1:\(existingBridge.port ?? port)")
            bridgeState.isRunning = true
            bridgeState.port = existingBridge.port ?? port
            if let version = existingBridge.version, version != VoxVersion.current {
                bridgeState.statusDetail =
                    "Using existing bridge from another Vox instance (v\(version))."
            } else {
                bridgeState.statusDetail = "Using existing bridge."
            }
            try? await proxy.connect()
            return
        }

        let bridge = HTTPBridgeServer(port: port, proxy: proxy, allowlist: allowlist)
        self.bridge = bridge
        bridge.start()

        if let startedBridge = await Self.waitForBridgeHealth(port: port) {
            bridgeState.isRunning = true
            bridgeState.port = startedBridge.port ?? port
            bridgeState.statusDetail = "Listening on localhost."
        } else {
            bridgeState.isRunning = false
            bridgeState.port = port
            bridgeState.statusDetail = "Bridge port \(port) is busy or unavailable."
        }

        try? await proxy.connect()
    }

    private nonisolated static func fetchBridgeHealth(port: UInt16) async -> BridgeHealthResponse? {
        guard let url = URL(string: "http://127.0.0.1:\(port)/health") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 0.25

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }

            let health = try JSONDecoder().decode(BridgeHealthResponse.self, from: data)
            guard health.service == "vox-companion" else {
                return nil
            }
            return health
        } catch {
            return nil
        }
    }

    private nonisolated static func waitForBridgeHealth(
        port: UInt16,
        attempts: Int = 10,
        intervalNanoseconds: UInt64 = 100_000_000
    ) async -> BridgeHealthResponse? {
        for attempt in 0..<attempts {
            if let health = await fetchBridgeHealth(port: port) {
                return health
            }
            if attempt + 1 < attempts {
                try? await Task.sleep(nanoseconds: intervalNanoseconds)
            }
        }

        return nil
    }

    private func shouldShowSettingsOnLaunch() -> Bool {
        if processInfo.arguments.contains("--show-settings") {
            return true
        }

        if let rawValue = processInfo.environment["VOX_SHOW_SETTINGS_ON_LAUNCH"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        {
            if ["1", "true", "yes", "on"].contains(rawValue) {
                return true
            }
        }

        return !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
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
