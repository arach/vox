import Foundation

enum LaunchAgentManager {
    static let label = "com.vox.daemon"
    static let plistName = "\(label).plist"

    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
            .appendingPathComponent(plistName)
    }

    static func isInstalled() -> Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    static func install() {
        let voxdPath = findVoxd()

        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [voxdPath, "--port", "42137"],
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
        launchctl(["bootstrap", "gui/\(getuid())", plistURL.path])
    }

    static func uninstall() {
        launchctl(["bootout", "gui/\(getuid())/\(label)"])
        try? FileManager.default.removeItem(at: plistURL)
    }

    static func restart() {
        launchctl(["kickstart", "-k", "gui/\(getuid())/\(label)"])
    }

    // MARK: - Private

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
