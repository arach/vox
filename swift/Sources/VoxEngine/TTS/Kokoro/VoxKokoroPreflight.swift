import Foundation
import VoxCore

public struct VoxKokoroPreflight: Sendable, Equatable {
    public let usesUv: Bool
    public let uvPath: String?
    public let modelCachePath: String
    public let installedSnapshotPath: String?

    public init(
        env: [String: String] = VoxKokoroTTS.environment(),
        processEnv: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) {
        let mergedEnv = processEnv.merging(env) { _, new in new }
        let store = VoxKokoroModelStore(env: mergedEnv)
        let pathValue = mergedEnv["PATH"] ?? ""

        self.usesUv = Self.isTruthy(mergedEnv["VOX_MLX_AUDIO_USE_UV"])
        self.uvPath = usesUv ? Self.findExecutable(named: "uv", pathValue: pathValue, fileManager: fileManager) : nil
        self.modelCachePath = store.repositoryCacheDirectory().path
        self.installedSnapshotPath = store.installedSnapshotDirectory(fileManager: fileManager)?.path
    }

    public var prerequisiteCheck: DoctorCheck {
        if usesUv {
            if let uvPath {
                return DoctorCheck(
                    name: "kokoro_prereq",
                    status: "ok",
                    detail: "uv ready at \(Self.abbreviateHomePath(uvPath))"
                )
            }

            return DoctorCheck(
                name: "kokoro_prereq",
                status: "warning",
                detail: "Install uv to enable local Kokoro TTS"
            )
        }

        return DoctorCheck(
            name: "kokoro_prereq",
            status: "ok",
            detail: "Kokoro provider environment configured"
        )
    }

    public var modelCheck: DoctorCheck {
        if let installedSnapshotPath {
            return DoctorCheck(
                name: "kokoro_model",
                status: "ok",
                detail: "Kokoro model cached in \(Self.abbreviateHomePath(installedSnapshotPath))"
            )
        }

        if prerequisiteCheck.status == "warning" {
            return DoctorCheck(
                name: "kokoro_model",
                status: "warning",
                detail: "Kokoro model not cached yet; fix prerequisites before first preload"
            )
        }

        return DoctorCheck(
            name: "kokoro_model",
            status: "warning",
            detail: "Kokoro model will download into \(Self.abbreviateHomePath(modelCachePath)) on first preload"
        )
    }

    public static func doctorChecks(
        env: [String: String] = VoxKokoroTTS.environment(),
        processEnv: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> [DoctorCheck] {
        let preflight = VoxKokoroPreflight(env: env, processEnv: processEnv, fileManager: fileManager)
        return [preflight.prerequisiteCheck, preflight.modelCheck]
    }

    private static func isTruthy(_ value: String?) -> Bool {
        guard let value else { return false }
        return ["1", "true", "yes", "on"].contains(value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    private static func findExecutable(
        named name: String,
        pathValue: String,
        fileManager: FileManager
    ) -> String? {
        for directory in pathValue.split(separator: ":").map(String.init) where !directory.isEmpty {
            let candidate = URL(fileURLWithPath: directory, isDirectory: true).appendingPathComponent(name).path
            if fileManager.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    private static func abbreviateHomePath(_ path: String) -> String {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        guard path.hasPrefix(homePath) else { return path }
        return "~" + path.dropFirst(homePath.count)
    }
}
