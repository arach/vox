import AppKit
import SwiftUI

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
        w.isMovableByWindowBackground = true
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
    @StateObject private var log = DiagnosticLog.shared
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
            // Header
            HStack {
                Text("DIAGNOSTICS")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.green.opacity(0.8))
                Spacer()
                let _ = refreshTick  // force re-render on timer
                Text("\(log.entries.count) events")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
                Button("Copy") {
                    let text = log.entries.map { entry in
                        let t = Self.timeFmt.string(from: entry.time)
                        return "\(t) \(entry.icon) \(entry.message)"
                    }.joined(separator: "\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))
                .buttonStyle(.plain)
                Button("Clear") { log.clear() }
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.3))
            .onReceive(refreshTimer) { _ in refreshTick += 1 }

            // Log entries
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(log.entries) { entry in
                            logRow(entry)
                                .id(entry.id)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
                .onChange(of: log.entries.count) { _, _ in
                    if autoScroll, let last = log.entries.last {
                        withAnimation(.easeOut(duration: 0.1)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .frame(minWidth: 420, idealWidth: 480, minHeight: 400, idealHeight: 600)
        .background(Color.black.opacity(0.75))
    }

    private func logRow(_ entry: DiagnosticLog.Entry) -> some View {
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
