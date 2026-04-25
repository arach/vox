import Foundation
import VoxCore

#if canImport(FluidAudio)
import FluidAudio
#endif

final class FluidAudioParakeetRuntime: @unchecked Sendable, ParakeetRuntime {
    var isAvailable: Bool {
#if canImport(FluidAudio)
        true
#else
        false
#endif
    }

#if canImport(FluidAudio)
    private var loadedModels: AsrModels?
    private var manager: AsrManager?
#endif

    func isPreloaded() async -> Bool {
#if canImport(FluidAudio)
        return manager != nil
#else
        return false
#endif
    }

    func load(from directory: URL, progress: @escaping @Sendable (ModelProgress) -> Void) async throws {
#if canImport(FluidAudio)
        if manager != nil {
            progress(ModelProgress(modelId: ParakeetModelManifest.v3.modelId, progress: 1.0, status: "ready"))
            return
        }

        progress(ModelProgress(modelId: ParakeetModelManifest.v3.modelId, progress: 0.85, status: "loading"))
        let loadedModels = try await AsrModels.load(from: directory, version: .v3)

        let manager = AsrManager(config: .init())
        try await manager.loadModels(loadedModels)
        self.loadedModels = loadedModels
        self.manager = manager
        progress(ModelProgress(modelId: ParakeetModelManifest.v3.modelId, progress: 1.0, status: "ready"))
#else
        throw NSError(domain: "VoxEngine", code: 2, userInfo: [
            NSLocalizedDescriptionKey: "FluidAudio is unavailable in this build."
        ])
#endif
    }

    func transcribe(url: URL) async throws -> ParakeetInferenceResult {
#if canImport(FluidAudio)
        guard let manager else {
            throw NSError(domain: "VoxEngine", code: 4, userInfo: [
                NSLocalizedDescriptionKey: "Parakeet manager is not initialized."
            ])
        }

        var decoderState = TdtDecoderState.make()
        let result = try await manager.transcribe(url, decoderState: &decoderState)
        let words: [WordTiming] = (result.tokenTimings ?? []).compactMap { timing in
            let word = timing.token.trimmingCharacters(in: .whitespaces)
            guard !word.isEmpty else { return nil }
            return WordTiming(
                word: word,
                start: timing.startTime,
                end: timing.endTime,
                confidence: timing.confidence
            )
        }

        return ParakeetInferenceResult(text: result.text, words: words)
#else
        throw NSError(domain: "VoxEngine", code: 5, userInfo: [
            NSLocalizedDescriptionKey: "FluidAudio is unavailable in this build."
        ])
#endif
    }
}
