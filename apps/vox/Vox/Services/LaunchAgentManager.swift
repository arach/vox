import Foundation
import VoxCore

#if canImport(Darwin)
import Darwin
#endif

struct LaunchAgentOperationStep: Identifiable, Equatable {
    enum Kind: Equatable {
        case info
        case success
        case warning
        case error
    }

    let id = UUID()
    let kind: Kind
    let title: String
    let detail: String?
}

struct LaunchAgentOperationResult: Equatable {
    let title: String
    let succeeded: Bool
    let summary: String
    let createdAt: Date
    let steps: [LaunchAgentOperationStep]
}

struct LaunchAgentStatus: Equatable {
    let plistExists: Bool
    let loaded: Bool
    let installedPath: String?
    let resolvedPath: String
    let runtime: RuntimeInfo?
    let runtimeProcessReachable: Bool
}

enum LaunchAgentManager {
    static let label = "cc.voxd.daemon"
    static let plistName = "\(label).plist"
    private static let legacyLabels = ["com.vox.daemon"]
    private static let log = VoxLog.service

    private struct LaunchctlResult {
        let arguments: [String]
        let status: Int32
        let output: String

        var command: String {
            "launchctl \(arguments.joined(separator: " "))"
        }

        var succeeded: Bool {
            status == 0
        }

        func detail(default fallback: String) -> String {
            if output.isEmpty {
                return "\(command) -> status \(status). \(fallback)"
            }
            return "\(command) -> status \(status). \(LaunchAgentManager.summarizeLaunchctlOutput(output))"
        }
    }

    private struct OperationBuilder {
        let title: String
        var steps: [LaunchAgentOperationStep] = []

        mutating func add(_ kind: LaunchAgentOperationStep.Kind, _ title: String, detail: String? = nil) {
            steps.append(LaunchAgentOperationStep(kind: kind, title: title, detail: detail))

            let message = detail.map { "\(title): \($0)" } ?? title
            switch kind {
            case .info:
                log.info(message)
            case .success:
                log.info(message)
            case .warning:
                log.warning(message)
            case .error:
                log.error(message)
            }
        }

