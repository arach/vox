import Foundation

enum BuiltinExternalProviderKind: String {
    case asr
    case tts
}

enum BuiltinExternalProviderError: Error, LocalizedError {
    case missingResource(String)

    var errorDescription: String? {
        switch self {
        case .missingResource(let name):
            return "Missing bundled provider resource: \(name)"
        }
    }
}

struct BuiltinExternalProvider {
    static func mlxAudioCommand(
        kind: BuiltinExternalProviderKind,
        env: [String: String]?
    ) throws -> [String] {
        guard let scriptURL = Bundle.module.url(forResource: "mlx_audio_provider", withExtension: "py") else {
            throw BuiltinExternalProviderError.missingResource("mlx_audio_provider.py")
        }

        let mergedEnv = mlxAudioEnvironment(env)
        if shouldUseUvRunner(mergedEnv) {
            return uvRunnerCommand(kind: kind, scriptPath: scriptURL.path, env: mergedEnv)
        }

        let pythonOverride = env?["VOX_MLX_AUDIO_PYTHON"]
            ?? ProcessInfo.processInfo.environment["VOX_MLX_AUDIO_PYTHON"]

        if let pythonOverride, !pythonOverride.isEmpty {
            return [
                pythonOverride,
                "-u",
                scriptURL.path,
                "--kind",
                kind.rawValue
            ]
        }

        return [
            "/usr/bin/env",
            "python3",
            "-u",
            scriptURL.path,
            "--kind",
            kind.rawValue
        ]
    }

    static func mlxAudioEnvironment(_ env: [String: String]?) -> [String: String] {
        var merged = env ?? [:]
        if merged["PYTHONUNBUFFERED"] == nil {
            merged["PYTHONUNBUFFERED"] = "1"
        }

        if shouldUseUvRunner(merged) {
            merged["PATH"] = expandedExecutableSearchPath(merged["PATH"])
        }

        let pythonOverride = merged["VOX_MLX_AUDIO_PYTHON"]
            ?? ProcessInfo.processInfo.environment["VOX_MLX_AUDIO_PYTHON"]
        if merged["VIRTUAL_ENV"] == nil,
           let pythonOverride,
           let virtualEnv = inferredVirtualEnv(fromPythonPath: pythonOverride)
        {
            merged["VIRTUAL_ENV"] = virtualEnv
        }

        return merged
    }

    private static func shouldUseUvRunner(_ env: [String: String]) -> Bool {
        guard let rawValue = env["VOX_MLX_AUDIO_USE_UV"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        else {
            return false
        }

        return ["1", "true", "yes", "on"].contains(rawValue)
    }

    private static func uvRunnerCommand(
        kind: BuiltinExternalProviderKind,
        scriptPath: String,
        env: [String: String]
    ) -> [String] {
        let uvExecutable = resolvedUvExecutable(env: env)
        var command = uvExecutable == "/usr/bin/env"
            ? ["/usr/bin/env", "uv", "run"]
            : [uvExecutable, "run"]

        for dependency in uvRunnerDependencies(for: kind) {
            command.append(contentsOf: ["--with", dependency])
        }

        command.append(contentsOf: ["python", "-u", scriptPath, "--kind", kind.rawValue])
        return command
    }

    private static func resolvedUvExecutable(env: [String: String]) -> String {
        let explicit = env["VOX_MLX_AUDIO_UV"]
            ?? ProcessInfo.processInfo.environment["VOX_MLX_AUDIO_UV"]
        if let explicit, !explicit.isEmpty {
            return explicit
        }

        let fileManager = FileManager.default
        for directory in expandedExecutableSearchPath(env["PATH"]).split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(directory))
                .appendingPathComponent("uv")
                .path
            if fileManager.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        return "/usr/bin/env"
    }

    private static func expandedExecutableSearchPath(_ path: String?) -> String {
        var entries = path?
            .split(separator: ":")
            .map(String.init) ?? []

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let defaults = [
            "\(home)/.local/bin",
            "\(home)/.cargo/bin",
            "\(home)/.bun/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
        ]

        for entry in defaults where !entries.contains(entry) {
            entries.append(entry)
        }

        return entries.joined(separator: ":")
    }

    private static func uvRunnerDependencies(for kind: BuiltinExternalProviderKind) -> [String] {
        switch kind {
        case .asr:
            return ["mlx-audio"]
        case .tts:
            return [
                "mlx-audio",
                "misaki",
                "num2words",
                "spacy",
                "espeakng-loader",
                "phonemizer-fork",
            ]
        }
    }

    private static func inferredVirtualEnv(fromPythonPath pythonPath: String) -> String? {
        let executableURL = URL(fileURLWithPath: pythonPath)
        let parentURL = executableURL.deletingLastPathComponent()
        guard ["bin", "Scripts"].contains(parentURL.lastPathComponent) else {
            return nil
        }

        let virtualEnvURL = parentURL.deletingLastPathComponent()
        let path = virtualEnvURL.path
        guard !path.isEmpty, path != "/" else {
            return nil
        }
        return path
    }
}
