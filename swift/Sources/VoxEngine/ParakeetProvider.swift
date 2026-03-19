import AVFoundation
import Foundation
import VoxCore

#if canImport(FluidAudio)
import FluidAudio
#endif

public final class ParakeetProvider: @unchecked Sendable, ASRProvider {
    private let log = VoxLog.engine
    private let modelID = "parakeet:v3"
    private let modelName = "Parakeet TDT v3"

#if canImport(FluidAudio)
    private var loadedModels: AsrModels?
    private var manager: AsrManager?
#endif

    public init() {}

    public func models() async -> [ASRModelInfo] {
        [modelInfo(preloaded: isPreloaded())]
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
        let input = try inspectAudioInput(url: url)
        trace.end("\(input.inputBytes) bytes")

        trace.begin("model_check")
        let wasPreloaded = isPreloaded()
        trace.end(wasPreloaded ? "already loaded" : "needs load")

        if !wasPreloaded {
            trace.begin("model_load")
        }
        _ = try await ensureLoaded { _ in }
        if !wasPreloaded {
            trace.end("initialized")
        }

#if canImport(FluidAudio)
        guard let manager else {
            throw NSError(domain: "VoxEngine", code: 4, userInfo: [
                NSLocalizedDescriptionKey: "Parakeet manager is not initialized."
            ])
        }

        trace.begin("audio_prepare")
        let prepared = try ParakeetClipPreparer.ensureMinimumDuration(url: url)
        trace.end(prepared.cleanupURL == nil ? "unchanged" : "padded")
        defer { prepared.cleanup() }

        trace.begin("inference")
        let result = try await manager.transcribe(prepared.url)
        let inferenceMs = trace.end("\(result.text.count) chars")

        let metrics = TranscriptionMetrics(
            traceId: trace.traceId,
            audioDurationMs: input.audioDurationMs,
            inputBytes: input.inputBytes,
            wasPreloaded: wasPreloaded,
            fileCheckMs: trace.durationMs(for: "file_check"),
            modelCheckMs: trace.durationMs(for: "model_check"),
            modelLoadMs: trace.durationMs(for: "model_load"),
            audioLoadMs: input.audioLoadMs,
            audioPrepareMs: trace.durationMs(for: "audio_prepare"),
            inferenceMs: inferenceMs,
            totalMs: trace.elapsedMs
        )

        // Surface word-level timestamps from Parakeet's token timings
        let words: [WordTiming] = (result.tokenTimings ?? []).map { timing in
            WordTiming(
                word: timing.token.trimmingCharacters(in: .whitespaces),
                start: timing.startTime,
                end: timing.endTime,
                confidence: timing.confidence
            )
        }.filter { !$0.word.isEmpty }

        log.info("Trace complete \(trace.summary, privacy: .public)")
        return TranscriptionOutput(modelId: self.modelID, text: result.text, elapsedMs: metrics.totalMs, metrics: metrics, words: words)
#else
        throw NSError(domain: "VoxEngine", code: 5, userInfo: [
            NSLocalizedDescriptionKey: "FluidAudio is unavailable in this build."
        ])
#endif
    }

