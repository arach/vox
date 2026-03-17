import Foundation

public enum VoxVersion {
    public static let current = "0.1.0"
}

public enum RuntimePaths {
    public static func voxHomeURL() -> URL {
        if let override = ProcessInfo.processInfo.environment["VOX_HOME"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }

        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".vox", isDirectory: true)
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

    public static func providersConfigURL() -> URL {
        voxHomeURL().appendingPathComponent("providers.json")
    }

    public static func ensureDirectories() throws {
        try FileManager.default.createDirectory(
            at: voxHomeURL(),
            withIntermediateDirectories: true
        )
    }
}
