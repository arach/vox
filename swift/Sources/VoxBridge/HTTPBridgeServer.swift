import Foundation
import Network
import VoxCore

/// Lightweight HTTP server on localhost for browser-to-daemon communication.
/// Listens on `VoxDefaults.bridgePort` by default and proxies requests to voxd via DaemonProxy.
public final class HTTPBridgeServer: @unchecked Sendable {
    public static let defaultPort: UInt16 = VoxDefaults.bridgePort
    private static let headerDelimiter = Data("\r\n\r\n".utf8)

    private let port: UInt16
    private let queue = DispatchQueue(label: "cc.voxd.bridge.http")
    private var listener: NWListener?
    private let proxy: DaemonProxy
    private let allowlist: OriginAllowlist
    private let jobs = JobStore()
    private let log = VoxLog.service
    private let maxRequestBytes = 25 * 1024 * 1024

    public init(port: UInt16 = HTTPBridgeServer.defaultPort, proxy: DaemonProxy, allowlist: OriginAllowlist) {
        self.port = port
        self.proxy = proxy
        self.allowlist = allowlist
    }

    public func start() {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true

        do {
            listener = try NWListener(using: parameters, on: .init(rawValue: port)!)
        } catch {
            log.error("Failed to create HTTP bridge listener: \(error.localizedDescription)")
            return
        }

        listener?.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.log.info("HTTP bridge listening on http://127.0.0.1:\(self.port)")
            case .failed(let error):
                self.log.error("HTTP bridge failed: \(error.localizedDescription)")
                self.listener?.cancel()
            default:
                break
            }
        }

        listener?.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }

        listener?.start(queue: queue)
    }

    public func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - Connection handling

    private func accept(_ connection: NWConnection) {
        connection.stateUpdateHandler = { state in
            if case .failed = state { connection.cancel() }
        }
        connection.start(queue: queue)
        receiveHTTP(on: connection, buffer: Data())
    }

    private func receiveHTTP(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, error in
            guard let self, error == nil else {
                connection.cancel()
                return
            }

            var requestBuffer = buffer
            if let data {
                requestBuffer.append(data)
            }

            guard requestBuffer.count <= self.maxRequestBytes else {
                self.sendResponse(status: 413, body: ["error": "Request too large"], on: connection)
                return
            }

            switch self.requestReadiness(for: requestBuffer) {
            case .ready:
                self.handleHTTPRequest(requestBuffer, on: connection)
            case .needMoreData:
                self.receiveHTTP(on: connection, buffer: requestBuffer)
            case .invalid(let message, let origin):
                self.sendResponse(status: 400, body: ["error": message], origin: origin, on: connection)
            }
        }
    }

    // MARK: - HTTP parsing and routing

    private func handleHTTPRequest(_ data: Data, on connection: NWConnection) {
        guard let headerRange = data.range(of: Self.headerDelimiter) else {
            sendResponse(status: 400, body: ["error": "Invalid request"], on: connection)
            return
        }

        let headerData = data.subdata(in: data.startIndex..<headerRange.lowerBound)
        guard let rawHeaders = String(data: headerData, encoding: .utf8) else {
            sendResponse(status: 400, body: ["error": "Invalid request headers"], on: connection)
            return
        }

        let lines = rawHeaders.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            sendResponse(status: 400, body: ["error": "Empty request"], on: connection)
            return
        }

        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else {
            sendResponse(status: 400, body: ["error": "Malformed request line"], on: connection)
            return
        }

        let method = String(parts[0])
        let path = String(parts[1])
        let origin = extractHeader("Origin", from: lines)
        let contentType = extractHeader("Content-Type", from: lines)
        let contentLength = parsedContentLength(from: lines) ?? 0
        let bodyEnd = min(data.count, headerRange.upperBound + contentLength)
        let bodyData = data.subdata(in: headerRange.upperBound..<bodyEnd)

        // Parse body for POST requests
        var jsonBody: [String: Any]?
        if method == "POST",
           let contentType,
           contentType.lowercased().contains("application/json"),
           !bodyData.isEmpty {
            jsonBody = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
        }

        // CORS preflight
        if method == "OPTIONS" {
            Task {
                let allowed = if let origin {
                    await allowlist.check(origin)
                } else {
                    false
                }
                sendCORSPreflight(origin: allowed ? origin : nil, allowed: allowed, on: connection)
            }
            return
        }

        // Route
        Task {
            await route(
                method: method,
                path: path,
                origin: origin,
                contentType: contentType,
                body: jsonBody,
                bodyData: bodyData,
                on: connection
            )
        }
    }

    private func route(
        method: String,
        path: String,
        origin: String?,
        contentType: String?,
        body: [String: Any]?,
        bodyData: Data,
        on connection: NWConnection
    ) async {
        // /health is open — no origin check
        if method == "GET" && path == "/health" {
            let daemonRunning = await proxy.isConnected
            sendResponse(status: 200, body: [
                "ok": daemonRunning,
                "service": "vox-companion",
                "version": VoxVersion.current,
                "port": Int(port)
            ], origin: origin, on: connection)
            return
        }

        // All other endpoints require origin check
        if let origin {
            let allowed = await allowlist.check(origin)
            if !allowed {
                sendResponse(status: 403, body: ["error": "Origin not allowed"], origin: origin, on: connection)
                return
            }
        }

        switch (method, path) {
        case ("GET", "/capabilities"):
            await handleCapabilities(origin: origin, on: connection)

        case ("GET", "/live"):
            await handleLiveStatus(origin: origin, on: connection)

        case ("POST", "/live"):
            await handleStartLiveSession(body: body, origin: origin, on: connection)

        case ("POST", "/live/stop"):
            await handleStopLiveSession(body: body, origin: origin, on: connection)

        case ("POST", "/live/cancel"):
            await handleCancelLiveSession(body: body, origin: origin, on: connection)

        case ("GET", "/speak"):
            await handleSpeakStatus(origin: origin, on: connection)

        case ("POST", "/speak"):
            await handleStartSynthesis(body: body, origin: origin, on: connection)

        case ("POST", "/speak/cancel"):
            await handleCancelSynthesis(body: body, origin: origin, on: connection)

        case ("GET", "/voices"):
            await handleVoices(origin: origin, on: connection)

        case ("POST", "/transcribe"):
            await handleTranscribe(bodyData: bodyData, contentType: contentType, origin: origin, on: connection)

        case ("POST", "/jobs"):
            await handleCreateJob(body: body, origin: origin, on: connection)

        case ("GET", _) where path.hasPrefix("/jobs/"):
            let jobId = String(path.dropFirst("/jobs/".count))
            await handleGetJob(jobId: jobId, origin: origin, on: connection)

        default:
            sendResponse(status: 404, body: ["error": "Not found"], origin: origin, on: connection)
        }
    }

    private nonisolated static func providerCredentials(from body: [String: Any]?) -> [String: String]? {
        guard let rawCredentials = body?["credentials"] as? [String: Any] else {
            return nil
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
        return credentials.isEmpty ? nil : credentials
    }

    // MARK: - Endpoint handlers

    private func handleCapabilities(origin: String?, on connection: NWConnection) async {
        do {
            if !(await proxy.isConnected) {
                try await proxy.connect()
            }
            let health = try await proxy.call("health")
            let models = try await proxy.call("models.list")

            sendResponse(status: 200, body: [
                "running": true,
                "version": VoxVersion.current,
                "features": [
                    "alignment": true,
                    "local_asr": true,
                    "local_tts": true,
                    "realtime": true,
                    "streaming_audio": true,
                    "streaming_progress": true
                ],
                "backends": [
                    "parakeet": true,
                    "avspeech": true
                ],
                "daemon": health,
                "models": models["models"] ?? []
            ], origin: origin, on: connection)
        } catch {
            sendResponse(status: 200, body: [
                "running": false,
                "version": VoxVersion.current,
                "features": [
                    "alignment": false,
                    "local_asr": false,
                    "local_tts": false,
                    "realtime": false,
                    "streaming_audio": false,
                    "streaming_progress": false
                ],
                "backends": [:] as [String: Any]
            ], origin: origin, on: connection)
        }
    }

    private func handleLiveStatus(origin: String?, on connection: NWConnection) async {
        do {
            if !(await proxy.isConnected) {
                try await proxy.connect()
            }

            let result = try await proxy.call("transcribe.sessionStatus")
            sendResponse(status: 200, body: [
                "session": result["session"] ?? NSNull()
            ], origin: origin, on: connection)
        } catch {
            sendResponse(
                status: statusCode(for: error),
                body: ["error": error.localizedDescription],
                origin: origin,
                on: connection
            )
        }
    }

    private func handleSpeakStatus(origin: String?, on connection: NWConnection) async {
        do {
            if !(await proxy.isConnected) {
                try await proxy.connect()
            }

            let result = try await proxy.call("synthesize.sessionStatus")
            sendResponse(status: 200, body: [
                "session": result["session"] ?? NSNull()
            ], origin: origin, on: connection)
        } catch {
            sendResponse(
                status: statusCode(for: error),
                body: ["error": error.localizedDescription],
                origin: origin,
                on: connection
            )
        }
    }

    private func handleStartLiveSession(body: [String: Any]?, origin: String?, on connection: NWConnection) async {
        let clientId = (body?["clientId"] as? String) ?? "vox-web"
        var didStartStream = false

        do {
            if !(await proxy.isConnected) {
                try await proxy.connect()
            }

            try await sendStreamingResponseHead(origin: origin, on: connection)
            didStartStream = true

            var params: [String: Any] = [
                "clientId": clientId
            ]
            if let modelId = body?["modelId"] as? String {
                params["modelId"] = modelId
            }

            let result = try await proxy.callStreaming(
                "transcribe.startSession",
                params: params
            ) { [self] event, data in
                await sendStreamingPayload([
                    "event": event,
                    "data": data
                ], on: connection)
            }

            await sendStreamingPayload(["result": result], on: connection)
            await finishStreamingResponse(on: connection)
        } catch {
            if didStartStream {
                await sendStreamingPayload(["error": error.localizedDescription], on: connection)
                await finishStreamingResponse(on: connection)
                return
            }

            sendResponse(
                status: statusCode(for: error),
                body: ["error": error.localizedDescription],
                origin: origin,
                on: connection
            )
        }
    }

    private func handleStartSynthesis(body: [String: Any]?, origin: String?, on connection: NWConnection) async {
        let clientId = (body?["clientId"] as? String) ?? "vox-web"
        let text = (body?["text"] as? String) ?? ""
        let voiceId = body?["voiceId"] as? String
        let format = (body?["format"] as? String) ?? "wav"
        let speed = body?["speed"] as? Double
        let instructions = body?["instructions"] as? String
        var didStartStream = false

        do {
            if !(await proxy.isConnected) {
                try await proxy.connect()
            }

            try await sendStreamingResponseHead(origin: origin, on: connection)
            didStartStream = true

            var params: [String: Any] = [
                "clientId": clientId,
                "text": text,
                "format": format
            ]
            if let modelId = body?["modelId"] as? String {
                params["modelId"] = modelId
            }
            if let voiceId {
                params["voiceId"] = voiceId
            }
            if let speed {
                params["speed"] = speed
            }
            if let instructions {
                params["instructions"] = instructions
            }
            if let credentials = Self.providerCredentials(from: body) {
                params["credentials"] = credentials
            }

            let result = try await proxy.callStreaming(
                "synthesize.startSession",
                params: params
            ) { [self] event, data in
                await sendStreamingPayload([
                    "event": event,
                    "data": data
                ], on: connection)
            }

            await sendStreamingPayload(["result": result], on: connection)
            await finishStreamingResponse(on: connection)
        } catch {
            if didStartStream {
                await sendStreamingPayload(["error": error.localizedDescription], on: connection)
                await finishStreamingResponse(on: connection)
                return
            }

            sendResponse(
                status: statusCode(for: error),
                body: ["error": error.localizedDescription],
                origin: origin,
                on: connection
            )
        }
    }

    private func handleStopLiveSession(body: [String: Any]?, origin: String?, on connection: NWConnection) async {
        do {
            if !(await proxy.isConnected) {
                try await proxy.connect()
            }

            let sessionId = body?["sessionId"] as? String
            let params = sessionId.map { ["sessionId": $0] }
            let result = try await proxy.call("transcribe.stopSession", params: params)
            sendResponse(status: 200, body: result, origin: origin, on: connection)
        } catch {
            sendResponse(
                status: statusCode(for: error),
                body: ["error": error.localizedDescription],
                origin: origin,
                on: connection
            )
        }
    }

    private func handleCancelLiveSession(body: [String: Any]?, origin: String?, on connection: NWConnection) async {
        do {
            if !(await proxy.isConnected) {
                try await proxy.connect()
            }

            let sessionId = body?["sessionId"] as? String
            let params = sessionId.map { ["sessionId": $0] }
            let result = try await proxy.call("transcribe.cancelSession", params: params)
            sendResponse(status: 200, body: result, origin: origin, on: connection)
        } catch {
            sendResponse(
                status: statusCode(for: error),
                body: ["error": error.localizedDescription],
                origin: origin,
                on: connection
            )
        }
    }

    private func handleCancelSynthesis(body: [String: Any]?, origin: String?, on connection: NWConnection) async {
        do {
            if !(await proxy.isConnected) {
                try await proxy.connect()
            }

            let sessionId = body?["sessionId"] as? String
            let params = sessionId.map { ["sessionId": $0] }
            let result = try await proxy.call("synthesize.cancel", params: params)
            sendResponse(status: 200, body: result, origin: origin, on: connection)
        } catch {
            sendResponse(
                status: statusCode(for: error),
                body: ["error": error.localizedDescription],
                origin: origin,
                on: connection
            )
        }
    }

    private func handleVoices(origin: String?, on connection: NWConnection) async {
        do {
            if !(await proxy.isConnected) {
                try await proxy.connect()
            }

            let result = try await proxy.call("synthesize.voices")
            sendResponse(status: 200, body: [
                "voices": result["voices"] ?? []
            ], origin: origin, on: connection)
        } catch {
            sendResponse(
                status: statusCode(for: error),
                body: ["error": error.localizedDescription],
                origin: origin,
                on: connection
            )
        }
    }

    private func handleTranscribe(bodyData: Data, contentType: String?, origin: String?, on connection: NWConnection) async {
        guard let contentType else {
            sendResponse(status: 400, body: ["error": "Missing Content-Type"], origin: origin, on: connection)
            return
        }

        do {
            let formData = try HTTPBridgeCodec.parseMultipartFormData(bodyData, contentType: contentType)
            guard let audio = formData.files["audio"] else {
                throw BridgeError.invalidRequest("Missing audio upload")
            }

            let formatHint = formData.fields["format"]?.lowercased()
            let metadata = parseMetadata(formData.fields["metadata"])
            let clientId = (metadata?["surface"] as? String)
                ?? (metadata?["clientId"] as? String)
                ?? "vox-web"
            let modelId = formData.fields["modelId"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            let preparedFiles = try prepareUploadedAudioFiles(audio: audio, formatHint: formatHint)
            defer {
                for fileURL in preparedFiles.cleanupURLs {
                    try? FileManager.default.removeItem(at: fileURL)
                }
            }

            if !(await proxy.isConnected) {
                try await proxy.connect()
            }

            var params: [String: Any] = [
                "path": preparedFiles.transcriptionURL.path,
                "clientId": clientId
            ]
            if let modelId, !modelId.isEmpty {
                params["modelId"] = modelId
            }

            let result = try await proxy.call("transcribe.file", params: params)

            let metrics = result["metrics"] as? [String: Any]
            let totalMs = (metrics?["totalMs"] as? Int) ?? (result["elapsedMs"] as? Int) ?? 0
            let durationMs = (metrics?["audioDurationMs"] as? Int) ?? totalMs
            let inferenceMs = (metrics?["inferenceMs"] as? Int) ?? totalMs
            let realtimeFactor = durationMs > 0 ? Double(totalMs) / Double(durationMs) : 0

            sendResponse(status: 200, body: [
                "text": result["text"] ?? "",
                "durationMs": durationMs,
                "words": result["words"] ?? [],
                "metrics": [
                    "inferenceMs": inferenceMs,
                    "totalMs": totalMs,
                    "realtimeFactor": realtimeFactor
                ]
            ], origin: origin, on: connection)
        } catch let error as BridgeError {
            let status = switch error {
            case .invalidRequest: 400
            default: 500
            }
            sendResponse(status: status, body: ["error": error.localizedDescription], origin: origin, on: connection)
        } catch {
            sendResponse(status: 500, body: ["error": error.localizedDescription], origin: origin, on: connection)
        }
    }

    private func handleCreateJob(body: [String: Any]?, origin: String?, on connection: NWConnection) async {
        guard let body,
              let type = body["type"] as? String
        else {
            sendResponse(status: 400, body: ["error": "Missing type"], origin: origin, on: connection)
            return
        }

        guard type == "alignment" else {
            sendResponse(status: 400, body: ["error": "Unsupported job type: \(type)"], origin: origin, on: connection)
            return
        }

        let jobId = "job_\(UUID().uuidString.prefix(8).lowercased())"
        let job = Job(id: jobId, type: type, status: .accepted, metadata: body["metadata"] as? [String: Any])
        await jobs.set(job)

        sendResponse(status: 200, body: [
            "jobId": jobId,
            "accepted": true
        ], origin: origin, on: connection)

        // Extract audio URL before crossing isolation boundary
        let audioUrl = (body["source"] as? [String: Any])?["audioUrl"] as? String
        let modelId = body["modelId"] as? String
        let jobCopy = job
        Task { [audioUrl, modelId, jobCopy] in
            await processJob(jobCopy, audioUrl: audioUrl, modelId: modelId)
        }
    }

    private func processJob(_ job: Job, audioUrl: String?, modelId: String?) async {
        var current = job
        current.status = .processing
        await jobs.set(current)

        guard let audioUrl else {
            current.status = .failed
            current.error = "Missing audio source"
            await jobs.set(current)
            return
        }

        do {
            // Download audio to temp file
            let tempDir = FileManager.default.temporaryDirectory
            let tempFile = tempDir.appendingPathComponent("vox-\(job.id).mp3")
            let (data, _) = try await URLSession.shared.data(from: URL(string: audioUrl)!)
            try data.write(to: tempFile)

            // Connect to daemon if needed
            if !(await proxy.isConnected) {
                try await proxy.connect()
            }

            // Transcribe via daemon
            let clientId = (job.metadata?["surface"] as? String)
                ?? (job.metadata?["clientId"] as? String)
                ?? "vox-web"
            var params: [String: Any] = [
                "path": tempFile.path,
                "clientId": clientId
            ]
            if let modelId, !modelId.isEmpty {
                params["modelId"] = modelId
            }
            let result = try await proxy.call("transcribe.file", params: params)

            // Clean up temp file
            try? FileManager.default.removeItem(at: tempFile)

            current.status = .completed
            current.result = [
                "alignment": [
                    "words": result["words"] ?? [],
                    "text": result["text"] ?? "",
                    "durationMs": result["elapsedMs"] ?? 0
                ]
            ]
            await jobs.set(current)
        } catch {
            current.status = .failed
            current.error = error.localizedDescription
            await jobs.set(current)
        }
    }

    private func handleGetJob(jobId: String, origin: String?, on connection: NWConnection) async {
        guard let job = await jobs.get(jobId) else {
            sendResponse(status: 404, body: ["error": "Job not found"], origin: origin, on: connection)
            return
        }

        var body: [String: Any] = [
            "jobId": job.id,
            "type": job.type,
            "status": job.status.rawValue
        ]
        if let result = job.result { body["result"] = result }
        if let error = job.error { body["error"] = error }

        sendResponse(status: 200, body: body, origin: origin, on: connection)
    }

    // MARK: - HTTP response helpers

    private func sendResponse(status: Int, body: [String: Any], origin: String? = nil, on connection: NWConnection) {
        let responseData = HTTPBridgeCodec.responseData(status: status, body: body, origin: origin)
        connection.send(content: responseData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func sendCORSPreflight(origin: String?, allowed: Bool, on connection: NWConnection) {
        guard allowed else {
            let headers = """
            HTTP/1.1 403 Forbidden\r
            Content-Length: 0\r
            Connection: close\r
            \r
            """

            connection.send(content: headers.data(using: .utf8), completion: .contentProcessed { _ in
                connection.cancel()
            })
            return
        }

        var headers = "HTTP/1.1 204 No Content\r\n"
        headers += "Connection: close\r\n"
        if let origin {
            headers += "Access-Control-Allow-Origin: \(origin)\r\n"
            headers += "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n"
            headers += "Access-Control-Allow-Headers: Content-Type\r\n"
            headers += "Access-Control-Max-Age: 86400\r\n"
        }
        headers += "\r\n"

        connection.send(content: headers.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func sendStreamingResponseHead(origin: String?, on connection: NWConnection) async throws {
        try await send(HTTPBridgeCodec.streamingResponseHead(origin: origin), on: connection)
    }

    private func sendStreamingPayload(_ body: [String: Any], on connection: NWConnection) async {
        do {
            try await send(HTTPBridgeCodec.streamingChunkData(body: body), on: connection)
        } catch {
            log.warning("Failed to send streaming bridge payload: \(error.localizedDescription)")
        }
    }

    private func finishStreamingResponse(on connection: NWConnection) async {
        do {
            try await send(HTTPBridgeCodec.streamingEndData(), on: connection)
        } catch {
            log.warning("Failed to finish streaming bridge response: \(error.localizedDescription)")
        }
        connection.cancel()
    }

    private func send(_ data: Data, on connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            })
        }
    }

    private func extractHeader(_ name: String, from lines: [String]) -> String? {
        let prefix = name.lowercased() + ":"
        for line in lines {
            if line.lowercased().hasPrefix(prefix) {
                return line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    private func parsedContentLength(from lines: [String]) -> Int? {
        guard let raw = extractHeader("Content-Length", from: lines) else { return 0 }
        return Int(raw.trimmingCharacters(in: .whitespaces))
    }

    private func requestReadiness(for data: Data) -> RequestReadiness {
        guard let headerRange = data.range(of: Self.headerDelimiter) else {
            return .needMoreData
        }

        let headerData = data.subdata(in: data.startIndex..<headerRange.lowerBound)
        guard let headerText = String(data: headerData, encoding: .utf8) else {
            return .invalid("Invalid request headers", nil)
        }

        let lines = headerText.components(separatedBy: "\r\n")
        let origin = extractHeader("Origin", from: lines)
        guard let contentLength = parsedContentLength(from: lines) else {
            return .invalid("Invalid Content-Length", origin)
        }

        let expectedLength = headerRange.upperBound + contentLength
        return data.count >= expectedLength ? .ready : .needMoreData
    }

    private func parseMetadata(_ raw: String?) -> [String: Any]? {
        guard let raw,
              let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        return object
    }

    private func preferredAudioExtension(formatHint: String?, filename: String?, mimeType: String?) -> String {
        if let mimeType {
            let normalizedMimeType = mimeType.lowercased()
            if normalizedMimeType.contains("webm") { return "webm" }
            if normalizedMimeType.contains("ogg") { return "ogg" }
            if normalizedMimeType.contains("wav") { return "wav" }
            if normalizedMimeType.contains("aac") || normalizedMimeType.contains("mp4") { return "m4a" }
            if normalizedMimeType.contains("mpeg") || normalizedMimeType.contains("mp3") { return "mp3" }
            if normalizedMimeType.contains("opus") { return "opus" }
        }
        if let formatHint, !formatHint.isEmpty {
            return normalizedAudioExtension(formatHint)
        }
        if let filename {
            let pathExtension = URL(fileURLWithPath: filename).pathExtension
            if !pathExtension.isEmpty {
                return normalizedAudioExtension(pathExtension)
            }
        }
        return "wav"
    }

    private func normalizedAudioExtension(_ raw: String) -> String {
        switch raw.lowercased() {
        case "aac", "m4a", "mp4":
            return "m4a"
        case "ogg", "opus":
            return "opus"
        case "mpeg", "mp3":
            return "mp3"
        case "wav":
            return "wav"
        case "webm":
            return "webm"
        default:
            return raw.lowercased()
        }
    }

    private func prepareUploadedAudioFiles(audio: MultipartFile, formatHint: String?) throws -> PreparedAudioFiles {
        let fileExtension = preferredAudioExtension(
            formatHint: formatHint,
            filename: audio.filename,
            mimeType: audio.contentType
        )

        let uploadedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vox-upload-\(UUID().uuidString)")
            .appendingPathExtension(fileExtension)
        try audio.data.write(to: uploadedURL, options: .atomic)

        guard fileExtension == "webm" else {
            return PreparedAudioFiles(transcriptionURL: uploadedURL, cleanupURLs: [uploadedURL])
        }

        let normalizedURL = try normalizeWebMUpload(at: uploadedURL)
        return PreparedAudioFiles(transcriptionURL: normalizedURL, cleanupURLs: [uploadedURL, normalizedURL])
    }

    private func normalizeWebMUpload(at inputURL: URL) throws -> URL {
        guard let ffmpegURL = ffmpegExecutableURL() else {
            throw BridgeError.invalidRequest(
                "WebM uploads require ffmpeg. Install ffmpeg or send Ogg, WAV, M4A, or MP3 audio."
            )
        }

        let outputURL = inputURL.deletingPathExtension().appendingPathExtension("wav")
        let process = Process()
        process.executableURL = ffmpegURL
        process.arguments = [
            "-y",
            "-i", inputURL.path,
            "-ar", "16000",
            "-ac", "1",
            outputURL.path
        ]

        let errorPipe = Pipe()
        process.standardOutput = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let details = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let suffix = details?.isEmpty == false ? " \(details!)" : ""
            throw BridgeError.invalidRequest("Failed to normalize WebM upload.\(suffix)")
        }

        return outputURL
    }

    private func ffmpegExecutableURL() -> URL? {
        let candidates = [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/opt/local/bin/ffmpeg"
        ]

        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }

        return nil
    }

    private func statusCode(for error: Error) -> Int {
        guard let bridgeError = error as? BridgeError else {
            return 500
        }

        switch bridgeError {
        case .invalidRequest:
            return 400
        case .daemonNotRunning, .disconnected:
            return 503
        case .daemonError, .originNotAllowed:
            return 500
        }
    }
}

private enum RequestReadiness {
    case needMoreData
    case ready
    case invalid(String, String?)
}

struct MultipartFormData {
    let fields: [String: String]
    let files: [String: MultipartFile]
}

struct MultipartFile {
    let filename: String?
    let contentType: String?
    let data: Data
}

private struct PreparedAudioFiles {
    let transcriptionURL: URL
    let cleanupURLs: [URL]
}

// MARK: - Job types

struct Job: @unchecked Sendable {
    let id: String
    let type: String
    var status: JobStatus
    var metadata: [String: Any]?
    var result: [String: Any]?
    var error: String?

    init(id: String, type: String, status: JobStatus, metadata: [String: Any]? = nil) {
        self.id = id
        self.type = type
        self.status = status
        self.metadata = metadata
    }
}

enum JobStatus: String, Sendable {
    case accepted
    case processing
    case completed
    case failed
}

actor JobStore {
    private var jobs: [String: Job] = [:]

    func set(_ job: Job) {
        jobs[job.id] = job
    }

    func get(_ id: String) -> Job? {
        jobs[id]
    }
}
