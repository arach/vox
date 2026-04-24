import Foundation
import VoxCore

public actor TTSProviderRegistry: TTSProvider {
    private let log = VoxLog.engine
    private var providers: [(entry: ProviderEntry, provider: any TTSProvider)] = []
    private var modelRouting: [String: any TTSProvider] = [:]

    public init(config: ProvidersConfig) {
        for entry in config.providers where entry.resolvedKind == .tts {
            let provider: any TTSProvider

            if entry.isBuiltin {
                switch entry.id.lowercased() {
                case "avspeech", "avspeechsynthesizer", "apple-tts", "system-tts":
                    provider = AVSpeechSynthesizerProvider()
                case "openai", "openai-tts":
                    provider = OpenAITTSProvider(env: entry.env)
                default:
                    log.warning("Skipping unknown builtin TTS provider: \(entry.id)")
                    continue
                }
                log.info("Registered builtin TTS provider: \(entry.id)")
            } else if entry.isExternal, let command = entry.command {
                provider = ExternalTTSProvider(id: entry.id, command: command, env: entry.env)
                log.info("Registered external TTS provider: \(entry.id) → \(command.joined(separator: " "))")
            } else {
                log.warning("Skipping TTS provider \(entry.id): no builtin flag or command specified")
                continue
            }

            providers.append((entry: entry, provider: provider))

            if let models = entry.models {
                for modelId in models {
                    modelRouting[modelId] = provider
                }
            }
        }
    }

    public func models() async -> [TTSModelInfo] {
        await withTaskGroup(of: [TTSModelInfo].self) { group in
            for (_, provider) in providers {
                group.addTask {
                    await provider.models()
                }
            }

            var all: [TTSModelInfo] = []
            for await batch in group {
                all.append(contentsOf: batch)
            }
            return all.sorted { lhs, rhs in
                lhs.id.localizedCaseInsensitiveCompare(rhs.id) == .orderedAscending
            }
        }
    }

    public func voices(modelId: String?) async throws -> [TTSVoiceInfo] {
        if let modelId {
            let provider = try resolveProvider(for: modelId)
            return try await provider.voices(modelId: modelId)
        }

        let models = await self.models()
        return try await withThrowingTaskGroup(of: [TTSVoiceInfo].self) { group in
            for model in models {
                group.addTask {
                    let provider = try await self.resolveProvider(for: model.id)
                    return try await provider.voices(modelId: model.id)
                }
            }

            var all: [TTSVoiceInfo] = []
            for try await batch in group {
                all.append(contentsOf: batch)
            }
            return all.sorted { lhs, rhs in
                if lhs.modelId == rhs.modelId {
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                return lhs.modelId.localizedCaseInsensitiveCompare(rhs.modelId) == .orderedAscending
            }
        }
    }

    public func preload(
        modelId: String,
        voiceId: String?,
        progress: @escaping @Sendable (ModelProgress) -> Void
    ) async throws -> TTSModelInfo {
        let provider = try resolveProvider(for: modelId)
        return try await provider.preload(modelId: modelId, voiceId: voiceId, progress: progress)
    }

    public func synthesize(_ request: SynthesisRequest) async throws -> SynthesisOutput {
        let provider = try resolveProvider(for: request.modelId)
        return try await provider.synthesize(request)
    }

    private func resolveProvider(for modelId: String) throws -> any TTSProvider {
        if let provider = modelRouting[modelId] {
            return provider
        }

        if providers.count == 1 {
            return providers[0].provider
        }

        throw TTSProviderRegistryError.unknownModel(modelId)
    }
}

public enum TTSProviderRegistryError: Error, LocalizedError {
    case unknownModel(String)

    public var errorDescription: String? {
        switch self {
        case .unknownModel(let id):
            return "No TTS provider registered for model '\(id)'"
        }
    }
}
