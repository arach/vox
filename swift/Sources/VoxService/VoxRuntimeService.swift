import Foundation
import VoxCore
import VoxEngine

public final class VoxRuntimeService: @unchecked Sendable {
    private let log = VoxLog.service
    private let port: UInt16
    private let bridge: ServiceBridge
    private let asrEngine: EngineManager
    private let annotationEngine: AnnotationManager
    private let ttsEngine: TTSEngineManager
    private let warmup: WarmupCoordinator
    private let performance = PerformanceRecorder()
    private let recorder = MicrophoneRecorder()
    private let sessions = LiveSessionCoordinator()
    private let synthesisSessions = SynthesisSessionCoordinator()
    private let startedAt = Date()
    private let preferencesLoader: @Sendable () -> VoxPreferences
    private let defaultSynthesisModelId: String

    public init(
        port: UInt16 = VoxDefaults.daemonPort,
        bindAddress: String = VoxDefaults.host,
        engine: EngineManager = EngineManager(),
        annotationEngine: AnnotationManager = AnnotationManager(),
        ttsEngine: TTSEngineManager = TTSEngineManager(),
        defaultSynthesisModelId: String = TTSDefaults.modelId,
        preferencesLoader: @escaping @Sendable () -> VoxPreferences = {
            (try? VoxPreferences.load()) ?? VoxPreferences()
        }
    ) {
        self.port = port
        self.bridge = ServiceBridge(port: port, serviceName: "Vox", bindAddress: bindAddress)
        self.asrEngine = engine
        self.annotationEngine = annotationEngine
        self.ttsEngine = ttsEngine
        self.warmup = WarmupCoordinator(asrEngine: engine, ttsEngine: ttsEngine)
        self.preferencesLoader = preferencesLoader
        self.defaultSynthesisModelId = defaultSynthesisModelId
    }

    public func start() throws {
        registerHandlers()
        try bridge.start()
        let runtime = RuntimeInfo(
            version: VoxVersion.current,
            serviceName: "Vox",
            port: port,
            pid: getpid(),
            startedAt: startedAt
        )
        try RuntimeRegistry.write(runtime)
    }

    public func stop() {
        bridge.stop()
        try? RuntimeRegistry.remove()
    }

    func performSynthesizeGenerate(params: [String: Any]?) async throws -> SynthesisOutput {
        let text = (params?["text"] as? String) ?? ""
        let requestedModelId = params?["modelId"] as? String
        let requestedVoiceId = params?["voiceId"] as? String
        let modelId = resolveSynthesisModelId(requestedModelId)
        let voiceId = resolveSynthesisVoiceId(
            requestedVoiceId,
            resolvedModelId: modelId,
            requestedModelId: requestedModelId
        )
        let format = (params?["format"] as? String) ?? TTSDefaults.format
        let speed = params?["speed"] as? Double
        let instructions = params?["instructions"] as? String
        let providerCredentials = providerCredentials(from: params)

        return try await performSynthesizeGenerate(request: SynthesisRequest(
            text: text,
            modelId: modelId,
            voiceId: voiceId,
            format: format,
            speed: speed,
            instructions: instructions,
            providerCredentials: providerCredentials
        ))
    }

    func performSynthesizeVoices(params: [String: Any]?) async throws -> [TTSVoiceInfo] {
        try await performSynthesizeVoices(modelId: params?["modelId"] as? String)
    }

    func performSynthesizeModels() async -> [TTSModelInfo] {
        await ttsEngine.models()
    }

    func performModelsInstall(
        params: [String: Any]?,
        progress: @escaping @Sendable (ModelProgress) -> Void
    ) async throws -> ASRModelInfo {
        let modelId = resolveTranscriptionModelId(params?["modelId"] as? String)
        return try await performModelsInstall(modelId: modelId, progress: progress)
    }

    func performModelsInstall(
        modelId: String,
        progress: @escaping @Sendable (ModelProgress) -> Void
    ) async throws -> ASRModelInfo {
        try await asrEngine.install(modelId: modelId, progress: progress)
    }

    func performModelsPreload(
        params: [String: Any]?,
        progress: @escaping @Sendable (ModelProgress) -> Void
    ) async throws -> ASRModelInfo {
        let modelId = resolveTranscriptionModelId(params?["modelId"] as? String)
        return try await performModelsPreload(modelId: modelId, progress: progress)
    }

    func performModelsPreload(
        modelId: String,
        progress: @escaping @Sendable (ModelProgress) -> Void
    ) async throws -> ASRModelInfo {
        try await asrEngine.preload(modelId: modelId, progress: progress)
    }

