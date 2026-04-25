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
        return merged
    }
}
