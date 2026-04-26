import Foundation
import VoxCore

public final class ParakeetProvider: @unchecked Sendable, ASRProvider {
    private let log = VoxLog.engine
    private let manifest: ParakeetModelManifest
    private let store: ParakeetModelStore
    private let runtime: any ParakeetRuntime
    private let audioLoader: ParakeetAudioLoader

    public init() {
        self.manifest = .v3
        self.store = ParakeetModelStore(manifest: .v3)
        self.runtime = FluidAudioParakeetRuntime()
        self.audioLoader = ParakeetAudioLoader()
    }

    init(
        manifest: ParakeetModelManifest = .v3,
        store: ParakeetModelStore? = nil,
        runtime: (any ParakeetRuntime)? = nil,
        audioLoader: ParakeetAudioLoader = ParakeetAudioLoader()
    ) {
        self.manifest = manifest
        self.store = store ?? ParakeetModelStore(manifest: manifest)
        self.runtime = runtime ?? FluidAudioParakeetRuntime()
        self.audioLoader = audioLoader
    }

    public func models() async -> [ASRModelInfo] {
        [await modelInfo()]
    }

    public func install(
        modelId: String,
        progress: @escaping @Sendable (ModelProgress) -> Void
    ) async throws -> ASRModelInfo {
        try validate(modelId: modelId)
        return try await ensureLoaded(progress: progress)
    }

    public func preload(
        modelId: String,
        progress: @escaping @Sendable (ModelProgress) -> Void
    ) async throws -> ASRModelInfo {
        try validate(modelId: modelId)
        return try await ensureLoaded(progress: progress)
    }

    public func transcribe(url: URL, modelId: String) async throws -> TranscriptionOutput {
        let trace = TranscriptionTrace()

        trace.begin("file_check")
        try validate(modelId: modelId)
        try validateAudioFile(url: url)
        let inputBytes = ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue) ?? 0
        trace.end("\(inputBytes) bytes")

        trace.begin("model_check")
        let wasPreloaded = await runtime.isPreloaded()
        trace.end(wasPreloaded ? "already loaded" : "needs load")

        if !wasPreloaded {
            trace.begin("model_load")
        }
        _ = try await ensureLoaded { _ in }
        if !wasPreloaded {
            trace.end("initialized")
        }

        trace.begin("audio_load")
        let loadedInput = try audioLoader.load(from: url)
        _ = trace.end("\(loadedInput.samples.count) samples")

        trace.begin("audio_prepare")
        let prepared = ParakeetSamplePreparer.ensureMinimumDuration(samples: loadedInput.samples)
        trace.end(prepared.wasPadded ? "padded" : "unchanged")

        trace.begin("inference")
        let result = try await runtime.transcribe(samples: prepared.samples)
        let inferenceMs = trace.end("\(result.text.count) chars")

        let metrics = TranscriptionMetrics(
            traceId: trace.traceId,
            audioDurationMs: loadedInput.audioDurationMs,
            inputBytes: loadedInput.inputBytes,
            wasPreloaded: wasPreloaded,
            fileCheckMs: trace.durationMs(for: "file_check"),
            modelCheckMs: trace.durationMs(for: "model_check"),
            modelLoadMs: trace.durationMs(for: "model_load"),
            audioLoadMs: loadedInput.audioLoadMs,
            audioPrepareMs: trace.durationMs(for: "audio_prepare"),
            inferenceMs: inferenceMs,
            totalMs: trace.elapsedMs
        )

        log.info("Trace complete \(trace.summary)")
        return TranscriptionOutput(
            modelId: manifest.modelId,
            text: result.text,
            elapsedMs: metrics.totalMs,
            metrics: metrics,
            words: result.words
        )
    }

    private func validate(modelId: String) throws {
        guard modelId == manifest.modelId else {
            throw NSError(domain: "VoxEngine", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Unsupported model: \(modelId)"
            ])
        }
    }

    func validateAudioFile(url: URL) throws {
        let path = url.path
        guard FileManager.default.fileExists(atPath: path) else {
            throw NSError(domain: "VoxEngine", code: 6, userInfo: [
                NSLocalizedDescriptionKey: "Audio file not found at \(path)"
            ])
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            throw NSError(domain: "VoxEngine", code: 7, userInfo: [
                NSLocalizedDescriptionKey: "Expected an audio file but found a directory at \(path)"
            ])
        }

        guard FileManager.default.isReadableFile(atPath: path) else {
            throw NSError(domain: "VoxEngine", code: 8, userInfo: [
                NSLocalizedDescriptionKey: "Audio file is not readable at \(path)"
            ])
        }
    }

    private func ensureLoaded(
        progress: @escaping @Sendable (ModelProgress) -> Void
    ) async throws -> ASRModelInfo {
        let installedDirectory = try await store.ensureInstalled(progress: progress)
        try await runtime.load(from: installedDirectory, progress: progress)
        log.info("\(manifest.name) loaded")
        return await modelInfo()
    }

    private func modelInfo() async -> ASRModelInfo {
        ASRModelInfo(
            id: manifest.modelId,
            name: manifest.name,
            backend: manifest.backend,
            installed: store.isInstalled(),
            preloaded: await runtime.isPreloaded(),
            available: isBackendAvailable()
        )
    }

    private func isBackendAvailable() -> Bool {
        runtime.isAvailable
    }
}

struct ParakeetSamplePreparationResult {
    let samples: [Float]
    let wasPadded: Bool
}

enum ParakeetSamplePreparer {
    private static let minimumDurationSeconds: Double = 1.5
    private static let sampleRate: Double = 16_000

    static func ensureMinimumDuration(samples: [Float]) -> ParakeetSamplePreparationResult {
        let minimumSamples = Int((minimumDurationSeconds * sampleRate).rounded(.up))
        guard samples.count < minimumSamples else {
            return ParakeetSamplePreparationResult(samples: samples, wasPadded: false)
        }

        let padded = samples + Array(repeating: 0, count: minimumSamples - samples.count)
        return ParakeetSamplePreparationResult(samples: padded, wasPadded: true)
    }
}
