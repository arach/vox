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
        case welcome
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
    let onboarding = OnboardingState()
    private var proxy: DaemonProxy?
    private var bridge: HTTPBridgeServer?
    private var allowlist: OriginAllowlist?
    private var settingsWindow: NSWindow?
    private var monitorObserver: AnyCancellable?
    private let processInfo = ProcessInfo.processInfo

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        startBridge()
        LaunchAgentManager.reconcileLegacyAgents()

        // Install or refresh the LaunchAgent when this bundle's helper path changes.
        LaunchAgentManager.ensureInstalled()

        monitor.start()

        // Show the app on first launch or when explicitly requested for demos/tests.
        if let launchPresentation = launchPresentationOnLaunch() {
            switch launchPresentation {
            case .settings:
                presentSettingsWindow(initialSection: .overview)
            case .gettingStarted, .welcome:
                onboarding.presentWelcome()
                presentSettingsWindow(initialSection: .welcome)
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
            button.image = MenuBarIcon.makeStatusImage(state: menuBarIconState())
            button.toolTip = "Vox"
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "Vox v\(VoxVersion.current)", action: nil, keyEquivalent: "")
        menu.addItem(.separator())

        let statusMenuItem = NSMenuItem(title: "Checking daemon...", action: nil, keyEquivalent: "")
        statusMenuItem.tag = 100
        menu.addItem(statusMenuItem)

        let stopRecordingItem = NSMenuItem(
            title: "Stop Recording",
            action: #selector(stopRecording),
            keyEquivalent: "."
        )
        stopRecordingItem.tag = 101
        stopRecordingItem.isHidden = true
        menu.addItem(stopRecordingItem)

        let stopSynthesisItem = NSMenuItem(
            title: "Stop Speaking",
            action: #selector(stopSynthesis),
            keyEquivalent: "."
        )
        stopSynthesisItem.keyEquivalentModifierMask = [.command, .shift]
        stopSynthesisItem.tag = 102
        stopSynthesisItem.isHidden = true
        menu.addItem(stopSynthesisItem)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Open Settings...", action: #selector(showSettings), keyEquivalent: ",")
        menu.addItem(withTitle: "Restart Daemon", action: #selector(restartDaemon), keyEquivalent: "")
        let diagnosticsItem = NSMenuItem(
            title: "Diagnostics…",
            action: #selector(toggleDiagnostics),
            keyEquivalent: "d"
        )
        diagnosticsItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(diagnosticsItem)
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

        let iconState = menuBarIconState()
        button.image = MenuBarIcon.makeStatusImage(state: iconState)
        button.contentTintColor = iconState == .idle && !monitor.isRunning ? .systemRed : nil

        if let liveSession = monitor.liveSession {
            let state = liveSession.state == .recording ? "recording" : liveSession.state.rawValue
            button.toolTip = "Vox is \(state) for \(liveSession.clientId)"
            statusMenuItem.title = "Daemon: \(state.capitalized) for \(liveSession.clientId) (port \(voxPortString(monitor.port ?? 0)))"
        } else if monitor.isSpeaking, let clientId = monitor.synthesisSession?.clientId {
            button.toolTip = "Vox is speaking for \(clientId)"
            statusMenuItem.title = "Daemon: Speaking for \(clientId) (port \(voxPortString(monitor.port ?? 0)))"
        } else if monitor.isRunning {
            button.toolTip = "Vox"
            statusMenuItem.title = "Daemon: Running (port \(voxPortString(monitor.port ?? 0)))"
        } else {
            button.toolTip = "Vox daemon is stopped"
            statusMenuItem.title = "Daemon: Stopped"
        }

        if let stopRecording = menu.item(withTag: 101) {
            stopRecording.isHidden = !monitor.hasLiveSession
            if let clientId = monitor.liveSession?.clientId {
                stopRecording.title = "Stop Live Session for \(clientId)"
            } else {
                stopRecording.title = "Stop Live Session"
            }
        }
        if let stopSynthesis = menu.item(withTag: 102) {
            stopSynthesis.isHidden = !monitor.isSpeaking
            if let clientId = monitor.synthesisSession?.clientId {
                stopSynthesis.title = "Stop Speaking for \(clientId)"
            } else {
                stopSynthesis.title = "Stop Speaking"
            }
        }
    }

    // MARK: - Actions

    @objc func showSettings() {
        presentSettingsWindow(initialSection: .overview)
    }

    private func presentSettingsWindow(initialSection: VoxSection) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let rootView = VoxRootView(initialSection: initialSection)
            .environmentObject(monitor)
            .environmentObject(bridgeState)
            .environmentObject(onboarding)
            .frame(minWidth: 1000, minHeight: 660)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1080, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Vox"
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = .black
        window.titlebarAppearsTransparent = false
        window.isOpaque = true
        window.contentViewController = NSHostingController(rootView: rootView)
        window.center()
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
    }

    func showGettingStarted(source: String?) {
        let context = GettingStartedContext.generic(sourceName: displayName(forSource: source))
        onboarding.present(context: context, returnTo: nil, isTrusted: false)
        presentSettingsWindow(initialSection: .welcome)
    }

    private func presentLaunch(request: LaunchRequest) {
        let fallbackSourceName = displayName(forSource: request.source)

        Task { @MainActor [weak self] in
            guard let self else { return }
            let isTrusted = await self.isTrustedLaunchRequest(returnTo: request.returnTo)
            let context = self.gettingStartedContext(
                sourceName: fallbackSourceName,
                payload: request.context
            )
            self.onboarding.present(
                context: context,
                returnTo: request.returnTo,
                isTrusted: isTrusted
            )
            self.presentSettingsWindow(initialSection: .welcome)
        }
    }

    @objc func restartDaemon() {
        let result = LaunchAgentManager.restart()
        DiagnosticLog.shared.log(result.summary, level: result.succeeded ? .success : .warning)
        monitor.checkNow()
    }

    private func menuBarIconState() -> MenuBarIcon.State {
        if monitor.hasLiveSession { return .recording }
        if monitor.isSpeaking  { return .speaking }
        return .idle
    }

    @objc func stopRecording() {
        Task { @MainActor [weak self] in
            await self?.monitor.cancelLiveSession()
        }
    }

    @objc func stopSynthesis() {
        Task { @MainActor [weak self] in
            await self?.monitor.cancelSynthesis()
        }
    }

    @objc func toggleDiagnostics() {
        DiagnosticWindow.shared.toggle()
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
        onboarding.attach(allowlist: a, bridgeState: bridgeState)
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
            bridgeState.statusDetail = "Ready on localhost."
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
        if processInfo.arguments.contains("--show-welcome") {
            return .welcome
        }

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
                presentLaunch(request: launchRequest(from: url))
            case "welcome":
                onboarding.presentWelcome()
                showSettings()
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
