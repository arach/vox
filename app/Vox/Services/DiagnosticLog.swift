import AppKit
import SwiftUI
import VoxCore

// Ported from Lattices's app/Sources/Core/System/DiagnosticLog.swift —
// in-memory ring + disk-rotated text log + a small floating overlay window.
// Adapted for Vox: log lives under ~/.vox/diagnostics.log; Vox-specific
// startup info; no tap-sound feedback wrapper.

// MARK: - Log Store

final class DiagnosticLog: ObservableObject, @unchecked Sendable {
    static let shared = DiagnosticLog()

    struct Entry: Identifiable {
        let id = UUID()
        let time: Date
        let message: String
        let level: Level

        enum Level: String { case info, success, warning, error }

        var icon: String {
            switch level {
            case .info:    return "›"
            case .success: return "✓"
            case .warning: return "⚠"
            case .error:   return "✗"
            }
        }
    }

    @Published var entries: [Entry] = []
    private let maxEntries = 80

    // Disk persistence
    private let logFile: URL
    private let fileHandle: FileHandle?
    private let diskQueue = DispatchQueue(label: "com.vox.log-writer")
    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    private init() {
        let voxHome: URL
        if let override = ProcessInfo.processInfo.environment["VOX_HOME"], !override.isEmpty {
            voxHome = URL(fileURLWithPath: override)
        } else {
            voxHome = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".vox")
        }
        try? FileManager.default.createDirectory(at: voxHome, withIntermediateDirectories: true)

        logFile = voxHome.appendingPathComponent("diagnostics.log")

        // Rotate if > 1MB
        if let attrs = try? FileManager.default.attributesOfItem(atPath: logFile.path),
           let size = attrs[.size] as? UInt64, size > 1_000_000 {
            let prev = voxHome.appendingPathComponent("diagnostics.log.1")
            try? FileManager.default.removeItem(at: prev)
            try? FileManager.default.moveItem(at: logFile, to: prev)
        }

        if !FileManager.default.fileExists(atPath: logFile.path) {
            FileManager.default.createFile(atPath: logFile.path, contents: nil)
        }
        fileHandle = try? FileHandle(forWritingTo: logFile)
        fileHandle?.seekToEndOfFile()

        let header = "\n──── Vox launched \(ISO8601DateFormatter().string(from: Date())) ────\n"
        if let data = header.data(using: .utf8) {
            fileHandle?.write(data)
        }
    }

    deinit {
        fileHandle?.closeFile()
    }

    func log(_ message: String, level: Entry.Level = .info) {
        let entry = Entry(time: Date(), message: message, level: level)

        // In-memory for UI
        DispatchQueue.main.async {
            self.entries.append(entry)
            if self.entries.count > self.maxEntries {
                self.entries.removeFirst(self.entries.count - self.maxEntries)
            }
        }

        // Disk
        diskQueue.async { [weak self] in
            let ts = Self.timeFmt.string(from: entry.time)
            let line = "\(ts) \(entry.icon) [\(level.rawValue)] \(message)\n"
            if let data = line.data(using: .utf8) {
                self?.fileHandle?.write(data)
            }
        }
    }

    func info(_ msg: String)    { log(msg, level: .info) }
    func success(_ msg: String) { log(msg, level: .success) }
    func warn(_ msg: String)    { log(msg, level: .warning) }
    func error(_ msg: String)   { log(msg, level: .error) }
    func clear()                { DispatchQueue.main.async { self.entries.removeAll() } }

    // MARK: - Per-Action Timing

    struct TimedAction {
        let label: String
        let start: Date
    }

    func startTimed(_ label: String) -> TimedAction {
        info("▸ \(label)")
        return TimedAction(label: label, start: Date())
    }

    func finish(_ action: TimedAction) {
        let ms = Date().timeIntervalSince(action.start) * 1000
        success("▸ \(action.label) — \(String(format: "%.0f", ms))ms")
    }
}

// MARK: - Runtime Log Sources

struct DiagnosticFileEntry: Identifiable {
    let id = UUID()
    let time: String
    let message: String
    let level: DiagnosticLog.Entry.Level
}

