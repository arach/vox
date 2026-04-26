import Foundation
import VoxCore

public actor KokoroTTSProvider: TTSProvider {
    private let externalProvider: ExternalTTSProvider
    private let modelStore: VoxKokoroModelStore

    public init(
        id: String = VoxKokoroTTS.providerID,
        additionalEnv: [String: String] = [:]
    ) throws {
        let env = VoxKokoroTTS.environment(additionalEnv: additionalEnv)
        let command = try BuiltinExternalProvider.mlxAudioCommand(kind: .tts, env: env)
        self.externalProvider = ExternalTTSProvider(id: id, command: command, env: env)
        self.modelStore = VoxKokoroModelStore(modelId: VoxKokoroTTS.modelID, env: env)
    }

    public func models() async -> [TTSModelInfo] {
        let upstream = await externalProvider.models()
        let upstreamModel = upstream.first(where: { $0.id == VoxKokoroTTS.modelID })

        return [
            TTSModelInfo(
                id: VoxKokoroTTS.modelID,
                name: upstreamModel?.name ?? "Kokoro 82M",
                backend: VoxKokoroTTS.backendID,
                installed: modelStore.isInstalled() || (upstreamModel?.preloaded ?? false),
                preloaded: upstreamModel?.preloaded ?? false,
                available: upstreamModel?.available ?? false
            )
        ]
    }

    public func voices(modelId: String?) async throws -> [TTSVoiceInfo] {
        try await externalProvider.voices(modelId: modelId ?? VoxKokoroTTS.modelID)
    }

    public func preload(
        modelId: String,
        voiceId: String?,
        progress: @escaping @Sendable (ModelProgress) -> Void
    ) async throws -> TTSModelInfo {
        let info = try await externalProvider.preload(
            modelId: modelId,
            voiceId: voiceId,
            progress: progress
        )

        return TTSModelInfo(
            id: info.id,
            name: info.name,
            backend: VoxKokoroTTS.backendID,
            installed: true,
            preloaded: info.preloaded,
            available: info.available
        )
    }

    public func synthesize(_ request: SynthesisRequest) async throws -> SynthesisOutput {
        try await externalProvider.synthesize(request)
    }
}
