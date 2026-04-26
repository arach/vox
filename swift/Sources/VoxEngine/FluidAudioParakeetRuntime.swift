import Foundation
import VoxCore

final class FluidAudioParakeetRuntime: @unchecked Sendable, ParakeetRuntime {
    private let log = VoxLog.engine
    private let modelLoader: ParakeetModelLoader
    private var loadedModels: ParakeetLoadedModels?
    private var singleChunkTranscriber: ParakeetSingleChunkTranscriber?

    init(modelLoader: ParakeetModelLoader = ParakeetModelLoader()) {
        self.modelLoader = modelLoader
    }

    var isAvailable: Bool {
        true
    }

    func isPreloaded() async -> Bool {
        singleChunkTranscriber != nil
    }

    func load(from directory: URL, progress: @escaping @Sendable (ModelProgress) -> Void) async throws {
        if singleChunkTranscriber != nil {
            progress(ModelProgress(modelId: ParakeetModelManifest.v3.modelId, progress: 1.0, status: "ready"))
            return
        }

        progress(ModelProgress(modelId: ParakeetModelManifest.v3.modelId, progress: 0.85, status: "loading"))
        let loadedModels = try modelLoader.loadModels(from: directory)
        self.loadedModels = loadedModels
        self.singleChunkTranscriber = ParakeetSingleChunkTranscriber(models: loadedModels)
        progress(ModelProgress(modelId: ParakeetModelManifest.v3.modelId, progress: 1.0, status: "ready"))
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

        guard let loadedModels else {
            throw NSError(domain: "VoxEngine", code: 5, userInfo: [
                NSLocalizedDescriptionKey: "Parakeet models are not initialized."
            ])
        }

        log.info("Using Vox-owned long-form Parakeet chunk processor")
        return try await ParakeetChunkProcessor(
            audioSamples: samples,
            workerCount: max(1, ParakeetInferenceConfig.default.parallelChunkConcurrency),
            transcriberFactory: {
                ParakeetSingleChunkTranscriber(models: loadedModels)
            }
        ).process()
    }
}
