import Foundation
import VoxCore

public actor ProviderRegistry: ASRProvider {
    private let log = VoxLog.engine
    private var providers: [(entry: ProviderEntry, provider: any ASRProvider)] = []
    private var modelRouting: [String: any ASRProvider] = [:]

    public init(config: ProvidersConfig) {
        for entry in config.providers {
            let provider: any ASRProvider

            if entry.isBuiltin {
                provider = ParakeetProvider()
                log.info("Registered builtin provider: \(entry.id)")
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
            return all
        }
    }

    public func install(
        modelId: String,
        progress: @escaping @Sendable (ModelProgress) -> Void
    ) async throws -> ASRModelInfo {
        let provider = try resolveProvider(for: modelId)
        return try await provider.install(modelId: modelId, progress: progress)
    }

    public func preload(
        modelId: String,
        progress: @escaping @Sendable (ModelProgress) -> Void
    ) async throws -> ASRModelInfo {
        let provider = try resolveProvider(for: modelId)
        return try await provider.preload(modelId: modelId, progress: progress)
    }

    public func transcribe(url: URL, modelId: String) async throws -> TranscriptionOutput {
        let provider = try resolveProvider(for: modelId)
        return try await provider.transcribe(url: url, modelId: modelId)
    }

    private func resolveProvider(for modelId: String) throws -> any ASRProvider {
        if let provider = modelRouting[modelId] {
            return provider
        }

        // Fall back to first provider if only one is registered
        if providers.count == 1 {
            return providers[0].provider
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
