import Foundation
import Network
import VoxCore

/// Lightweight HTTP server on localhost for browser-to-daemon communication.
/// Listens on port 43115 and proxies requests to voxd via DaemonProxy.
public final class HTTPBridgeServer: @unchecked Sendable {
    public static let defaultPort: UInt16 = 43115

    private let port: UInt16
    private let queue = DispatchQueue(label: "dev.vox.bridge.http")
    private var listener: NWListener?
    private let proxy: DaemonProxy
    private let allowlist: OriginAllowlist
    private let jobs = JobStore()
    private let log = VoxLog.service

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
        receiveHTTP(on: connection)
    }

    private func receiveHTTP(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, error in
            guard let self, let data, error == nil else {
                connection.cancel()
                return
            }
            self.handleHTTPRequest(data, on: connection)
        }
    }

    // MARK: - HTTP parsing and routing

    private func handleHTTPRequest(_ data: Data, on connection: NWConnection) {
        guard let raw = String(data: data, encoding: .utf8) else {
            sendResponse(status: 400, body: ["error": "Invalid request"], on: connection)
            return
        }

        let lines = raw.components(separatedBy: "\r\n")
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

        // Parse body for POST requests
        var jsonBody: [String: Any]?
        if method == "POST", let bodyStart = raw.range(of: "\r\n\r\n") {
            let bodyString = String(raw[bodyStart.upperBound...])
            if let bodyData = bodyString.data(using: .utf8) {
                jsonBody = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
            }
        }

        // CORS preflight
        if method == "OPTIONS" {
            sendCORSPreflight(origin: origin, on: connection)
            return
        }

        // Route
        Task {
            await route(method: method, path: path, origin: origin, body: jsonBody, on: connection)
        }
    }

    private func route(method: String, path: String, origin: String?, body: [String: Any]?, on connection: NWConnection) async {
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
                sendResponse(status: 403, body: ["error": "Origin not allowed"], on: connection)
                return
            }
        }

        switch (method, path) {
        case ("GET", "/capabilities"):
            await handleCapabilities(origin: origin, on: connection)

        case ("POST", "/jobs"):
            await handleCreateJob(body: body, origin: origin, on: connection)

        case ("GET", _) where path.hasPrefix("/jobs/"):
            let jobId = String(path.dropFirst("/jobs/".count))
            await handleGetJob(jobId: jobId, origin: origin, on: connection)

        default:
            sendResponse(status: 404, body: ["error": "Not found"], origin: origin, on: connection)
        }
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
                    "streaming_progress": true
                ],
                "backends": [
                    "parakeet": true
                ],
                "daemon": health,
                "models": models["models"] ?? []
            ], origin: origin, on: connection)
        } catch {
            sendResponse(status: 200, body: [
                "running": false,
                "version": VoxVersion.current,
                "features": [:] as [String: Any],
                "backends": [:] as [String: Any]
            ], origin: origin, on: connection)
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
        let jobCopy = job
        Task { [audioUrl, jobCopy] in
            await processJob(jobCopy, audioUrl: audioUrl)
        }
    }

    private func processJob(_ job: Job, audioUrl: String?) async {
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
            let result = try await proxy.call("transcribe.file", params: [
                "path": tempFile.path,
                "modelId": "parakeet:v3"
            ])

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
        let statusText: String = switch status {
        case 200: "OK"
        case 400: "Bad Request"
        case 403: "Forbidden"
        case 404: "Not Found"
        default: "Error"
        }

        let jsonData = (try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])) ?? Data()

        var headers = "HTTP/1.1 \(status) \(statusText)\r\n"
        headers += "Content-Type: application/json\r\n"
        headers += "Content-Length: \(jsonData.count)\r\n"
        headers += "Connection: close\r\n"
        if let origin {
            headers += "Access-Control-Allow-Origin: \(origin)\r\n"
            headers += "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n"
            headers += "Access-Control-Allow-Headers: Content-Type\r\n"
        }
        headers += "\r\n"

        var responseData = headers.data(using: .utf8)!
        responseData.append(jsonData)

        connection.send(content: responseData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func sendCORSPreflight(origin: String?, on connection: NWConnection) {
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

    private func extractHeader(_ name: String, from lines: [String]) -> String? {
        let prefix = name.lowercased() + ":"
        for line in lines {
            if line.lowercased().hasPrefix(prefix) {
                return line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }
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
