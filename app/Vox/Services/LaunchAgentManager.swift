import Foundation
import VoxCore

enum LaunchAgentManager {
    static let label = "cc.voxd.daemon"
    static let plistName = "\(label).plist"
    private static let legacyLabels = ["com.vox.daemon"]

    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
            .appendingPathComponent(plistName)
    }

    static func isInstalled() -> Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    static func ensureInstalled() {
        evictLegacyAgents()

        let voxdPath = findVoxd()
        if samePath(installedVoxdPath(), voxdPath) {
            return
        }

        writeAndLoad(voxdPath: voxdPath)
    }

    static func install() {
        evictLegacyAgents()
        writeAndLoad(voxdPath: findVoxd())
    }

    static func uninstall() {
        launchctl(["bootout", "gui/\(getuid())/\(label)"])
        try? FileManager.default.removeItem(at: plistURL)
    }

    static func restart() {
        launchctl(["kickstart", "-k", "gui/\(getuid())/\(label)"])
    }

    private static func writeAndLoad(voxdPath: String) {
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [voxdPath, "--port", String(VoxDefaults.daemonPort)],
            "RunAtLoad": true,
            "KeepAlive": ["SuccessfulExit": false],
            "StandardOutPath": logPath("stdout"),
            "StandardErrorPath": logPath("stderr"),
        ]

        // Ensure LaunchAgents directory exists
        let agentsDir = plistURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: agentsDir, withIntermediateDirectories: true)

        // Ensure logs directory exists
        let logsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".vox/logs")
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)

        // Write plist
        let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try? data?.write(to: plistURL, options: .atomic)

        // Load it
        launchctl(["bootout", "gui/\(getuid())/\(label)"])
        launchctl(["bootstrap", "gui/\(getuid())", plistURL.path])
    }

    /// Boot out and remove plists for any pre-rename launch labels.
    /// Called from `install()` so first launch after rebranding is self-healing.
    private static func evictLegacyAgents() {
        let agentsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")

        for legacy in legacyLabels {
            let plistURL = agentsDir.appendingPathComponent("\(legacy).plist")
            guard FileManager.default.fileExists(atPath: plistURL.path) else { continue }
            launchctl(["bootout", "gui/\(getuid())/\(legacy)"])
            try? FileManager.default.removeItem(at: plistURL)
        }
    }

    // MARK: - Private

    private static func installedVoxdPath() -> String? {
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let arguments = plist["ProgramArguments"] as? [String],
              let path = arguments.first
        else {
            return nil
        }
        return path
    }

    private static func samePath(_ lhs: String?, _ rhs: String) -> Bool {
        guard let lhs else {
            return false
        }
        return URL(fileURLWithPath: lhs).standardizedFileURL.path == URL(fileURLWithPath: rhs).standardizedFileURL.path
    }

    private static func findVoxd() -> String {
        // 1. Bundled in the app
        if let bundled = Bundle.main.path(forResource: "voxd", ofType: nil) {
            return bundled
        }

        // 2. ~/.vox/bin/voxd
        let localBin = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".vox/bin/voxd").path
        if FileManager.default.fileExists(atPath: localBin) {
            return localBin
        }

        // 3. Check PATH via which
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["voxd"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try? process.run()
        process.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !output.isEmpty && FileManager.default.fileExists(atPath: output) {
            return output
        }

        // 4. Development fallback — built from Swift package
        let devPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("dev/vox/swift/.build/release/voxd").path
        if FileManager.default.fileExists(atPath: devPath) {
            return devPath
        }

        // Last resort
        return "/usr/local/bin/voxd"
    }

    private static func logPath(_ name: String) -> String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".vox/logs/voxd.\(name).log").path
    }

    @discardableResult
    private static func launchctl(_ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        try? process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
}