@MainActor
final class DiagnosticRuntimeSources: ObservableObject {
    @Published var daemonEntries: [DiagnosticFileEntry] = []
    @Published var traceEntries: [DiagnosticFileEntry] = []

    private var isRefreshing = false

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true

        let daemonURL = RuntimePaths.daemonLogURL()
        let performanceURL = RuntimePaths.performanceLogURL()

        Task.detached(priority: .utility) {
            let daemon = Self.readDaemonEntries(from: daemonURL, limit: 140)
            let traces = Self.readTraceEntries(from: performanceURL, limit: 120)
            await MainActor.run {
                self.daemonEntries = daemon
                self.traceEntries = traces
                self.isRefreshing = false
            }
        }
    }

    nonisolated private static func readDaemonEntries(from url: URL, limit: Int) -> [DiagnosticFileEntry] {
        readTailLines(from: url, limit: limit).map { line in
            DiagnosticFileEntry(
                time: extractBracketedTime(from: line),
                message: line,
                level: level(for: line)
            )
        }
    }

    nonisolated private static func readTraceEntries(from url: URL, limit: Int) -> [DiagnosticFileEntry] {
        readTailLines(from: url, limit: limit).compactMap { line in
            guard
                let data = line.data(using: .utf8),
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                return nil
            }

            let timestamp = (object["timestamp"] as? String) ?? "-"
            let route = (object["route"] as? String) ?? "route?"
            let outcome = (object["outcome"] as? String) ?? "outcome?"
            let clientId = (object["clientId"] as? String) ?? "client?"
            let modelId = (object["modelId"] as? String) ?? "model?"
            let voiceId = object["voiceId"] as? String
            let textLength = object["textLength"] as? Int
            let error = object["error"] as? String
            let metrics = object["metrics"] as? [String: Any]
            let traceId = (metrics?["traceId"] as? String) ?? "trace?"
            let totalMs = number(metrics?["totalMs"])
            let synthesisMs = number(metrics?["synthesisMs"] ?? metrics?["inferenceMs"])
            let outputBytes = number(metrics?["outputBytes"])
            let realtimeFactor = number(metrics?["realtimeFactor"])

            var parts = [
                "\(outcome.uppercased())",
                route,
                "trace=\(traceId)",
                "client=\(clientId)",
                "model=\(modelId)"
            ]
            if let voiceId, !voiceId.isEmpty {
                parts.append("voice=\(voiceId)")
            }
            if let textLength {
                parts.append("chars=\(textLength)")
            }
            if let totalMs {
                parts.append("total=\(formatMs(totalMs))")
            }
            if let synthesisMs {
                parts.append("synth=\(formatMs(synthesisMs))")
            }
            if let realtimeFactor {
                parts.append("rtf=\(String(format: "%.2f", realtimeFactor))x")
            }
            if let outputBytes {
                parts.append("bytes=\(Int(outputBytes))")
            }
            if let error, !error.isEmpty {
                parts.append("error=\(error)")
            }

            return DiagnosticFileEntry(
                time: timestamp,
                message: parts.joined(separator: "  "),
                level: outcome == "ok" ? .success : .error
            )
        }
    }

    nonisolated private static func readTailLines(from url: URL, limit: Int, maxBytes: UInt64 = 512_000) -> [String] {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return []
        }
        defer {
            try? handle.close()
        }

        let fileSize = (try? handle.seekToEnd()) ?? 0
        let start = fileSize > maxBytes ? fileSize - maxBytes : 0
        try? handle.seek(toOffset: start)

        guard let data = try? handle.readToEnd(), !data.isEmpty else {
            return []
        }

        return String(decoding: data, as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: true)
            .suffix(limit)
            .map(String.init)
    }

    nonisolated private static func extractBracketedTime(from line: String) -> String {
        guard
            line.first == "[",
            let end = line.firstIndex(of: "]")
        else {
            return "-"
        }
        return String(line[line.index(after: line.startIndex)..<end])
    }

    nonisolated private static func level(for line: String) -> DiagnosticLog.Entry.Level {
        if line.contains(" ERROR:") || line.contains(" FAULT:") {
            return .error
        }
        if line.contains(" WARN:") {
            return .warning
        }
        if line.contains(" complete ") || line.contains(" completed ") || line.contains(" ready ") {
            return .success
        }
        return .info
    }

    nonisolated private static func number(_ value: Any?) -> Double? {
        if let value = value as? Double {
            return value
        }
        if let value = value as? Int {
            return Double(value)
        }
        if let value = value as? NSNumber {
            return value.doubleValue
        }
        return nil
    }

    nonisolated private static func formatMs(_ value: Double) -> String {
        if value >= 1000 {
            return "\(String(format: "%.2f", value / 1000))s"
        }
        return "\(Int(value.rounded()))ms"
    }
}

