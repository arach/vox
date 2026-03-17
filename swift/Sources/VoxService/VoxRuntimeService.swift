import Foundation
import VoxCore
import VoxEngine

public final class VoxRuntimeService: @unchecked Sendable {
    private let log = VoxLog.service
    private let port: UInt16
    private let bridge: ServiceBridge
    private let engine: EngineManager
    private let warmup: WarmupCoordinator
    private let performance = PerformanceRecorder()
    private let recorder = MicrophoneRecorder()
    private let sessions = LiveSessionCoordinator()
    private let startedAt = Date()

    public init(port: UInt16 = 42137, engine: EngineManager = EngineManager()) {
        self.port = port
        self.bridge = ServiceBridge(port: port, serviceName: "Vox")
        self.engine = engine
        self.warmup = WarmupCoordinator(engine: engine)
    }

    public func start() throws {
        registerHandlers()
        let runtime = RuntimeInfo(
            version: VoxVersion.current,
            serviceName: "Vox",
            port: port,
            pid: getpid(),
            startedAt: startedAt
        )
        try RuntimeRegistry.write(runtime)
        bridge.start()
    }

    public func stop() {
        bridge.stop()
        try? RuntimeRegistry.remove()
    }

    private func registerHandlers() {
        bridge.onClientDisconnected = { [weak self] connectionID in
            guard let self else { return }
            Task {
                await self.handleDisconnect(connectionID: connectionID)
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
                let models = await self.engine.models()
                reply(["models": models.map { $0.dictionaryValue() }], nil)
            }
        }

        bridge.handleStreaming("models.install") { [weak self] params, progress, reply in
            guard let self else { return }
            let modelId = (params?["modelId"] as? String) ?? "parakeet:v3"
            Task {
                do {
                    let model = try await self.engine.install(modelId: modelId) { update in
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
                    let model = try await self.engine.preload(modelId: modelId) { update in
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
                    let output = try await self.engine.transcribe(url: URL(fileURLWithPath: path), modelId: modelId)
                    await self.performance.record(PerformanceSample(
                        clientId: clientId,
                        route: "transcribe.file",
                        modelId: modelId,
                        outcome: "ok",
                        textLength: output.text.count,
                        metrics: output.metrics
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
                    session.progress("session.state", [
                        "sessionId": session.sessionId,
                        "state": SessionState.starting.rawValue,
                        "previous": NSNull()
                    ])
                    _ = try await self.recorder.start()
                    session.state = .recording
                    session.progress("session.state", [
                        "sessionId": session.sessionId,
                        "state": SessionState.recording.rawValue,
                        "previous": SessionState.starting.rawValue
                    ])
                    _ = await self.warmup.start(modelId: modelId, requestedBy: clientId)
                } catch {
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

                    let output = try await self.engine.transcribe(url: audioURL, modelId: session.modelId)
                    _ = self.sessions.finish(id: session.sessionId)
                    await self.performance.record(PerformanceSample(
                        clientId: session.clientId,
                        route: "transcribe.live",
                        modelId: session.modelId,
                        outcome: "ok",
                        textLength: output.text.count,
                        metrics: output.metrics
                    ))

                    session.state = .done
                    session.progress("session.final", [
                        "sessionId": session.sessionId,
                        "text": output.text,
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
                        "text": output.text,
                        "elapsedMs": output.elapsedMs,
                        "metrics": output.metrics.dictionaryValue()
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
    }

    private func makeDoctorReport() async -> DoctorReport {
        let runtimeExists = ((try? RuntimeRegistry.read()) != nil)
        let models = await engine.models()
        let model = models.first
        let checks = [
            DoctorCheck(name: "runtime", status: runtimeExists ? "ok" : "error", detail: runtimeExists ? "runtime.json written" : "runtime.json missing"),
            DoctorCheck(name: "microphone", status: microphoneStatusToLevel(MicrophonePermission.statusString()), detail: MicrophonePermission.statusString()),
            DoctorCheck(name: "backend", status: (model?.available ?? false) ? "ok" : "error", detail: (model?.available ?? false) ? "Parakeet available" : "FluidAudio unavailable"),
            DoctorCheck(name: "model", status: (model?.installed ?? false) ? "ok" : "warning", detail: (model?.installed ?? false) ? "Parakeet model installed" : "Parakeet model not installed")
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
        guard let session = sessions.finish(connectionID: connectionID) else {
            return
        }

        await recorder.cancel()
        session.reply(nil, "session_cancelled:connection_closed")
    }
}