        func finish(succeeded: Bool, summary: String) -> LaunchAgentOperationResult {
            LaunchAgentOperationResult(
                title: title,
                succeeded: succeeded,
                summary: summary,
                createdAt: Date(),
                steps: steps
            )
        }
    }

    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
            .appendingPathComponent(plistName)
    }

    static func isInstalled() -> Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    static func status() -> LaunchAgentStatus {
        let runtime = try? RuntimeRegistry.read()
        return LaunchAgentStatus(
            plistExists: isInstalled(),
            loaded: isLoaded(),
            installedPath: installedVoxdPath(),
            resolvedPath: findVoxd(),
            runtime: runtime,
            runtimeProcessReachable: runtime.map(runtimeProcessIsReachable) ?? false
        )
    }

    @discardableResult
    static func reconcileLegacyAgents() -> LaunchAgentOperationResult {
        var operation = OperationBuilder(title: "Reconcile Legacy LaunchAgents")
        operation.add(.info, "Checking legacy launch labels", detail: legacyLabels.joined(separator: ", "))
        evictLegacyAgents(operation: &operation)
        return operation.finish(succeeded: true, summary: "Legacy launch-agent cleanup complete.")
    }

    @discardableResult
    static func ensureInstalled() -> LaunchAgentOperationResult {
        var operation = OperationBuilder(title: "Ensure Daemon LaunchAgent")
        evictLegacyAgents(operation: &operation)

        let voxdPath = findVoxd()
        let installedPath = installedVoxdPath()
        let matchesInstalledPath = samePath(installedPath, voxdPath)
        let loaded = isLoaded(operation: &operation)

        operation.add(
            .info,
            "Resolved daemon binary",
            detail: "plist=\(isInstalled() ? "present" : "missing"), loaded=\(loaded), installed=\(installedPath ?? "none"), resolved=\(voxdPath)"
        )

        if matchesInstalledPath && loaded {
            let runtimeOK = appendRuntimeStatus(to: &operation)
            return operation.finish(
                succeeded: runtimeOK,
                summary: runtimeOK
                    ? "LaunchAgent is loaded and the daemon is reachable."
                    : "LaunchAgent is loaded, but Vox could not confirm the daemon runtime yet."
            )
        }

        let launched: Bool
        if matchesInstalledPath {
            launched = bootstrapExisting(operation: &operation)
        } else {
            launched = writeAndLoad(voxdPath: voxdPath, operation: &operation)
        }

        let runtimeOK = appendRuntimeStatus(to: &operation)
        return operation.finish(
            succeeded: launched && runtimeOK,
            summary: launched
                ? (runtimeOK ? "LaunchAgent loaded and daemon is reachable." : "LaunchAgent loaded, but runtime confirmation is still pending.")
                : "LaunchAgent could not be loaded."
        )
    }

    @discardableResult
    static func install() -> LaunchAgentOperationResult {
        var operation = OperationBuilder(title: "Install Daemon LaunchAgent")
        operation.add(.info, "Install requested", detail: "label=\(label)")
        evictLegacyAgents(operation: &operation)

        let launched = writeAndLoad(voxdPath: findVoxd(), operation: &operation)
        let runtimeOK = appendRuntimeStatus(to: &operation)
        return operation.finish(
            succeeded: launched && runtimeOK,
            summary: launched
                ? (runtimeOK ? "LaunchAgent installed and daemon is reachable." : "LaunchAgent installed, but runtime confirmation is still pending.")
                : "LaunchAgent install failed."
        )
    }

    @discardableResult
    static func uninstall() -> LaunchAgentOperationResult {
        var operation = OperationBuilder(title: "Uninstall Daemon LaunchAgent")
        operation.add(.info, "Uninstall requested", detail: "label=\(label)")

        let bootout = launchctl(["bootout", "gui/\(getuid())/\(label)"])
        appendLaunchctl(bootout, to: &operation, successTitle: "Stopped launchd job", failureTitle: "launchd job was not stopped")

        do {
            if FileManager.default.fileExists(atPath: plistURL.path) {
                try FileManager.default.removeItem(at: plistURL)
                operation.add(.success, "Removed LaunchAgent plist", detail: plistURL.path)
            } else {
                operation.add(.info, "LaunchAgent plist already absent", detail: plistURL.path)
            }
            return operation.finish(succeeded: true, summary: "LaunchAgent removed.")
        } catch {
            operation.add(.error, "Failed to remove LaunchAgent plist", detail: error.localizedDescription)
            return operation.finish(succeeded: false, summary: "LaunchAgent plist could not be removed.")
        }
    }

    @discardableResult
    static func restart() -> LaunchAgentOperationResult {
        var operation = OperationBuilder(title: "Restart Daemon")
        operation.add(.info, "Restart requested", detail: "label=\(label)")

        let status = launchctl(["kickstart", "-k", "gui/\(getuid())/\(label)"])
        if status.succeeded {
            appendLaunchctl(status, to: &operation, successTitle: "Asked launchd to restart daemon", failureTitle: "Restart command failed")
            let runtimeOK = appendRuntimeStatus(to: &operation)
            return operation.finish(
                succeeded: runtimeOK,
                summary: runtimeOK
                    ? "launchd restarted the daemon and runtime is reachable."
                    : "launchd accepted restart, but runtime confirmation is still pending."
            )
        }

        appendLaunchctl(status, to: &operation, successTitle: "Asked launchd to restart daemon", failureTitle: "Restart command failed")
        operation.add(.warning, "Recovering missing launchd job", detail: "Restart cannot work until the LaunchAgent is bootstrapped.")

        evictLegacyAgents(operation: &operation)
        let voxdPath = findVoxd()
        let installedPath = installedVoxdPath()
        let matchesInstalledPath = samePath(installedPath, voxdPath)
        let recovered = matchesInstalledPath
            ? bootstrapExisting(operation: &operation)
            : writeAndLoad(voxdPath: voxdPath, operation: &operation)
        let runtimeOK = appendRuntimeStatus(to: &operation)

        return operation.finish(
            succeeded: recovered && runtimeOK,
            summary: recovered
                ? (runtimeOK ? "LaunchAgent recovered and daemon is reachable." : "LaunchAgent recovered, but runtime confirmation is still pending.")
                : "Restart failed because Vox could not bootstrap the LaunchAgent."
        )
    }

    private static func writeAndLoad(voxdPath: String, operation: inout OperationBuilder) -> Bool {
        operation.add(.info, "Writing LaunchAgent plist", detail: "daemon=\(voxdPath)")

        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [voxdPath, "--port", String(VoxDefaults.daemonPort)],
            "RunAtLoad": true,
            "KeepAlive": ["SuccessfulExit": false],
            "StandardOutPath": logPath("stdout"),
            "StandardErrorPath": logPath("stderr"),
        ]

        do {
            let agentsDir = plistURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: agentsDir, withIntermediateDirectories: true)

            let logsDir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".vox/logs")
            try FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)

            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: plistURL, options: .atomic)
            operation.add(.success, "Wrote LaunchAgent plist", detail: plistURL.path)
        } catch {
            operation.add(.error, "Failed to write LaunchAgent plist", detail: error.localizedDescription)
            return false
        }

        let bootout = launchctl(["bootout", "gui/\(getuid())/\(label)"])
        if bootout.succeeded {
            appendLaunchctl(bootout, to: &operation, successTitle: "Removed previous launchd job", failureTitle: "Previous launchd job was not removed")
        } else if bootout.status == 113 {
            operation.add(.info, "No previous launchd job to remove", detail: bootout.detail(default: "launchd did not have this job loaded."))
        } else {
            appendLaunchctl(bootout, to: &operation, successTitle: "Removed previous launchd job", failureTitle: "Previous launchd job was not removed")
        }

        return bootstrapExisting(operation: &operation)
    }

    private static func bootstrapExisting(operation: inout OperationBuilder) -> Bool {
        guard FileManager.default.fileExists(atPath: plistURL.path) else {
            operation.add(.error, "Cannot bootstrap missing LaunchAgent plist", detail: plistURL.path)
            return false
        }

        let result = launchctl(["bootstrap", "gui/\(getuid())", plistURL.path])
        appendLaunchctl(result, to: &operation, successTitle: "Bootstrapped LaunchAgent", failureTitle: "LaunchAgent bootstrap failed")
        return result.succeeded
    }

    private static func evictLegacyAgents(operation: inout OperationBuilder) {
        let agentsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")

        for legacy in legacyLabels {
            let legacyURL = agentsDir.appendingPathComponent("\(legacy).plist")
            guard FileManager.default.fileExists(atPath: legacyURL.path) else { continue }
            operation.add(.info, "Removing legacy LaunchAgent", detail: legacy)
            appendLaunchctl(
                launchctl(["bootout", "gui/\(getuid())/\(legacy)"]),
                to: &operation,
                successTitle: "Stopped legacy LaunchAgent",
                failureTitle: "Legacy LaunchAgent was not loaded"
            )
            do {
                try FileManager.default.removeItem(at: legacyURL)
                operation.add(.success, "Removed legacy plist", detail: legacyURL.path)
            } catch {
                operation.add(.warning, "Could not remove legacy plist", detail: error.localizedDescription)
            }
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

    private static func isLoaded() -> Bool {
        launchctl(["print", "gui/\(getuid())/\(label)"], shouldLog: false).succeeded
    }

    private static func isLoaded(operation: inout OperationBuilder) -> Bool {
        let result = launchctl(["print", "gui/\(getuid())/\(label)"], shouldLog: false)
        if result.succeeded {
            operation.add(.success, "LaunchAgent is loaded", detail: "launchd knows \(label).")
        } else {
            operation.add(.warning, "LaunchAgent is not loaded", detail: result.detail(default: "launchd has no active job for \(label)."))
        }
        return result.succeeded
    }

    private static func appendRuntimeStatus(to operation: inout OperationBuilder, timeout: TimeInterval = 2.0) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        var lastDetail = RuntimePaths.runtimeFileURL().path

        while Date() < deadline {
            if let runtime = try? RuntimeRegistry.read(), runtimeProcessIsReachable(runtime) {
                let detail = "pid=\(runtime.pid), port=\(runtime.port), version=\(runtime.version), file=\(RuntimePaths.runtimeFileURL().path)"
                operation.add(.success, "Daemon runtime reachable", detail: detail)
                return true
            }

            if let runtime = try? RuntimeRegistry.read() {
                lastDetail = "pid=\(runtime.pid), port=\(runtime.port), version=\(runtime.version), file=\(RuntimePaths.runtimeFileURL().path)"
            }

            Thread.sleep(forTimeInterval: 0.2)
        }

        do {
            guard let runtime = try RuntimeRegistry.read() else {
                operation.add(.warning, "Runtime file unavailable", detail: "\(lastDetail) after \(String(format: "%.1f", timeout))s")
                return false
            }

            let reachable = runtimeProcessIsReachable(runtime)
            let detail = "pid=\(runtime.pid), port=\(runtime.port), version=\(runtime.version), file=\(RuntimePaths.runtimeFileURL().path)"
            operation.add(
                reachable ? .success : .warning,
                reachable ? "Daemon runtime reachable" : "Runtime file points to an unreachable process",
                detail: detail
            )
            return reachable
        } catch {
            operation.add(.error, "Failed to read runtime file", detail: error.localizedDescription)
            return false
        }
    }

    private static func runtimeProcessIsReachable(_ runtime: RuntimeInfo) -> Bool {
        #if canImport(Darwin)
        errno = 0
        return kill(runtime.pid, 0) == 0 || errno == EPERM
        #else
        return true
        #endif
    }

    private static func appendLaunchctl(
        _ result: LaunchctlResult,
        to operation: inout OperationBuilder,
        successTitle: String,
        failureTitle: String
    ) {
        operation.add(
            result.succeeded ? .success : .error,
            result.succeeded ? successTitle : failureTitle,
            detail: result.detail(default: result.succeeded ? "launchd accepted the request." : "launchd rejected the request.")
        )
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

        // 4. Development fallback - built from Swift package
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

    private static func summarizeLaunchctlOutput(_ output: String) -> String {
        guard output.count > 240 else {
            return output
        }

        let firstLines = output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .prefix(3)
            .joined(separator: " | ")
        return "\(firstLines) ... (\(output.count) chars)"
    }

    private static func launchctl(_ arguments: [String], shouldLog: Bool = true) -> LaunchctlResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        if shouldLog {
            log.info("LaunchAgent launchctl start arguments=\(arguments.joined(separator: " "))")
        }
        do {
            try process.run()
        } catch {
            let result = LaunchctlResult(
                arguments: arguments,
                status: -1,
                output: error.localizedDescription
            )
            if shouldLog {
                log.error("LaunchAgent launchctl failedToRun arguments=\(arguments.joined(separator: " ")) error=\(error.localizedDescription)")
            }
            return result
        }

        process.waitUntilExit()
        let stdout = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let output = [stdout, stderr].filter { !$0.isEmpty }.joined(separator: "\n")

        if shouldLog {
            log.info("LaunchAgent launchctl finished arguments=\(arguments.joined(separator: " ")) status=\(process.terminationStatus) output=\(summarizeLaunchctlOutput(output))")
        }
        return LaunchctlResult(arguments: arguments, status: process.terminationStatus, output: output)
    }
}