// MARK: - Diagnostic Window

@MainActor
final class DiagnosticWindow {
    static let shared = DiagnosticWindow()

    private var window: NSWindow?
    private var keyMonitor: Any?
    private let log = DiagnosticLog.shared

    var isVisible: Bool { window?.isVisible ?? false }

    func toggle() {
        if let w = window, w.isVisible {
            dismiss()
        } else {
            show()
        }
    }

    func dismiss() {
        window?.orderOut(nil)
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    func show() {
        if let w = window {
            w.orderFrontRegardless()
            return
        }

        let view = DiagnosticOverlayView()

        let hosting = NSHostingController(rootView: view)
        let screen = NSScreen.main
        let screenFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let panelWidth: CGFloat = 480
        let panelHeight: CGFloat = max(600, floor(screenFrame.height * 0.55))
        hosting.preferredContentSize = NSSize(width: panelWidth, height: panelHeight)

        let w = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        w.contentViewController = hosting
        w.title = "Vox Diagnostics"
        w.titlebarAppearsTransparent = true
        w.isMovableByWindowBackground = false
        w.level = .floating
        w.isOpaque = false
        w.backgroundColor = NSColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 1.0)
        w.hasShadow = true
        w.alphaValue = 1.0
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Right edge, vertically centered
        let x = screenFrame.maxX - panelWidth - 12
        let y = screenFrame.minY + floor((screenFrame.height - panelHeight) / 2)
        w.setFrameOrigin(NSPoint(x: x, y: y))

        w.orderFrontRegardless()
        window = w

        // Escape key → dismiss
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53,
                  let win = self?.window,
                  event.window === win || win.isKeyWindow else { return event }
            self?.dismiss()
            return nil
        }

        // Startup info
        let diag = DiagnosticLog.shared
        diag.info("Diagnostics opened")
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        diag.info("Vox \(version) (\(build))")
        let macos = ProcessInfo.processInfo.operatingSystemVersionString
        diag.info("macOS \(macos)")
        if let voxHome = ProcessInfo.processInfo.environment["VOX_HOME"], !voxHome.isEmpty {
            diag.info("VOX_HOME: \(voxHome)")
        }
    }
}

// MARK: - SwiftUI Overlay

struct DiagnosticOverlayView: View {
    private enum Tab: String, CaseIterable, Identifiable {
        case app = "App"
        case daemon = "Daemon"
        case traces = "Traces"

        var id: String { rawValue }
    }

