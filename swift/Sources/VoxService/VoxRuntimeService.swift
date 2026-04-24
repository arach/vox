import Foundation
import VoxCore
import VoxEngine

public final class VoxRuntimeService: @unchecked Sendable {
    private let log = VoxLog.service
    private let port: UInt16
    private let bridge: ServiceBridge
    private let asrEngine: EngineManager
    private let ttsEngine: TTSEngineManager
    private let warmup: WarmupCoordinator
    private let performance = PerformanceRecorder()
    private let recorder = MicrophoneRecorder()
    private let sessions = LiveSessionCoordinator()
    private let synthesisSessions = SynthesisSessionCoordinator()
    private let startedAt = Date()

    public init(
        port: UInt16 = VoxDefaults.daemonPort,
        bindAddress: String = VoxDefaults.host,
        engine: EngineManager = EngineManager(),
        ttsEngine: TTSEngineManager = TTSEngineManager()
    ) {
        self.port = port
        self.bridge = ServiceBridge(port: port, serviceName: "Vox", bindAddress: bindAddress)
        self.asrEngine = engine
        self.ttsEngine = ttsEngine
        self.warmup = WarmupCoordinator(asrEngine: engine, ttsEngine: ttsEngine)
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
        let modelId = (params?["modelId"] as? String) ?? TTSDefaults.modelId
        let voiceId = params?["voiceId"] as? String
        let format = (params?["format"] as? String) ?? TTSDefaults.format
        let speed = params?["speed"] as? Double
        let instructions = params?["instructions"] as? String

        return try await performSynthesizeGenerate(request: SynthesisRequest(
            text: text,
            modelId: modelId,
            voiceId: voiceId,
            format: format,
            speed: speed,
            instructions: instructions
        ))
    }

    func performSynthesizeVoices(params: [String: Any]?) async throws -> [TTSVoiceInfo] {
        try await performSynthesizeVoices(modelId: params?["modelId"] as? String)
    }

    private func performSynthesizeGenerate(request: SynthesisRequest) async throws -> SynthesisOutput {
        try await ttsEngine.synthesize(request)
    }

    private func performSynthesizeVoices(modelId: String?) async throws -> [TTSVoiceInfo] {
        try await ttsEngine.voices(modelId: modelId)
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
            let modelId = (params?["modelId"] as? String) ?? "parakeet:v3"
            Task {
                do {
                    let model = try await self.asrEngine.install(modelId: modelId) { update in
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
            let modelId = (params?["modelId"] as? String) ?? "parakeet:v3"
            Task {
                do {
                    let model = try await self.asrEngine.preload(modelId: modelId) { update in
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
            let modelId = (params?["modelId"] as? String) ?? "parakeet:v3"
            let requestedBy = params?["clientId"] as? String
            Task {
                let status = await self.warmup.status(modelId: modelId, requestedBy: requestedBy)
                reply(["warmup": status.dictionaryValue()], nil)
            }
        }

        bridge.handle("warmup.start") { [weak self] params, reply in
            guard let self else { return }
            let modelId = (params?["modelId"] as? String) ?? "parakeet:v3"
            let requestedBy = params?["clientId"] as? String
            Task {
                let status = await self.warmup.start(modelId: modelId, requestedBy: requestedBy)
                reply(["warmup": status.dictionaryValue()], nil)
            }
        }

        bridge.handle("warmup.schedule") { [weak self] params, reply in
            guard let self else { return }
            let modelId = (params?["modelId"] as? String) ?? "parakeet:v3"
            let requestedBy = params?["clientId"] as? String
            let delayMs = max((params?["delayMs"] as? Int) ?? 0, 0)
            Task {
                let status = await self.warmup.schedule(modelId: modelId, delayMs: delayMs, requestedBy: requestedBy)
                reply(["warmup": status.dictionaryValue()], nil)
            }
        }

        bridge.handle("transcribe.file") { [weak self] params, reply in
            guard let self else { return }
            let path = params?["path"] as? String
            let modelId = (params?["modelId"] as? String) ?? "parakeet:v3"
            let clientId = (params?["clientId"] as? String) ?? "unknown"
            Task {
                do {
                    guard let path else {
                        reply(nil, "Missing path")
                        return
                    }
                    let output = try await self.asrEngine.transcribe(url: URL(fileURLWithPath: path), modelId: modelId)
                    await self.performance.record(PerformanceSample(
                        clientId: clientId,
                        route: "transcribe.file",
                        modelId: modelId,
                        outcome: "ok",
                        textLength: output.text.count,
                        metrics: output.metrics.performanceMetrics
                    ))
                    reply(output.dictionaryValue(), nil)
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

        bridge.handle("synthesize.generate") { [weak self] params, reply in
            guard let self else { return }
            let modelId = (params?["modelId"] as? String) ?? TTSDefaults.modelId
            let requestedVoiceId = params?["voiceId"] as? String
            let clientId = (params?["clientId"] as? String) ?? "unknown"
            let text = (params?["text"] as? String) ?? ""
            let format = (params?["format"] as? String) ?? TTSDefaults.format
            let speed = params?["speed"] as? Double
            let instructions = params?["instructions"] as? String
            let request = SynthesisRequest(
                text: text,
                modelId: modelId,
                voiceId: requestedVoiceId,
                format: format,
                speed: speed,
                instructions: instructions
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
                        voiceId: requestedVoiceId,
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
            let modelId = (params?["modelId"] as? String) ?? "parakeet:v3"
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
            let modelId = (params?["modelId"] as? String) ?? TTSDefaults.modelId
            let voiceId = params?["voiceId"] as? String
            let format = (params?["format"] as? String) ?? TTSDefaults.format
            let speed = params?["speed"] as? Double
            let instructions = params?["instructions"] as? String
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
                                instructions: instructions
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
            DoctorCheck(name: "backend", status: (asrModel?.available ?? false) ? "ok" : "error", detail: (asrModel?.available ?? false) ? "Parakeet available" : "FluidAudio unavailable"),
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