    func performWarmupStatus(params: [String: Any]?) async -> WarmupStatus {
        let modelId = resolveTranscriptionModelId(params?["modelId"] as? String)
        let requestedBy = params?["clientId"] as? String
        return await performWarmupStatus(modelId: modelId, requestedBy: requestedBy)
    }

    func performWarmupStatus(modelId: String, requestedBy: String?) async -> WarmupStatus {
        await warmup.status(modelId: modelId, requestedBy: requestedBy)
    }

    func performWarmupStart(params: [String: Any]?) async -> WarmupStatus {
        let modelId = resolveTranscriptionModelId(params?["modelId"] as? String)
        let requestedBy = params?["clientId"] as? String
        return await performWarmupStart(modelId: modelId, requestedBy: requestedBy)
    }

    func performWarmupStart(modelId: String, requestedBy: String?) async -> WarmupStatus {
        await warmup.start(modelId: modelId, requestedBy: requestedBy)
    }

    func performWarmupSchedule(params: [String: Any]?) async -> WarmupStatus {
        let modelId = resolveTranscriptionModelId(params?["modelId"] as? String)
        let requestedBy = params?["clientId"] as? String
        let delayMs = max((params?["delayMs"] as? Int) ?? 0, 0)
        return await performWarmupSchedule(modelId: modelId, delayMs: delayMs, requestedBy: requestedBy)
    }

    func performWarmupSchedule(modelId: String, delayMs: Int, requestedBy: String?) async -> WarmupStatus {
        await warmup.schedule(modelId: modelId, delayMs: delayMs, requestedBy: requestedBy)
    }

    func performTranscribeFile(params: [String: Any]?) async throws -> ASRRouteTranscriptionResult {
        guard let path = params?["path"] as? String else {
            throw NSError(domain: "VoxService", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Missing path"
            ])
        }

