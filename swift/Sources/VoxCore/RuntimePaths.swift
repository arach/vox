import Foundation

public enum VoxVersion {
    public static let current = "0.2.0"
}

public enum VoxDefaults {
    public static let daemonPort: UInt16 = 42137
    public static let bridgePort: UInt16 = 43115
    public static let host = "127.0.0.1"

    public static func resolvedDaemonPort() -> UInt16 {
        if let raw = ProcessInfo.processInfo.environment["VOX_PORT"],
           let port = UInt16(raw) {
            return port
        }
        return daemonPort
    }

    public static func resolvedBridgePort() -> UInt16 {
        if let raw = ProcessInfo.processInfo.environment["VOX_BRIDGE_PORT"],
           let port = UInt16(raw) {
            return port
        }
        return bridgePort
    }

    public static func resolvedHost() -> String {
        if let host = ProcessInfo.processInfo.environment["VOX_HOST"], !host.isEmpty {
            return host
        }
        return host
    }
}

public enum RuntimePaths {
    public static func voxHomeURL() -> URL {
        if let override = ProcessInfo.processInfo.environment["VOX_HOME"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }

        let fileManager = FileManager.default

        #if os(iOS)
        let baseDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return baseDirectory
            .appendingPathComponent("Vox", isDirectory: true)
        #else
        return fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".vox", isDirectory: true)
        #endif
    }

    public static func runtimeFileURL() -> URL {
        if let override = ProcessInfo.processInfo.environment["VOX_RUNTIME_PATH"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }

        return voxHomeURL().appendingPathComponent("runtime.json")
    }

    public static func performanceLogURL() -> URL {
        voxHomeURL().appendingPathComponent("performance.jsonl")
    }

    public static func voiceLogURL() -> URL {
        voxHomeURL().appendingPathComponent("voice.jsonl")
    }

    public static func logsDirectoryURL() -> URL {
        voxHomeURL().appendingPathComponent("logs", isDirectory: true)
    }

    public static func daemonLogURL() -> URL {
        logsDirectoryURL().appendingPathComponent("voxd.log")
    }

    public static func providersConfigURL() -> URL {
        voxHomeURL().appendingPathComponent("providers.json")
    }

    public static func bridgeOriginsFileURL() -> URL {
        voxHomeURL().appendingPathComponent("origins.json")
    }

    public static func bridgeOriginsDirectoryURL() -> URL {
        voxHomeURL().appendingPathComponent("origins.d", isDirectory: true)
    }

    public static func ensureDirectories() throws {
        try FileManager.default.createDirectory(
            at: voxHomeURL(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: logsDirectoryURL(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: bridgeOriginsDirectoryURL(),
            withIntermediateDirectories: true
        )
    }
}
