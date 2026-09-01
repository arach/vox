#if os(macOS) && arch(arm64)
@preconcurrency import AVFoundation
import CoreMedia
import Foundation
@preconcurrency import Speech
import VoxCore

public actor AppleSpeechTranscriberProvider: ASRProvider {
    public static let providerID = "apple-speech"
    public static let fallbackModelIDs = ["apple:speech-transcriber"]

    private let log = VoxLog.engine
    private let localeIdentifier: String
    private let catalogStore: ModelCatalogStore
    private var preloadedModels: Set<String> = []

    public init(
        env: [String: String]? = nil,
        catalogStore: ModelCatalogStore = .shared
    ) {
        self.catalogStore = catalogStore
        self.localeIdentifier = Self.resolveLocaleIdentifier(env: env)
    }

    public func models() async -> [ASRModelInfo] {
        guard #available(macOS 26.0, *) else {
            return supportedModelIDs().map { unavailableModelInfo(modelId: $0) }
        }

        let locale = await SpeechTranscriber.supportedLocale(
            equivalentTo: Locale(identifier: localeIdentifier)
        )
        guard let locale, SpeechTranscriber.isAvailable else {
            return supportedModelIDs().map { unavailableModelInfo(modelId: $0) }
        }

        let transcriber = SpeechTranscriber(
            locale: locale,
            preset: .timeIndexedTranscriptionWithAlternatives
        )
        let status = await AssetInventory.status(forModules: [transcriber])
        return supportedModelIDs().map { modelId in
            ASRModelInfo(
                id: modelId,
                name: "Apple SpeechTranscriber",
                backend: Self.providerID,
                installed: status == .installed,
                preloaded: preloadedModels.contains(modelId),
                available: status != .unsupported
            )
        }
    }

    public func install(
        modelId: String,
        progress: @escaping @Sendable (ModelProgress) -> Void
    ) async throws -> ASRModelInfo {
        try validate(modelId: modelId)
        guard #available(macOS 26.0, *) else {
            throw unavailableError()
        }

        let transcriber = try await makeTranscriber()
        try await ensureAssets(for: transcriber, modelId: modelId, progress: progress)
        return try await modelInfo(modelId: modelId, transcriber: transcriber)
    }

    public func preload(
        modelId: String,
        progress: @escaping @Sendable (ModelProgress) -> Void
    ) async throws -> ASRModelInfo {
        try validate(modelId: modelId)
        guard #available(macOS 26.0, *) else {
            throw unavailableError()
        }

        let transcriber = try await makeTranscriber()
        try await ensureAssets(for: transcriber, modelId: modelId, progress: progress)

        progress(ModelProgress(modelId: modelId, progress: 0.9, status: "preparing"))
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
        try await analyzer.prepareToAnalyze(in: format)
        preloadedModels.insert(modelId)
        progress(ModelProgress(modelId: modelId, progress: 1.0, status: "ready"))
        return try await modelInfo(modelId: modelId, transcriber: transcriber)
    }

    public func transcribe(url: URL, modelId: String) async throws -> TranscriptionOutput {
        try validate(modelId: modelId)
        guard #available(macOS 26.0, *) else {
            throw unavailableError()
        }

        let trace = TranscriptionTrace()
        trace.begin("file_check")
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            throw NSError(domain: "VoxEngine", code: 5301, userInfo: [
                NSLocalizedDescriptionKey: "Audio file is not readable at \(url.path)"
            ])
        }
        let inputBytes = ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue) ?? 0
        trace.end("\(inputBytes) bytes")

        trace.begin("model_check")
        let wasPreloaded = preloadedModels.contains(modelId)
        let transcriber = try await makeTranscriber()
        trace.end(wasPreloaded ? "ready" : "cold")

        if !wasPreloaded {
            trace.begin("model_load")
            try await ensureAssets(for: transcriber, modelId: modelId) { _ in }
            preloadedModels.insert(modelId)
            trace.end("assets ready")
        }

        trace.begin("audio_load")
        let audioFile = try AVAudioFile(forReading: url)
        let audioDurationMs = Int(
            (Double(audioFile.length) / audioFile.processingFormat.sampleRate) * 1000
        )
        trace.end("\(audioDurationMs)ms")

        trace.begin("inference")
        let outputTask = Task {
            try await Self.collectResults(from: transcriber)
        }

        do {
            let analyzer = try await SpeechAnalyzer(
                inputAudioFile: audioFile,
                modules: [transcriber],
                finishAfterFile: true
            )
            _ = analyzer
            let result = try await outputTask.value
            let inferenceMs = trace.end("\(result.text.count) chars")
            let metrics = TranscriptionMetrics(
                traceId: trace.traceId,
                audioDurationMs: audioDurationMs,
                inputBytes: inputBytes,
                wasPreloaded: wasPreloaded,
                fileCheckMs: trace.durationMs(for: "file_check"),
                modelCheckMs: trace.durationMs(for: "model_check"),
                modelLoadMs: trace.durationMs(for: "model_load"),
                audioLoadMs: trace.durationMs(for: "audio_load"),
                audioPrepareMs: 0,
                inferenceMs: inferenceMs,
                totalMs: trace.elapsedMs
            )

            log.info("Apple SpeechTranscriber trace complete \(trace.summary)")
            return TranscriptionOutput(
                modelId: modelId,
                text: result.text,
                elapsedMs: metrics.totalMs,
                metrics: metrics,
                words: result.words
            )
        } catch {
            outputTask.cancel()
            throw error
        }
    }

    static func resolveLocaleIdentifier(
        env: [String: String]?,
        processEnv: [String: String] = ProcessInfo.processInfo.environment,
        currentLocale: Locale = .current
    ) -> String {
        let configured = env?["VOX_APPLE_SPEECH_LOCALE"]
            ?? env?["VOX_SPEECH_LOCALE"]
            ?? processEnv["VOX_APPLE_SPEECH_LOCALE"]
            ?? processEnv["VOX_SPEECH_LOCALE"]
        let trimmed = configured?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? currentLocale.identifier : trimmed
    }

    @available(macOS 26.0, *)
    private func makeTranscriber() async throws -> SpeechTranscriber {
        guard SpeechTranscriber.isAvailable else {
            throw unavailableError()
        }
        let requestedLocale = Locale(identifier: localeIdentifier)
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: requestedLocale) else {
            throw NSError(domain: "VoxEngine", code: 5302, userInfo: [
                NSLocalizedDescriptionKey: "Apple SpeechTranscriber does not support locale '\(localeIdentifier)'."
            ])
        }
        return SpeechTranscriber(
            locale: locale,
            preset: .timeIndexedTranscriptionWithAlternatives
        )
    }

    @available(macOS 26.0, *)
    private func ensureAssets(
        for transcriber: SpeechTranscriber,
        modelId: String,
        progress: @escaping @Sendable (ModelProgress) -> Void
    ) async throws {
        let modules: [any SpeechModule] = [transcriber]
        let status = await AssetInventory.status(forModules: modules)
        switch status {
        case .installed:
            progress(ModelProgress(modelId: modelId, progress: 1.0, status: "ready"))
        case .unsupported:
            throw unavailableError()
        case .supported, .downloading:
            progress(ModelProgress(modelId: modelId, progress: 0.1, status: "downloading"))
            guard let request = try await AssetInventory.assetInstallationRequest(supporting: modules) else {
                throw NSError(domain: "VoxEngine", code: 5303, userInfo: [
                    NSLocalizedDescriptionKey: "Apple SpeechTranscriber assets could not be installed."
                ])
            }
            try await request.downloadAndInstall()
            progress(ModelProgress(modelId: modelId, progress: 1.0, status: "ready"))
        @unknown default:
            throw unavailableError()
        }
    }

    @available(macOS 26.0, *)
    private func modelInfo(
        modelId: String,
        transcriber: SpeechTranscriber
    ) async throws -> ASRModelInfo {
        let status = await AssetInventory.status(forModules: [transcriber])
        return ASRModelInfo(
            id: modelId,
            name: "Apple SpeechTranscriber",
            backend: Self.providerID,
            installed: status == .installed,
            preloaded: preloadedModels.contains(modelId),
            available: SpeechTranscriber.isAvailable && status != .unsupported
        )
    }

    @available(macOS 26.0, *)
    private static func collectResults(
        from transcriber: SpeechTranscriber
    ) async throws -> (text: String, words: [VoxCore.WordTiming]) {
        var parts: [String] = []
        var words: [VoxCore.WordTiming] = []

        for try await result in transcriber.results {
            try Task.checkCancellation()
            guard result.isFinal else { continue }
            let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                parts.append(text)
            }

            for run in result.text.runs {
                guard let timeRange = run.audioTimeRange else { continue }
                let word = String(result.text[run.range].characters)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !word.isEmpty else { continue }
                let start = CMTimeGetSeconds(timeRange.start)
                let duration = CMTimeGetSeconds(timeRange.duration)
                guard start.isFinite, duration.isFinite else { continue }
                words.append(VoxCore.WordTiming(
                    word: word,
                    start: start,
                    end: start + max(duration, 0),
                    confidence: Float(run.transcriptionConfidence ?? 0)
                ))
            }
        }

        return (parts.joined(separator: " "), words)
    }

    private func supportedModelIDs() -> [String] {
        let catalogIDs = catalogStore.appleSpeechModelIDs()
        return catalogIDs.isEmpty ? Self.fallbackModelIDs : catalogIDs
    }

    private func validate(modelId: String) throws {
        guard supportedModelIDs().contains(modelId) else {
            throw NSError(domain: "VoxEngine", code: 5304, userInfo: [
                NSLocalizedDescriptionKey: "Unsupported Apple SpeechTranscriber model: \(modelId)"
            ])
        }
    }

    private func unavailableModelInfo(modelId: String) -> ASRModelInfo {
        ASRModelInfo(
            id: modelId,
            name: "Apple SpeechTranscriber",
            backend: Self.providerID,
            installed: false,
            preloaded: false,
            available: false
        )
    }

    private func unavailableError() -> NSError {
        NSError(domain: "VoxEngine", code: 5305, userInfo: [
            NSLocalizedDescriptionKey: "Apple SpeechTranscriber requires macOS 26 or newer on Apple Silicon."
        ])
    }
}
#endif