        let modelId = resolveTranscriptionModelId(params?["modelId"] as? String)
        let clientId = (params?["clientId"] as? String) ?? "unknown"
        return try await performTranscribeFile(path: path, modelId: modelId, clientId: clientId)
    }

    func performTranscribeFile(path: String, modelId: String, clientId: String) async throws -> ASRRouteTranscriptionResult {
        let output = try await asrEngine.transcribe(url: URL(fileURLWithPath: path), modelId: modelId)
        let sample = PerformanceSample(
            clientId: clientId,
            route: "transcribe.file",
            modelId: modelId,
            outcome: "ok",
            textLength: output.text.count,
            metrics: output.metrics.performanceMetrics
        )
        return ASRRouteTranscriptionResult(output: output, performanceSample: sample)
    }

    func performAnnotateFile(params: [String: Any]?) async throws -> AnnotationRouteResult {
        guard let path = params?["path"] as? String else {
            throw NSError(domain: "VoxService", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Missing path"
            ])
        }

        let modelId = (params?["modelId"] as? String) ?? "speaker-diarization:v1"
        let clientId = (params?["clientId"] as? String) ?? "unknown"
        let text = params?["text"] as? String
        let words = parseAnnotationWords(params?["words"] as? [[String: Any]])

        return try await performAnnotateFile(
            path: path,
            modelId: modelId,
            clientId: clientId,
            text: text,
            words: words
        )
    }

    func performAnnotateFile(
        path: String,
        modelId: String,
        clientId: String,
        text: String?,
        words: [WordTiming]?
    ) async throws -> AnnotationRouteResult {
        let transcription: AnnotationInputTranscription? = {
            guard let text else { return nil }
            return AnnotationInputTranscription(text: text, words: words ?? [])
        }()

        let request = AnnotationRequest(
            url: URL(fileURLWithPath: path),
            modelId: modelId,
            transcription: transcription
        )
        let output = try await annotationEngine.annotate(request: request)
        let sample = PerformanceSample(
            clientId: clientId,
            route: "annotate.file",
            modelId: modelId,
            outcome: "ok",
            textLength: output.text?.count ?? 0,
            metrics: output.metrics.performanceMetrics
        )
        return AnnotationRouteResult(output: output, performanceSample: sample)
    }

    private func parseAnnotationWords(_ rawWords: [[String: Any]]?) -> [WordTiming]? {
        rawWords?.compactMap { entry in
            guard let word = entry["word"] as? String, !word.isEmpty else {
                return nil
            }

            let confidence: Float
            if let floatConfidence = entry["confidence"] as? Float {
                confidence = floatConfidence
            } else if let doubleConfidence = entry["confidence"] as? Double {
                confidence = Float(doubleConfidence)
            } else if let intConfidence = entry["confidence"] as? Int {
                confidence = Float(intConfidence)
            } else {
                confidence = 0
            }

            return WordTiming(
                word: word,
                start: entry["start"] as? Double ?? 0,
                end: entry["end"] as? Double ?? 0,
                confidence: confidence
            )
        }
    }

    private func performSynthesizeGenerate(request: SynthesisRequest) async throws -> SynthesisOutput {
        try await ttsEngine.synthesize(request)
    }

    private func performSynthesizeVoices(modelId: String?) async throws -> [TTSVoiceInfo] {
        try await ttsEngine.voices(modelId: modelId)
    }

    private func currentPreferences() -> VoxPreferences {
        preferencesLoader()
    }

    private func resolveTranscriptionModelId(_ requestedModelId: String?) -> String {
        let normalizedRequestedModelId = normalizePreferenceValue(requestedModelId)
        if let normalizedRequestedModelId {
            return normalizedRequestedModelId
        }

        let preferences = currentPreferences()
        return normalizePreferenceValue(preferences.speech.preferredTranscriptionModelId) ?? "parakeet:v3"
    }

    private func resolveSynthesisModelId(_ requestedModelId: String?) -> String {
        let normalizedRequestedModelId = normalizePreferenceValue(requestedModelId)
        if let normalizedRequestedModelId {
            return normalizedRequestedModelId
        }

        let preferences = currentPreferences()
        return normalizePreferenceValue(preferences.speech.preferredSynthesisModelId) ?? defaultSynthesisModelId
    }

    private func resolveSynthesisVoiceId(
        _ requestedVoiceId: String?,
        resolvedModelId: String,
        requestedModelId: String?
    ) -> String? {
        if let requestedVoiceId = normalizePreferenceValue(requestedVoiceId) {
            return requestedVoiceId
        }

        let preferences = currentPreferences()
        let preferredVoiceId = normalizePreferenceValue(preferences.speech.preferredSynthesisVoiceId)
        guard let preferredVoiceId else {
            return nil
        }

        let preferredModelId = normalizePreferenceValue(preferences.speech.preferredSynthesisModelId) ?? defaultSynthesisModelId
        let normalizedRequestedModelId = normalizePreferenceValue(requestedModelId)

        // Only apply the user-level voice default when the resolved model matches
        // the voice's preferred model. Explicit model overrides keep provider defaults.
        guard resolvedModelId == preferredModelId,
              normalizedRequestedModelId == nil || normalizedRequestedModelId == preferredModelId
        else {
            return nil
        }

        return preferredVoiceId
    }

    private func normalizePreferenceValue(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty
        else {
            return nil
        }
        return trimmed
    }

    private func providerCredentials(from params: [String: Any]?) -> [String: String] {
        guard let rawCredentials = params?["credentials"] as? [String: Any] else {
            return [:]
        }

        var credentials: [String: String] = [:]
        for key in ["OPENAI_API_KEY", "openaiApiKey", "openai_api_key"] {
            if let value = rawCredentials[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    credentials[key] = trimmed
                }
            }
        }
        return credentials
    }

    private func registerHandlers() {
        bridge.onClientDisconnected = { [weak self] connectionID in
            guard let self else { return }
            Task {
                await self.handleDisconnect(connectionID: connectionID)
            }
        }

        sessions.onRecordingTimeout = { [weak self] session in
            guard let self else { return }
            Task {
                await self.recorder.cancel()
                session.state = .cancelled
                self.log.warning("Auto-cancelled live session \(session.sessionId) for client \(session.clientId) — exceeded \(Int(LiveSessionCoordinator.maxRecordingSeconds))s recording limit")
                session.progress("session.state", [
                    "sessionId": session.sessionId,
                    "state": SessionState.cancelled.rawValue,
                    "previous": SessionState.recording.rawValue,
                    "reason": "recording_timeout"
                ])
                session.reply(nil, "session_cancelled:recording_timeout")
            }
        }

        bridge.handle("health") { [weak self] _, reply in
            guard let self else { return }
            reply([
                "service": "Vox",
                "version": VoxVersion.current,
                "port": Int(self.port),
                "pid": Int(getpid()),
                "startedAt": ISO8601DateFormatter().string(from: self.startedAt)
            ], nil)
        }

        bridge.handle("doctor.run") { [weak self] _, reply in
            guard let self else { return }
            Task {
                let report = await self.makeDoctorReport()
                reply(report.dictionaryValue(), nil)
            }
        }

        bridge.handle("models.list") { [weak self] _, reply in
            guard let self else { return }
            Task {
                let models = await self.asrEngine.models()
                reply(["models": models.map { $0.dictionaryValue() }], nil)
            }
        }

        bridge.handleStreaming("models.install") { [weak self] params, progress, reply in
            guard let self else { return }
            let modelId = self.resolveTranscriptionModelId(params?["modelId"] as? String)
            Task {
                do {
                    let model = try await self.performModelsInstall(modelId: modelId) { update in
                        progress("models.progress", update.dictionaryValue())
                    }
                    reply(["model": model.dictionaryValue()], nil)
                } catch {
                    reply(nil, error.localizedDescription)
                }
            }
        }

        bridge.handleStreaming("models.preload") { [weak self] params, progress, reply in
            guard let self else { return }
            let modelId = self.resolveTranscriptionModelId(params?["modelId"] as? String)
            Task {
                do {
                    let model = try await self.performModelsPreload(modelId: modelId) { update in
                        progress("models.progress", update.dictionaryValue())
                    }
                    reply(["model": model.dictionaryValue()], nil)
                } catch {
                    reply(nil, error.localizedDescription)
                }
            }
        }

        bridge.handle("warmup.status") { [weak self] params, reply in
            guard let self else { return }
            let modelId = self.resolveTranscriptionModelId(params?["modelId"] as? String)
            let requestedBy = params?["clientId"] as? String
            Task {
                let status = await self.performWarmupStatus(modelId: modelId, requestedBy: requestedBy)
                reply(["warmup": status.dictionaryValue()], nil)
            }
        }

        bridge.handle("warmup.start") { [weak self] params, reply in
            guard let self else { return }
            let modelId = self.resolveTranscriptionModelId(params?["modelId"] as? String)
            let requestedBy = params?["clientId"] as? String
            Task {
                let status = await self.performWarmupStart(modelId: modelId, requestedBy: requestedBy)
                reply(["warmup": status.dictionaryValue()], nil)
            }
        }

        bridge.handle("warmup.schedule") { [weak self] params, reply in
            guard let self else { return }
            let modelId = self.resolveTranscriptionModelId(params?["modelId"] as? String)
            let requestedBy = params?["clientId"] as? String
            let delayMs = max((params?["delayMs"] as? Int) ?? 0, 0)
            Task {
                let status = await self.performWarmupSchedule(modelId: modelId, delayMs: delayMs, requestedBy: requestedBy)
                reply(["warmup": status.dictionaryValue()], nil)
            }
        }

        bridge.handle("transcribe.file") { [weak self] params, reply in
            guard let self else { return }
            let path = params?["path"] as? String
            let clientId = (params?["clientId"] as? String) ?? "unknown"
            let modelId = self.resolveTranscriptionModelId(params?["modelId"] as? String)
            Task {
                do {
                    guard let path else {
                        throw NSError(domain: "VoxService", code: 1, userInfo: [
                            NSLocalizedDescriptionKey: "Missing path"
                        ])
                    }
                    let result = try await self.performTranscribeFile(path: path, modelId: modelId, clientId: clientId)
                    await self.performance.record(result.performanceSample)
                    reply(result.output.dictionaryValue(), nil)
                } catch {
                    await self.performance.record(PerformanceSample(
                        clientId: clientId,
                        route: "transcribe.file",
                        modelId: modelId,
                        outcome: "error",
                        textLength: 0,
                        error: error.localizedDescription
                    ))
                    reply(nil, error.localizedDescription)
                }
            }
        }

        bridge.handle("annotate.file") { [weak self] params, reply in
            guard let self else { return }
            let path = params?["path"] as? String
            let modelId = (params?["modelId"] as? String) ?? "speaker-diarization:v1"
            let clientId = (params?["clientId"] as? String) ?? "unknown"
            let text = params?["text"] as? String
            let words = self.parseAnnotationWords(params?["words"] as? [[String: Any]])
            Task {
                do {
                    guard let path else {
                        throw NSError(domain: "VoxService", code: 1, userInfo: [
                            NSLocalizedDescriptionKey: "Missing path"
                        ])
                    }
                    let result = try await self.performAnnotateFile(
                        path: path,
                        modelId: modelId,
                        clientId: clientId,
                        text: text,
                        words: words
                    )
                    await self.performance.record(result.performanceSample)
                    reply(result.output.dictionaryValue(), nil)
                } catch {
                    await self.performance.record(PerformanceSample(
                        clientId: clientId,
                        route: "annotate.file",
                        modelId: modelId,
                        outcome: "error",
                        textLength: 0,
                        error: error.localizedDescription
                    ))
                    reply(nil, error.localizedDescription)
                }
            }
        }

        bridge.handle("synthesize.voices") { [weak self] params, reply in
            guard let self else { return }
            let modelId = params?["modelId"] as? String
            Task {
                do {
                    let voices = try await self.performSynthesizeVoices(modelId: modelId)
                    reply([
                        "voices": voices.map { $0.dictionaryValue() }
                    ], nil)
                } catch {
                    reply(nil, error.localizedDescription)
                }
            }
        }

        bridge.handle("synthesize.models") { [weak self] _, reply in
            guard let self else { return }
            Task {
                let models = await self.performSynthesizeModels()
                reply([
                    "models": models.map { $0.dictionaryValue() }
                ], nil)
            }
        }

        bridge.handle("synthesize.generate") { [weak self] params, reply in
            guard let self else { return }
            let requestedModelId = params?["modelId"] as? String
            let modelId = self.resolveSynthesisModelId(requestedModelId)
            let requestedVoiceId = params?["voiceId"] as? String
            let voiceId = self.resolveSynthesisVoiceId(
                requestedVoiceId,
                resolvedModelId: modelId,
                requestedModelId: requestedModelId
            )
            let clientId = (params?["clientId"] as? String) ?? "unknown"
            let text = (params?["text"] as? String) ?? ""
            let format = (params?["format"] as? String) ?? TTSDefaults.format
            let speed = params?["speed"] as? Double
            let instructions = params?["instructions"] as? String
            let providerCredentials = self.providerCredentials(from: params)
            let request = SynthesisRequest(
                text: text,
                modelId: modelId,
                voiceId: voiceId,
                format: format,
                speed: speed,
                instructions: instructions,
                providerCredentials: providerCredentials
            )

            Task {
                do {
                    let output = try await self.performSynthesizeGenerate(request: request)
                    await self.performance.record(PerformanceSample(
                        clientId: clientId,
                        route: "synthesize.generate",
                        modelId: output.modelId,
                        voiceId: output.voiceId,
                        outcome: "ok",
                        textLength: text.count,
                        metrics: output.metrics.performanceMetrics
                    ))
                    reply(output.dictionaryValue(), nil)
                } catch {
                    await self.performance.record(PerformanceSample(
                        clientId: clientId,
                        route: "synthesize.generate",
                        modelId: modelId,
                        voiceId: voiceId,
                        outcome: "error",
                        textLength: text.count,
                        error: error.localizedDescription
                    ))
                    reply(nil, error.localizedDescription)
                }
            }
        }

        bridge.handle("transcribe.sessionStatus") { [weak self] _, reply in
            guard let self else { return }
            if let session = self.sessions.status() {
                reply(["session": session.dictionaryValue()], nil)
            } else {
                reply(["session": NSNull()], nil)
            }
        }

        bridge.handle("synthesize.sessionStatus") { [weak self] _, reply in
            guard let self else { return }
            if let session = self.synthesisSessions.status() {
                reply(["session": session.dictionaryValue()], nil)
            } else {
                reply(["session": NSNull()], nil)
            }
        }

        bridge.handleStreaming("transcribe.startSession") { [weak self] params, progress, reply in
            guard let self else { return }
            let modelId = self.resolveTranscriptionModelId(params?["modelId"] as? String)
            let clientId = (params?["clientId"] as? String) ?? "unknown"
            let connectionID = (params?["_connectionID"] as? String) ?? UUID().uuidString

            Task {
                do {
                    let session = try self.sessions.begin(
                        connectionID: connectionID,
                        clientId: clientId,
                        modelId: modelId,
                        progress: progress,
                        reply: reply
                    )
                    self.log.info("Starting live session \(session.sessionId) for client \(clientId) model \(modelId)")
                    session.progress("session.state", [
                        "sessionId": session.sessionId,
                        "state": SessionState.starting.rawValue,
                        "previous": NSNull()
                    ])
                    _ = try await self.recorder.start()
                    session.state = .recording
                    self.sessions.startRecordingTimer()
                    session.progress("session.state", [
                        "sessionId": session.sessionId,
                        "state": SessionState.recording.rawValue,
                        "previous": SessionState.starting.rawValue
                    ])
                    _ = await self.warmup.start(modelId: modelId, requestedBy: clientId)
                } catch {
                    if let active = self.sessions.status() {
                        self.log.warning("Failed to start live session for client \(clientId): \(error.localizedDescription) active=\(active.sessionId) state=\(active.state.rawValue) owner=\(active.clientId)")
                    } else {
                        self.log.error("Failed to start live session for client \(clientId): \(error.localizedDescription)")
                    }
                    reply(nil, error.localizedDescription)
                }
            }
        }

        bridge.handleStreaming("synthesize.startSession") { [weak self] params, progress, reply in
            guard let self else { return }
            let text = (params?["text"] as? String) ?? ""
            let requestedModelId = params?["modelId"] as? String
            let modelId = self.resolveSynthesisModelId(requestedModelId)
            let voiceId = self.resolveSynthesisVoiceId(
                params?["voiceId"] as? String,
                resolvedModelId: modelId,
                requestedModelId: requestedModelId
            )
            let format = (params?["format"] as? String) ?? TTSDefaults.format
            let speed = params?["speed"] as? Double
            let instructions = params?["instructions"] as? String
            let providerCredentials = self.providerCredentials(from: params)
            let clientId = (params?["clientId"] as? String) ?? "unknown"
            let connectionID = (params?["_connectionID"] as? String) ?? UUID().uuidString

            Task {
                do {
                    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        reply(nil, "Missing text")
                        return
                    }

                    let session = try self.synthesisSessions.begin(
                        connectionID: connectionID,
                        clientId: clientId,
                        modelId: modelId,
                        voiceId: voiceId,
                        textLength: text.count,
                        progress: progress,
                        reply: reply
                    )
                    self.log.info("Starting synthesis session \(session.sessionId) for client \(clientId) model \(modelId) voice \(voiceId ?? "default")")
                    session.progress("session.state", [
                        "sessionId": session.sessionId,
                        "state": SessionState.starting.rawValue,
                        "previous": NSNull()
                    ])

                    session.state = .processing
                    session.progress("session.state", [
                        "sessionId": session.sessionId,
                        "state": SessionState.processing.rawValue,
                        "previous": SessionState.starting.rawValue
                    ])

                    _ = await self.warmup.start(modelId: modelId, requestedBy: clientId)

                    session.task = Task { [weak self] in
                        guard let self else { return }

                        do {
                            let output = try await self.ttsEngine.synthesize(SynthesisRequest(
                                requestId: session.sessionId,
                                text: text,
                                modelId: modelId,
                                voiceId: voiceId,
                                format: format,
                                speed: speed,
                                instructions: instructions,
                                providerCredentials: providerCredentials
                            ))

                            guard !Task.isCancelled else { return }

                            for (index, chunk) in Self.audioChunks(from: output.audioData).enumerated() {
                                guard !Task.isCancelled else { return }
                                session.progress("session.audio", [
                                    "sessionId": session.sessionId,
                                    "sequence": index,
                                    "modelId": output.modelId,
                                    "voiceId": output.voiceId,
                                    "format": output.format,
                                    "contentType": output.contentType,
                                    "audioBase64": chunk.base64EncodedString(),
                                    "audioBytes": chunk.count
                                ])
                            }

                            _ = self.synthesisSessions.finish(id: session.sessionId)
                            await self.performance.record(PerformanceSample(
                                clientId: session.clientId,
                                route: "synthesize.startSession",
                                modelId: output.modelId,
                                voiceId: output.voiceId,
                                outcome: "ok",
                                textLength: session.textLength,
                                metrics: output.metrics.performanceMetrics
                            ))

                            session.state = .done
                            session.progress("session.final", [
                                "sessionId": session.sessionId,
                                "modelId": output.modelId,
                                "voiceId": output.voiceId,
                                "format": output.format,
                                "contentType": output.contentType,
                                "audioBytes": output.audioData.count,
                                "elapsedMs": output.elapsedMs,
                                "metrics": output.metrics.dictionaryValue()
                            ])
                            session.progress("session.state", [
                                "sessionId": session.sessionId,
                                "state": SessionState.done.rawValue,
                                "previous": SessionState.processing.rawValue
                            ])
                            session.reply([
                                "sessionId": session.sessionId,
                                "modelId": output.modelId,
                                "voiceId": output.voiceId,
                                "format": output.format,
                                "contentType": output.contentType,
                                "audioBytes": output.audioData.count,
                                "elapsedMs": output.elapsedMs,
                                "metrics": output.metrics.dictionaryValue()
                            ], nil)
                        } catch is CancellationError {
                            return
                        } catch {
                            await self.performance.record(PerformanceSample(
                                clientId: session.clientId,
                                route: "synthesize.startSession",
                                modelId: session.modelId,
                                voiceId: session.voiceId,
                                outcome: "error",
                                textLength: session.textLength,
                                error: error.localizedDescription
                            ))
                            self.log.error("Failed synthesis session \(session.sessionId) for client \(session.clientId): \(error.localizedDescription)")
                            if let finished = self.synthesisSessions.finish(id: session.sessionId) {
                                finished.state = .error
                                finished.progress("session.state", [
                                    "sessionId": finished.sessionId,
                                    "state": SessionState.error.rawValue,
                                    "previous": SessionState.processing.rawValue
                                ])
                                finished.reply(nil, error.localizedDescription)
                            }
                        }
                    }
                } catch {
                    if let active = self.synthesisSessions.status() {
                        self.log.warning("Failed to start synthesis session for client \(clientId): \(error.localizedDescription) active=\(active.sessionId) state=\(active.state.rawValue) owner=\(active.clientId)")
                    } else {
                        self.log.error("Failed to start synthesis session for client \(clientId): \(error.localizedDescription)")
                    }
                    reply(nil, error.localizedDescription)
                }
            }
        }

        bridge.handle("transcribe.stopSession") { [weak self] params, reply in
            guard let self else { return }
            let requestedID = params?["sessionId"] as? String
            Task {
                do {
                    guard let session = self.sessions.current(id: requestedID) else {
                        reply(nil, "No active live session")
                        return
                    }

                    session.state = .processing
                    session.progress("session.state", [
                        "sessionId": session.sessionId,
                        "state": SessionState.processing.rawValue,
                        "previous": SessionState.recording.rawValue
                    ])

                    let audioURL = try await self.recorder.stop()
                    defer { try? FileManager.default.removeItem(at: audioURL) }

                    let output = try await self.asrEngine.transcribe(url: audioURL, modelId: session.modelId)
                    _ = self.sessions.finish(id: session.sessionId)
                    await self.performance.record(PerformanceSample(
                        clientId: session.clientId,
                        route: "transcribe.live",
                        modelId: session.modelId,
                        outcome: "ok",
                        textLength: output.text.count,
                        metrics: output.metrics.performanceMetrics
                    ))

                    session.state = .done
                    self.log.info("Completed live session \(session.sessionId) for client \(session.clientId) elapsed=\(output.elapsedMs)ms textLength=\(output.text.count)")
                    session.progress("session.final", [
                        "sessionId": session.sessionId,
                        "text": output.text,
                        "elapsedMs": output.elapsedMs,
                        "metrics": output.metrics.dictionaryValue(),
                        "words": output.words.map { $0.dictionaryValue() }
                    ])
                    session.progress("session.state", [
                        "sessionId": session.sessionId,
                        "state": SessionState.done.rawValue,
                        "previous": SessionState.processing.rawValue
                    ])
                    session.reply([
                        "sessionId": session.sessionId,
                        "text": output.text,
                        "elapsedMs": output.elapsedMs,
                        "metrics": output.metrics.dictionaryValue(),
                        "words": output.words.map { $0.dictionaryValue() }
                    ], nil)

                    reply(["stopped": true, "sessionId": session.sessionId], nil)
                } catch {
                    if let session = self.sessions.current(id: requestedID) {
                        await self.performance.record(PerformanceSample(
                            clientId: session.clientId,
                            route: "transcribe.live",
                            modelId: session.modelId,
                            outcome: "error",
                            textLength: 0,
                            error: error.localizedDescription
                        ))
                    }
                    self.log.error("Failed to stop live session \(requestedID ?? "current"): \(error.localizedDescription)")
                    if let session = self.sessions.finish(id: requestedID) {
                        session.reply(nil, error.localizedDescription)
                    }
                    reply(nil, error.localizedDescription)
                }
            }
        }

        bridge.handle("transcribe.cancelSession") { [weak self] params, reply in
            guard let self else { return }
            let requestedID = params?["sessionId"] as? String
            Task {
                guard let session = self.sessions.finish(id: requestedID) else {
                    reply(nil, "No active live session")
                    return
                }

                await self.recorder.cancel()
                session.state = .cancelled
                self.log.warning("Cancelled live session \(session.sessionId) for client \(session.clientId)")
                session.progress("session.state", [
                    "sessionId": session.sessionId,
                    "state": SessionState.cancelled.rawValue,
                    "previous": SessionState.recording.rawValue
                ])
                session.reply([
                    "cancelled": true,
                    "sessionId": session.sessionId
                ], nil)
                reply([
                    "cancelled": true,
                    "sessionId": session.sessionId
                ], nil)
            }
        }

        bridge.handle("synthesize.cancel") { [weak self] params, reply in
            guard let self else { return }
            let requestedID = params?["sessionId"] as? String
            Task {
                guard let session = self.synthesisSessions.finish(id: requestedID) else {
                    reply(nil, "No active synthesis session")
                    return
                }

                session.task?.cancel()
                session.task = nil
                session.state = .cancelled
                await self.performance.record(PerformanceSample(
                    clientId: session.clientId,
                    route: "synthesize.startSession",
                    modelId: session.modelId,
                    voiceId: session.voiceId,
                    outcome: "cancelled",
                    textLength: session.textLength
                ))
                self.log.warning("Cancelled synthesis session \(session.sessionId) for client \(session.clientId)")
                session.progress("session.state", [
                    "sessionId": session.sessionId,
                    "state": SessionState.cancelled.rawValue,
                    "previous": SessionState.processing.rawValue
                ])
                session.reply([
                    "cancelled": true,
                    "sessionId": session.sessionId
                ], nil)
                reply([
                    "cancelled": true,
                    "sessionId": session.sessionId
                ], nil)
            }
        }
    }

    private func makeDoctorReport() async -> DoctorReport {
        let runtimeExists = ((try? RuntimeRegistry.read()) != nil)
        let asrModels = await asrEngine.models()
        let asrModel = asrModels.first
        let ttsModels = await ttsEngine.models()
        let ttsModel = ttsModels.first
        let checks = [
            DoctorCheck(name: "runtime", status: runtimeExists ? "ok" : "error", detail: runtimeExists ? "runtime.json written" : "runtime.json missing"),
            DoctorCheck(name: "microphone", status: microphoneStatusToLevel(MicrophonePermission.statusString()), detail: MicrophonePermission.statusString()),
            DoctorCheck(name: "backend", status: (asrModel?.available ?? false) ? "ok" : "error", detail: (asrModel?.available ?? false) ? "Parakeet available" : "Parakeet unavailable"),
            DoctorCheck(name: "model", status: (asrModel?.installed ?? false) ? "ok" : "warning", detail: (asrModel?.installed ?? false) ? "Parakeet model installed" : "Parakeet model not installed"),
            DoctorCheck(name: "synthesis", status: (ttsModel?.available ?? false) ? "ok" : "warning", detail: (ttsModel?.available ?? false) ? "\(ttsModel?.name ?? "TTS") available" : "Speech synthesis unavailable")
        ]

        return DoctorReport(ready: checks.allSatisfy { $0.status != "error" }, checks: checks)
    }

    private func microphoneStatusToLevel(_ status: String) -> String {
        switch status {
        case "authorized":
            return "ok"
        case "not_determined":
            return "warning"
        default:
            return "error"
        }
    }

    private func handleDisconnect(connectionID: String) async {
        if let session = sessions.finish(connectionID: connectionID) {
            await recorder.cancel()
            log.warning("Connection \(connectionID) closed, cancelled live session \(session.sessionId) for client \(session.clientId)")
            session.reply(nil, "session_cancelled:connection_closed")
            return
        }

        if let session = synthesisSessions.finish(connectionID: connectionID) {
            session.task?.cancel()
            session.task = nil
            await performance.record(PerformanceSample(
                clientId: session.clientId,
                route: "synthesize.startSession",
                modelId: session.modelId,
                voiceId: session.voiceId,
                outcome: "cancelled",
                textLength: session.textLength,
                error: "session_cancelled:connection_closed"
            ))
            log.warning("Connection \(connectionID) closed, cancelled synthesis session \(session.sessionId) for client \(session.clientId)")
            session.reply(nil, "session_cancelled:connection_closed")
        }
    }

    private static func audioChunks(from data: Data, chunkSize: Int = 24 * 1024) -> [Data] {
        guard !data.isEmpty else { return [] }

        var chunks: [Data] = []
        var index = 0
        while index < data.count {
            let upperBound = min(index + chunkSize, data.count)
            chunks.append(data.subdata(in: index..<upperBound))
            index = upperBound
        }
        return chunks
    }
}

struct ASRRouteTranscriptionResult: Sendable {
    let output: TranscriptionOutput
    let performanceSample: PerformanceSample
}

struct AnnotationRouteResult: Sendable {
    let output: AnnotationOutput
    let performanceSample: PerformanceSample
}