    private func validate(modelId: String) throws {
        guard modelId == self.modelID else {
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

    private func inspectAudioInput(url: URL) throws -> InputAudioMetadata {
        try validateAudioFile(url: url)

        let inputBytes = ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue) ?? 0

        let startedAt = CFAbsoluteTimeGetCurrent()
        let file = try AVAudioFile(forReading: url)
        let audioLoadMs = Int((CFAbsoluteTimeGetCurrent() - startedAt) * 1000)
        let audioDurationMs = Int((Double(file.length) / file.processingFormat.sampleRate) * 1000)

        return InputAudioMetadata(
            inputBytes: inputBytes,
            audioDurationMs: audioDurationMs,
            audioLoadMs: audioLoadMs
        )
    }

    private func isPreloaded() -> Bool {
#if canImport(FluidAudio)
        return manager != nil
#else
        return false
#endif
    }

    private func ensureLoaded(
        progress: @escaping @Sendable (ModelProgress) -> Void
    ) async throws -> ASRModelInfo {
#if canImport(FluidAudio)
        if let _ = manager {
            progress(ModelProgress(modelId: modelID, progress: 1.0, status: "ready"))
            return modelInfo(preloaded: true)
        }

        progress(ModelProgress(modelId: modelID, progress: 0.05, status: "starting"))
        let loadedModels = try await AsrModels.downloadAndLoad(version: .v3)
        progress(ModelProgress(modelId: modelID, progress: 0.8, status: "downloaded"))

        let manager = AsrManager(config: .init())
        try await manager.initialize(models: loadedModels)
        self.loadedModels = loadedModels
        self.manager = manager
        progress(ModelProgress(modelId: modelID, progress: 1.0, status: "ready"))
        log.info("Parakeet v3 loaded")
        return modelInfo(preloaded: true)
#else
        throw NSError(domain: "VoxEngine", code: 2, userInfo: [
            NSLocalizedDescriptionKey: "FluidAudio is unavailable in this build."
        ])
#endif
    }

    private func modelInfo(preloaded: Bool) -> ASRModelInfo {
        ASRModelInfo(
            id: modelID,
            name: modelName,
            backend: "parakeet",
            installed: isInstalled(),
            preloaded: preloaded,
            available: isBackendAvailable()
        )
    }

    private func isBackendAvailable() -> Bool {
#if canImport(FluidAudio)
        true
#else
        false
#endif
    }

    private func isInstalled() -> Bool {
        let fileManager = FileManager.default
        for directory in candidateModelDirectories() {
            guard fileManager.fileExists(atPath: directory.path) else {
                continue
            }

            if let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: nil) {
                for case let url as URL in enumerator where url.pathExtension == "mlmodelc" {
                    return true
                }
            }
        }

        return false
    }

    private func candidateModelDirectories() -> [URL] {
        let roots: [URL] = [
            RuntimePaths.voxHomeURL().appendingPathComponent("cache", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cache", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        ]

        return roots.map { root in
            root
                .appendingPathComponent("FluidAudio", isDirectory: true)
                .appendingPathComponent("Models", isDirectory: true)
                .appendingPathComponent("parakeet-tdt-0.6b-v3-coreml", isDirectory: true)
        }
    }
}

private struct InputAudioMetadata {
    let inputBytes: Int
    let audioDurationMs: Int
    let audioLoadMs: Int
}

private struct ParakeetClipPreparationResult {
    let url: URL
    let cleanupURL: URL?

    func cleanup() {
        guard let cleanupURL else { return }
        try? FileManager.default.removeItem(at: cleanupURL)
    }
}

private enum ParakeetClipPreparer {
    private static let minimumDuration: TimeInterval = 1.5

    static func ensureMinimumDuration(url: URL) throws -> ParakeetClipPreparationResult {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let duration = Double(file.length) / format.sampleRate
        guard duration < minimumDuration else {
            return ParakeetClipPreparationResult(url: url, cleanupURL: nil)
        }

        guard format.commonFormat == .pcmFormatFloat32 else {
            return ParakeetClipPreparationResult(url: url, cleanupURL: nil)
        }

        let minimumFrames = AVAudioFrameCount((minimumDuration * format.sampleRate).rounded(.up))
        guard
            let readBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: max(AVAudioFrameCount(file.length), 1)),
            let paddedBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: minimumFrames)
        else {
            return ParakeetClipPreparationResult(url: url, cleanupURL: nil)
        }

        try file.read(into: readBuffer)
        let framesRead = min(readBuffer.frameLength, minimumFrames)

        guard
            let sourceChannels = readBuffer.floatChannelData,
            let targetChannels = paddedBuffer.floatChannelData
        else {
            return ParakeetClipPreparationResult(url: url, cleanupURL: nil)
        }

        for channel in 0..<Int(format.channelCount) {
            let target = targetChannels[channel]
            let source = sourceChannels[channel]
            target.update(from: source, count: Int(framesRead))
            let remaining = Int(minimumFrames - framesRead)
            if remaining > 0 {
                target.advanced(by: Int(framesRead)).initialize(repeating: 0, count: remaining)
            }
        }

        paddedBuffer.frameLength = minimumFrames
        let paddedURL = url.deletingPathExtension().appendingPathExtension("parakeet-padded.wav")
        if FileManager.default.fileExists(atPath: paddedURL.path) {
            try FileManager.default.removeItem(at: paddedURL)
        }

        let output = try AVAudioFile(forWriting: paddedURL, settings: file.fileFormat.settings)
        try output.write(from: paddedBuffer)
        return ParakeetClipPreparationResult(url: paddedURL, cleanupURL: paddedURL)
    }
}
