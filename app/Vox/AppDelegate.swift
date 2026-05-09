import AppKit
import Combine
import SwiftUI
import VoxBridge
import VoxCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject, NSMenuDelegate {
    private enum LaunchPresentation {
        case settings
        case gettingStarted
    }

    private struct BridgeHealthResponse: Decodable, Sendable {
        let ok: Bool
        let port: UInt16?
        let service: String?
        let version: String?
    }

    private struct LaunchRequest {
        let source: String?
        let returnTo: String?
        let context: LaunchContextPayload?
    }

    private struct LaunchContextPayload: Decodable {
        let requesterName: String?
        let productName: String?
        let headline: String?
        let body: String?
        let actionLabel: String?
        let logo: LaunchLogoPayload?
        let logoURL: String?
        let logoUrl: String?
        let logoPath: String?
    }

    private struct LaunchLogoPayload: Decodable {
        let url: String?
        let path: String?
        let symbolName: String?
    }

    private var statusItem: NSStatusItem!
    let monitor = DaemonMonitor()
    let bridgeState = BridgeState()
    private var proxy: DaemonProxy?
    private var bridge: HTTPBridgeServer?
    private var allowlist: OriginAllowlist?
    private var settingsWindow: NSWindow?
    private var gettingStartedWindow: NSWindow?
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

        // Show the app on first launch or when explicitly requested for demos/tests.
        if let launchPresentation = launchPresentationOnLaunch() {
            switch launchPresentation {
            case .settings:
                showSettings()
            case .gettingStarted:
                showGettingStarted(source: nil)
            }

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
            button.image = MenuBarIcon.makeStatusImage(showsRecordingBadge: monitor.isRecording)
            button.image?.size = NSSize(width: 18, height: 18)
            button.toolTip = "Vox"
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

        button.image = MenuBarIcon.makeStatusImage(showsRecordingBadge: monitor.isRecording)
        button.image?.size = NSSize(width: 18, height: 18)
        button.contentTintColor = monitor.isRunning && monitor.isRecording ? nil : (monitor.isRunning ? nil : .systemRed)

        if monitor.isRecording, let clientId = monitor.liveSessionClientId {
            button.toolTip = "Vox is recording for \(clientId)"
            statusMenuItem.title = "Daemon: Recording for \(clientId) (port \(voxPortString(monitor.port ?? 0)))"
        } else if monitor.isRunning {
            button.toolTip = "Vox"
            statusMenuItem.title = "Daemon: Running (port \(voxPortString(monitor.port ?? 0)))"
        } else {
            button.toolTip = "Vox daemon is stopped"
            statusMenuItem.title = "Daemon: Stopped"
        }
    }

    // MARK: - Actions

    @objc func showSettings() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let rootView = VoxRootView()
            .environmentObject(monitor)
            .environmentObject(bridgeState)
            .frame(minWidth: 920, minHeight: 640)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Vox"
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: rootView)
        window.center()
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
    }

    func showGettingStarted(source: String?) {
        showGettingStarted(context: .generic(sourceName: displayName(forSource: source)))
    }

    private func showGettingStarted(request: LaunchRequest) {
        let fallbackSourceName = displayName(forSource: request.source)

        Task { @MainActor [weak self] in
            guard let self else { return }
            let isTrusted = await self.isTrustedLaunchRequest(returnTo: request.returnTo)
            let context = self.gettingStartedContext(
                sourceName: fallbackSourceName,
                payload: isTrusted ? request.context : nil
            )
            self.showGettingStarted(context: context)
        }
    }

    private func showGettingStarted(context: GettingStartedContext) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        let rootView = GettingStartedView(
            context: context,
            onOpenSettings: { [weak self] in
                self?.showSettings()
            },
            onRestartDaemon: { [weak self] in
                LaunchAgentManager.restart()
                self?.monitor.checkNow()
            }
        )
        .environmentObject(monitor)
        .environmentObject(bridgeState)

        if let window = gettingStartedWindow {
            window.title = gettingStartedTitle(context: context)
            window.contentViewController = NSHostingController(rootView: rootView)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 430),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = gettingStartedTitle(context: context)
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: rootView)
        window.center()
        gettingStartedWindow = window
        window.makeKeyAndOrderFront(nil)
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

    private func launchPresentationOnLaunch() -> LaunchPresentation? {
        if processInfo.arguments.contains("--show-settings") {
            return .settings
        }

        if let rawValue = processInfo.environment["VOX_SHOW_SETTINGS_ON_LAUNCH"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        {
            if ["1", "true", "yes", "on"].contains(rawValue) {
                return .settings
            }
        }

        return !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") ? .gettingStarted : nil
    }

    private func displayName(forSource source: String?) -> String? {
        switch source?.lowercased() {
        case "openscout":
            return "OpenScout"
        case let source? where !source.isEmpty:
            return source
        default:
            return nil
        }
    }

    private func gettingStartedTitle(context: GettingStartedContext) -> String {
        if let productName = context.productName {
            return "\(productName) powered by Vox"
        }
        return context.sourceName.map { "Vox for \($0)" } ?? "Vox Getting Started"
    }

    private func launchRequest(from url: URL) -> LaunchRequest {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []
        let source = queryItems.first(where: { $0.name == "source" })?.value
        let returnTo = queryItems.first(where: { $0.name == "returnTo" })?.value
        let rawContext = queryItems.first(where: { $0.name == "context" })?.value
        let context = rawContext.flatMap { Self.decodeLaunchContext($0) }
        return LaunchRequest(source: source, returnTo: returnTo, context: context)
    }

    private nonisolated static func decodeLaunchContext(_ rawContext: String) -> LaunchContextPayload? {
        let decodedContext = rawContext.replacingOccurrences(of: "+", with: " ")
        guard let data = decodedContext.data(using: .utf8), data.count <= 4096 else {
            return nil
        }
        return try? JSONDecoder().decode(LaunchContextPayload.self, from: data)
    }

    private func isTrustedLaunchRequest(returnTo: String?) async -> Bool {
        guard let returnTo, !returnTo.isEmpty, let allowlist else {
            return false
        }
        return await allowlist.check(returnTo)
    }

    private func gettingStartedContext(
        sourceName: String?,
        payload: LaunchContextPayload?
    ) -> GettingStartedContext {
        guard let payload else {
            return .generic(sourceName: sourceName)
        }

        let requesterName = cleanLaunchText(payload.requesterName, maxLength: 40) ?? sourceName
        let productName = cleanLaunchText(payload.productName, maxLength: 48) ?? requesterName
        return GettingStartedContext(
            sourceName: requesterName,
            productName: productName,
            headline: cleanLaunchText(payload.headline, maxLength: 72) ?? "Local speech for \(productName ?? "your app")",
            detail: cleanLaunchText(payload.body, maxLength: 180)
                ?? "Vox runs local speech capture and speech synthesis for this integration.",
            actionLabel: cleanLaunchText(payload.actionLabel, maxLength: 36) ?? requesterName.map { "Return to \($0)" } ?? "Return to your app",
            logo: launchLogo(from: payload)
        )
    }

    private func launchLogo(from payload: LaunchContextPayload) -> GettingStartedLogo? {
        let rawPath = cleanLaunchText(payload.logo?.path ?? payload.logoPath, maxLength: 512)
        let rawURL = cleanLaunchText(payload.logo?.url ?? payload.logoURL ?? payload.logoUrl, maxLength: 512)
        let symbolName = cleanLaunchText(payload.logo?.symbolName, maxLength: 64)

        if let rawPath {
            return GettingStartedLogo(url: URL(fileURLWithPath: rawPath), symbolName: symbolName)
        }

        if let rawURL,
           let url = URL(string: rawURL),
           let scheme = url.scheme?.lowercased(),
           ["file", "http", "https"].contains(scheme)
        {
            return GettingStartedLogo(url: url, symbolName: symbolName)
        }

        if let symbolName {
            return GettingStartedLogo(url: nil, symbolName: symbolName)
        }

        return nil
    }

    private func cleanLaunchText(_ value: String?, maxLength: Int) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maxLength))
    }

    // MARK: - URL Scheme

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard url.scheme == "vox" else { continue }
            switch url.host {
            case "launch":
                showGettingStarted(request: launchRequest(from: url))
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
