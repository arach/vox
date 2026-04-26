import Foundation
import VoxCore

public enum VoxKokoroTTS {
    public static let providerID = "kokoro"
    public static let backendID = "kokoro"
    public static let modelID = "mlx-community/Kokoro-82M-bf16"
    public static let defaultVoiceID = "af_heart"
    public static let supportedVoiceIDs = [
        "af_heart",
        "af_bella",
        "af_nova",
        "af_sky",
        "am_adam",
        "am_echo",
        "bf_alice",
        "bf_emma",
        "bm_daniel",
        "bm_george",
        "jf_alpha",
        "jm_kumo",
        "zf_xiaobei",
        "zm_yunxi",
    ]

    public static func providerEntry(
        id: String = providerID,
        additionalEnv: [String: String] = [:]
    ) -> ProviderEntry {
        ProviderEntry(
            id: id,
            kind: .tts,
            builtin: true,
            models: [modelID],
            env: environment(additionalEnv: additionalEnv)
        )
    }

    public static func providersConfig(additionalEnv: [String: String] = [:]) -> ProvidersConfig {
        ProvidersConfig(providers: [
            providerEntry(additionalEnv: additionalEnv)
        ])
    }

    public static func makeEngine(additionalEnv: [String: String] = [:]) -> TTSEngineManager {
        TTSEngineManager(provider: TTSProviderRegistry(config: providersConfig(additionalEnv: additionalEnv)))
    }

    public static func environment(
        additionalEnv: [String: String] = [:],
        fileManager: FileManager = .default
    ) -> [String: String] {
        let huggingFaceHome = huggingFaceHomeURL(fileManager: fileManager)
        let hubCache = huggingFaceHome.appendingPathComponent("hub", isDirectory: true)
        let modelOverrides = [
            modelID: supportedVoiceIDs
        ]

        var env: [String: String] = [
            "VOX_MLX_AUDIO_USE_UV": "1",
            "VOX_MLX_AUDIO_TTS_MODELS": modelID,
            "VOX_MLX_AUDIO_TTS_DEFAULT_VOICE": defaultVoiceID,
            "VOX_MLX_AUDIO_TTS_VOICES_JSON": jsonString(for: modelOverrides),
            "VOX_PROVIDER_BACKEND": backendID,
            "HF_HOME": huggingFaceHome.path,
            "HF_HUB_CACHE": hubCache.path,
            "HUGGINGFACE_HUB_CACHE": hubCache.path,
            "TRANSFORMERS_CACHE": hubCache.path,
        ]
        env.merge(additionalEnv) { _, new in new }
        return env
    }

    public static func huggingFaceHomeURL(fileManager: FileManager = .default) -> URL {
        let _ = fileManager
        return RuntimePaths.voxHomeURL()
            .appendingPathComponent("cache", isDirectory: true)
            .appendingPathComponent("huggingface", isDirectory: true)
    }

    private static func jsonString(for payload: [String: [String]]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }
}
