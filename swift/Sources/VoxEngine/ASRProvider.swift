import Foundation
import VoxCore

public protocol ASRProvider: Sendable {
    func models() async -> [ASRModelInfo]
    func install(modelId: String, progress: @escaping @Sendable (ModelProgress) -> Void) async throws -> ASRModelInfo
    func preload(modelId: String, progress: @escaping @Sendable (ModelProgress) -> Void) async throws -> ASRModelInfo
    func transcribe(url: URL, modelId: String) async throws -> TranscriptionOutput
}

public actor EngineManager {
    private let provider: any ASRProvider

    public init(provider: any ASRProvider = ParakeetProvider()) {
        self.provider = provider
    }

    public func models() async -> [ASRModelInfo] {
        await provider.models()
    }

    public func install(
        modelId: String,
        progress: @escaping @Sendable (ModelProgress) -> Void
    ) async throws -> ASRModelInfo {
        try await provider.install(modelId: modelId, progress: progress)
    }

    public func preload(
        modelId: String,
        progress: @escaping @Sendable (ModelProgress) -> Void
    ) async throws -> ASRModelInfo {
        try await provider.preload(modelId: modelId, progress: progress)
    }

    public func transcribe(url: URL, modelId: String) async throws -> TranscriptionOutput {
        try await provider.transcribe(url: url, modelId: modelId)
    }
}
