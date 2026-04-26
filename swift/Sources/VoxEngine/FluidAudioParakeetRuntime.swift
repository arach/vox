import Foundation
import VoxCore

#if canImport(FluidAudio)
import FluidAudio
#endif

final class FluidAudioParakeetRuntime: @unchecked Sendable, ParakeetRuntime {
    private let log = VoxLog.engine
    private let modelLoader: ParakeetModelLoader

    init(modelLoader: ParakeetModelLoader = ParakeetModelLoader()) {
        self.modelLoader = modelLoader
    }

    var isAvailable: Bool {
#if canImport(FluidAudio)
        true
#else
        false
#endif
    }

#if canImport(FluidAudio)
    private var loadedModels: ParakeetLoadedModels?
    private var manager: AsrManager?
#endif
    private var singleChunkTranscriber: ParakeetSingleChunkTranscriber?

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
        let loadedModels = try modelLoader.loadModels(from: directory)
        self.loadedModels = loadedModels
        self.singleChunkTranscriber = ParakeetSingleChunkTranscriber(models: loadedModels)

#if canImport(FluidAudio)
        let manager = AsrManager(config: .init())
        try await manager.loadModels(loadedModels.asrModels())
        self.manager = manager
#endif
        progress(ModelProgress(modelId: ParakeetModelManifest.v3.modelId, progress: 1.0, status: "ready"))
#else
        throw NSError(domain: "VoxEngine", code: 2, userInfo: [
            NSLocalizedDescriptionKey: "FluidAudio is unavailable in this build."
        ])
#endif
    }

    func transcribe(samples: [Float]) async throws -> ParakeetInferenceResult {
        guard let singleChunkTranscriber else {
            throw NSError(domain: "VoxEngine", code: 4, userInfo: [
                NSLocalizedDescriptionKey: "Parakeet runtime is not initialized."
            ])
        }

        if samples.count <= ParakeetConstants.maxModelSamples {
            log.info("Using Vox-owned single-chunk Parakeet runtime")
            return try await singleChunkTranscriber.transcribe(samples: samples)
        }

#if canImport(FluidAudio)
        guard let manager else {
            throw NSError(domain: "VoxEngine", code: 5, userInfo: [
                NSLocalizedDescriptionKey: "Parakeet long-audio fallback is not initialized."
            ])
        }

        log.info("Using FluidAudio long-audio Parakeet fallback")
        var decoderState = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
        let result = try await manager.transcribe(samples, decoderState: &decoderState)
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
        throw NSError(domain: "VoxEngine", code: 6, userInfo: [
            NSLocalizedDescriptionKey: "Long-form Parakeet transcription is unavailable in this build."
        ])
#endif
    }
}