    @StateObject private var log = DiagnosticLog.shared
    @StateObject private var runtimeSources = DiagnosticRuntimeSources()
    @State private var selectedTab: Tab = .daemon
    @State private var autoScroll = true
    @State private var refreshTick = 0

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    // Fallback timer to catch any missed updates
    private let refreshTimer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            headerView
            entriesView
        }
        .frame(minWidth: 420, idealWidth: 480, minHeight: 400, idealHeight: 600)
        .background(Color.black.opacity(0.75))
        .onAppear {
            runtimeSources.refresh()
        }
    }

    private var headerView: some View {
        HStack {
            Text("DIAGNOSTICS")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.green.opacity(0.8))
            tabStrip
            Spacer()
            let _ = refreshTick
            Text(countLabel)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.white.opacity(0.4))
            Button("Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(copyText, forType: .string)
            }
            .font(.system(size: 9, design: .monospaced))
            .foregroundColor(.white.opacity(0.5))
            .buttonStyle(.plain)
            Button(selectedTab == .app ? "Clear" : "Refresh") {
                if selectedTab == .app {
                    log.clear()
                } else {
                    runtimeSources.refresh()
                }
            }
            .font(.system(size: 9, design: .monospaced))
            .foregroundColor(.white.opacity(0.5))
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.3))
        .onReceive(refreshTimer) { _ in
            refreshTick += 1
            runtimeSources.refresh()
        }
    }

    private var tabStrip: some View {
        HStack(spacing: 2) {
            ForEach(Tab.allCases) { tab in
                tabButton(tab)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.black.opacity(0.42))
        )
    }

    private func tabButton(_ tab: Tab) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            selectedTab = tab
        } label: {
            Text(tab.rawValue)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(isSelected ? .black.opacity(0.9) : .white.opacity(0.72))
                .frame(minWidth: 54)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isSelected ? Color.green.opacity(0.86) : Color.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isSelected ? Color.green.opacity(0.95) : Color.white.opacity(0.16), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var entriesView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    if selectedTab == .app {
                        ForEach(log.entries) { entry in
                            appLogRow(entry)
                                .id(entry.id)
                        }
                    } else {
                        ForEach(fileEntries) { entry in
                            fileLogRow(entry)
                                .id(entry.id)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .textSelection(.enabled)
            }
            .onChange(of: scrollCount) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: selectedTab) { _, _ in
                scrollToBottom(proxy)
            }
        }
    }

    private var fileEntries: [DiagnosticFileEntry] {
        selectedTab == .traces ? runtimeSources.traceEntries : runtimeSources.daemonEntries
    }

    private var scrollCount: Int {
        selectedTab == .app ? log.entries.count : fileEntries.count
    }

    private var countLabel: String {
        switch selectedTab {
        case .app:
            return "\(log.entries.count) events"
        case .daemon:
            return "\(runtimeSources.daemonEntries.count) lines"
        case .traces:
            return "\(runtimeSources.traceEntries.count) traces"
        }
    }

    private var copyText: String {
        switch selectedTab {
        case .app:
            return log.entries.map { entry in
                let t = Self.timeFmt.string(from: entry.time)
                return "\(t) \(entry.icon) \(entry.message)"
            }.joined(separator: "\n")
        case .daemon, .traces:
            return fileEntries.map { entry in
                "\(entry.time) \(entry.message)"
            }.joined(separator: "\n")
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard autoScroll else { return }
        if selectedTab == .app, let last = log.entries.last {
            withAnimation(.easeOut(duration: 0.1)) {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        } else if let last = fileEntries.last {
            withAnimation(.easeOut(duration: 0.1)) {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    private func appLogRow(_ entry: DiagnosticLog.Entry) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(Self.timeFmt.string(from: entry.time))
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.white.opacity(0.3))

            Text(entry.icon)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(iconColor(entry.level))
                .frame(width: 10)

            Text(entry.message)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(textColor(entry.level))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 1)
        .textSelection(.enabled)
    }

    private func fileLogRow(_ entry: DiagnosticFileEntry) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(entry.time)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.white.opacity(0.3))
                .frame(width: selectedTab == .traces ? 118 : 132, alignment: .leading)
                .lineLimit(1)

            Text(entry.level == .success ? "✓" : entry.level == .warning ? "⚠" : entry.level == .error ? "✗" : "›")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(iconColor(entry.level))
                .frame(width: 10)

            Text(entry.message)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(textColor(entry.level))
                .lineLimit(selectedTab == .traces ? 4 : 3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 1)
        .textSelection(.enabled)
    }

    private func iconColor(_ level: DiagnosticLog.Entry.Level) -> Color {
        switch level {
        case .info:    return .white.opacity(0.5)
        case .success: return .green
        case .warning: return .yellow
        case .error:   return .red
        }
    }

    private func textColor(_ level: DiagnosticLog.Entry.Level) -> Color {
        switch level {
        case .info:    return .white.opacity(0.7)
        case .success: return .green.opacity(0.9)
        case .warning: return .yellow.opacity(0.9)
        case .error:   return .red.opacity(0.9)
        }
    }
}
