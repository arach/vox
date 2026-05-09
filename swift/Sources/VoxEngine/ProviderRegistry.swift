import Foundation
import VoxCore

public actor ProviderRegistry: ASRProvider {
    private let log = VoxLog.engine
    private var providers: [(entry: ProviderEntry, provider: any ASRProvider)] = []
    private var modelRouting: [String: any ASRProvider] = [:]

    public init(config: ProvidersConfig) {
        for entry in config.providers where entry.resolvedKind == .asr {
            let provider: any ASRProvider

            if entry.isBuiltin {
                switch entry.id.lowercased() {
                case "parakeet", "parakeet-asr":
                    provider = ParakeetProvider()
                    log.info("Registered builtin provider: \(entry.id)")
                case "mlx-audio", "mlx_audio", "mlx-audio-stt", "mlx_audio_stt":
                    do {
                        let env = BuiltinExternalProvider.mlxAudioEnvironment(entry.env)
                        let command = try BuiltinExternalProvider.mlxAudioCommand(kind: .asr, env: env)
                        provider = ExternalProvider(id: entry.id, command: command, env: env)
                        log.info("Registered builtin mlx-audio ASR provider: \(entry.id)")
                    } catch {
                        log.error("Skipping builtin ASR provider \(entry.id): \(error.localizedDescription)")
                        continue
                    }
                default:
                    log.warning("Skipping unknown builtin ASR provider: \(entry.id)")
                    continue
                }
            } else if entry.isExternal, let command = entry.command {
                provider = ExternalProvider(id: entry.id, command: command, env: entry.env)
                log.info("Registered external provider: \(entry.id) → \(command.joined(separator: " "))")
            } else {
                log.warning("Skipping provider \(entry.id): no builtin flag or command specified")
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

    public func models() async -> [ASRModelInfo] {
        await withTaskGroup(of: [ASRModelInfo].self) { group in
            for (_, provider) in providers {
                group.addTask {
                    await provider.models()
                }
            }
            var all: [ASRModelInfo] = []
            for await batch in group {
                all.append(contentsOf: batch)
            }
            return all.sorted { lhs, rhs in
                lhs.id.localizedCaseInsensitiveCompare(rhs.id) == .orderedAscending
            }
        }
    }

    public func install(
        modelId: String,
        progress: @escaping @Sendable (ModelProgress) -> Void
    ) async throws -> ASRModelInfo {
        let provider = try await resolveProvider(for: modelId)
        return try await provider.install(modelId: modelId, progress: progress)
    }

    public func preload(
        modelId: String,
        progress: @escaping @Sendable (ModelProgress) -> Void
    ) async throws -> ASRModelInfo {
        let provider = try await resolveProvider(for: modelId)
        return try await provider.preload(modelId: modelId, progress: progress)
    }

    public func transcribe(url: URL, modelId: String) async throws -> TranscriptionOutput {
        let provider = try await resolveProvider(for: modelId)
        return try await provider.transcribe(url: url, modelId: modelId)
    }

    public func shutdown() async {
        for (_, provider) in providers {
            if let externalProvider = provider as? ExternalProvider {
                await externalProvider.shutdown()
            }
        }
    }

    private func resolveProvider(for modelId: String) async throws -> any ASRProvider {
        if let provider = modelRouting[modelId] {
            return provider
        }

        // Fall back to first provider if only one is registered
        if providers.count == 1 {
            return providers[0].provider
        }

        for (_, provider) in providers {
            let models = await provider.models()
            if models.contains(where: { $0.id == modelId }) {
                for model in models {
                    modelRouting[model.id] = provider
                }
                return provider
            }
        }

        throw ProviderRegistryError.unknownModel(modelId)
    }
}

public enum ProviderRegistryError: Error, LocalizedError {
    case unknownModel(String)

    public var errorDescription: String? {
        switch self {
        case .unknownModel(let id):
            return "No provider registered for model '\(id)'"
        }
    }
}
