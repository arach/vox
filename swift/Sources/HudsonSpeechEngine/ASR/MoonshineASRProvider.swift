@preconcurrency import Foundation
@preconcurrency import MoonshineVoice
import VoxCore

public actor MoonshineASRProvider: ASRProvider {
    public static let providerID = "moonshine"
    public static let fallbackModelIDs = ["moonshine:medium-streaming"]

    private let log = VoxLog.engine
    private let language: String
    private let catalogStore: ModelCatalogStore
    private let audioLoader = ASRAudioLoader()
    private var transcribers: [String: Transcriber] = [:]

    public init(
        env: [String: String]? = nil,
        catalogStore: ModelCatalogStore = .shared
    ) {
        self.catalogStore = catalogStore
        self.language = Self.resolveLanguage(env: env)
    }

    public func models() async -> [ASRModelInfo] {
        supportedModelIDs().map(modelInfo)
    }

    public func install(
        modelId: String,
        progress: @escaping @Sendable (ModelProgress) -> Void
    ) async throws -> ASRModelInfo {
        _ = try await ensureLoaded(modelId: modelId, progress: progress)
        return modelInfo(modelId: modelId)
    }

    public func preload(
        modelId: String,
        progress: @escaping @Sendable (ModelProgress) -> Void
    ) async throws -> ASRModelInfo {
        try await install(modelId: modelId, progress: progress)
    }

    public func transcribe(url: URL, modelId: String) async throws -> TranscriptionOutput {
        try validate(modelId: modelId)
        let trace = TranscriptionTrace()

        trace.begin("file_check")
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            throw NSError(domain: "VoxEngine", code: 5401, userInfo: [
                NSLocalizedDescriptionKey: "Audio file is not readable at \(url.path)"
            ])
        }
        let inputBytes = ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue) ?? 0
        trace.end("\(inputBytes) bytes")

        trace.begin("model_check")
        let wasPreloaded = transcribers[modelId] != nil
        trace.end(wasPreloaded ? "ready" : "cold")

        if !wasPreloaded {
            trace.begin("model_load")
        }
        let transcriber = try await ensureLoaded(modelId: modelId) { _ in }
        if !wasPreloaded {
            trace.end("loaded")
        }

        trace.begin("audio_load")
        let input = try audioLoader.load(from: url)
        trace.end("\(input.samples.count) samples")

        trace.begin("inference")
        let transcript = try transcriber.transcribeWithoutStreaming(
            audioData: input.samples,
            sampleRate: 16_000
        )
        let text = transcript.lines
            .map(\.text)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let words = transcript.lines.flatMap { line in
            line.words.map { word in
                VoxCore.WordTiming(
                    word: word.word,
                    start: Double(word.start),
                    end: Double(word.end),
                    confidence: word.confidence
                )
            }
        }
        let inferenceMs = trace.end("\(text.count) chars")

        let metrics = TranscriptionMetrics(
            traceId: trace.traceId,
            audioDurationMs: input.audioDurationMs,
            inputBytes: input.inputBytes,
            wasPreloaded: wasPreloaded,
            fileCheckMs: trace.durationMs(for: "file_check"),
            modelCheckMs: trace.durationMs(for: "model_check"),
            modelLoadMs: trace.durationMs(for: "model_load"),
            audioLoadMs: input.audioLoadMs,
            audioPrepareMs: 0,
            inferenceMs: inferenceMs,
            totalMs: trace.elapsedMs
        )

        log.info("Moonshine transcription trace complete \(trace.summary)")
        return TranscriptionOutput(
            modelId: modelId,
            text: text,
            elapsedMs: metrics.totalMs,
            metrics: metrics,
            words: words
        )
    }

    static func resolveLanguage(
        env: [String: String]?,
        processEnv: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        let raw = env?["VOX_MOONSHINE_LANGUAGE"]
            ?? env?["VOX_SPEECH_LANGUAGE"]
            ?? processEnv["VOX_MOONSHINE_LANGUAGE"]
            ?? processEnv["VOX_SPEECH_LANGUAGE"]
            ?? "en"
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "en" : trimmed
    }

    private func ensureLoaded(
        modelId: String,
        progress: @escaping @Sendable (ModelProgress) -> Void
    ) async throws -> Transcriber {
        try validate(modelId: modelId)
        if let transcriber = transcribers[modelId] {
            progress(ModelProgress(modelId: modelId, progress: 1.0, status: "ready"))
            return transcriber
        }

        progress(ModelProgress(modelId: modelId, progress: 0.0, status: "downloading"))
        let transcriber = try await Transcriber.load(
            language: language,
            modelArch: .mediumStreaming,
            onProgress: { download in
                let fileFraction: Double
                if download.bytesTotal > 0 {
                    fileFraction = min(1, Double(download.bytesDownloaded) / Double(download.bytesTotal))
                } else {
                    fileFraction = 0
                }
                let totalFiles = max(download.totalFiles, 1)
                let completedFiles = max(download.fileIndex - 1, 0)
                let overall = (Double(completedFiles) + fileFraction) / Double(totalFiles)
                progress(ModelProgress(
                    modelId: modelId,
                    progress: min(max(overall, 0), 0.95),
                    status: "downloading"
                ))
            }
        )
        transcribers[modelId] = transcriber
        progress(ModelProgress(modelId: modelId, progress: 1.0, status: "ready"))
        return transcriber
    }

    private func modelInfo(modelId: String) -> ASRModelInfo {
        let installed = isInstalled(modelId: modelId)
        return ASRModelInfo(
            id: modelId,
            name: "Moonshine Medium Streaming",
            backend: Self.providerID,
            installed: installed,
            preloaded: transcribers[modelId] != nil,
            available: Self.isSupportedPlatform
        )
    }

    private func isInstalled(modelId: String) -> Bool {
        guard supportedModelIDs().contains(modelId) else { return false }
        let spec = ModelSpec.stt(language: language, modelArch: .mediumStreaming)
        let directory = ModelCache.defaultRoot()
            .appendingPathComponent(ModelCache.key(for: spec), isDirectory: true)
        return AssetDownloader().isModelPresent(root: directory, spec: spec)
    }

    private func supportedModelIDs() -> [String] {
        let catalogIDs = catalogStore.moonshineModelIDs()
        return catalogIDs.isEmpty ? Self.fallbackModelIDs : catalogIDs
    }

    private func validate(modelId: String) throws {
        guard Self.isSupportedPlatform else {
            throw NSError(domain: "VoxEngine", code: 5402, userInfo: [
                NSLocalizedDescriptionKey: "Moonshine in Vox requires Apple Silicon."
            ])
        }
        guard supportedModelIDs().contains(modelId) else {
            throw NSError(domain: "VoxEngine", code: 5403, userInfo: [
                NSLocalizedDescriptionKey: "Unsupported Moonshine model: \(modelId)"
            ])
        }
    }

    private static var isSupportedPlatform: Bool {
        #if arch(arm64)
        true
        #else
        false
        #endif
    }
}
