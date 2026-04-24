import Foundation
import VoxCore

/// Connects to the voxd WebSocket JSON-RPC daemon and proxies requests.
public actor DaemonProxy {
    private struct PendingRequest {
        let continuation: CheckedContinuation<[String: Any], Error>
        let onProgress: (@Sendable (_ event: String, _ data: [String: Any]) async -> Void)?
    }

    private var webSocket: URLSessionWebSocketTask?
    private let session = URLSession(configuration: .default)
    private var pendingRequests: [String: PendingRequest] = [:]
    private var requestCounter = 0
    private var connected = false

    public init() {}

    public func connect() async throws {
        let runtime = try RuntimeRegistry.read()
        guard let runtime else {
            throw BridgeError.daemonNotRunning
        }
        let host = VoxDefaults.resolvedHost()
        let url = URL(string: "ws://\(host):\(runtime.port)")!
        let task = session.webSocketTask(with: url)
        webSocket = task
        connected = true
        task.resume()
        startReceiving(task)
    }

    public func disconnect() {
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        connected = false
        let pending = pendingRequests
        pendingRequests.removeAll()
        for (_, request) in pending {
            request.continuation.resume(throwing: BridgeError.disconnected)
        }
    }

    public var isConnected: Bool {
        connected
    }

    public func call(_ method: String, params: [String: Any]? = nil) async throws -> sending [String: Any] {
        try await sendRequest(method, params: params, onProgress: nil)
    }

    public func callStreaming(
        _ method: String,
        params: [String: Any]? = nil,
        onProgress: @escaping @Sendable (_ event: String, _ data: [String: Any]) async -> Void
    ) async throws -> sending [String: Any] {
        try await sendRequest(method, params: params, onProgress: onProgress)
    }

    private func sendRequest(
        _ method: String,
        params: [String: Any]? = nil,
        onProgress: (@Sendable (_ event: String, _ data: [String: Any]) async -> Void)?
    ) async throws -> sending [String: Any] {
        guard let ws = webSocket else {
            throw BridgeError.daemonNotRunning
        }
        requestCounter += 1
        let id = "bridge-\(requestCounter)"

        var message: [String: Any] = ["id": id, "method": method]
        if let params {
            message["params"] = params
        }

        let data = try JSONSerialization.data(withJSONObject: message)
        let text = String(data: data, encoding: .utf8)!
        try await ws.send(.string(text))

        return try await withCheckedThrowingContinuation { continuation in
            pendingRequests[id] = PendingRequest(continuation: continuation, onProgress: onProgress)
        }
    }

    private func startReceiving(_ ws: URLSessionWebSocketTask) {
        ws.receive { [weak self] result in
            guard let self else { return }
            Task {
                switch result {
                case .success(let message):
                    await self.handleMessage(message)
                    await self.startReceiving(ws)
                case .failure:
                    await self.disconnect()
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) async {
        let text: String
        switch message {
        case .string(let s): text = s
        case .data(let d): text = String(data: d, encoding: .utf8) ?? ""
        @unknown default: return
        }

        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }

        if let id = object["id"] as? String,
           let event = object["event"] as? String {
            let payload = object["data"] as? [String: Any] ?? [:]
            if let onProgress = pendingRequests[id]?.onProgress {
                await onProgress(event, payload)
            }
            return
        }

        guard let id = object["id"] as? String else { return }
        let request = pendingRequests.removeValue(forKey: id)

        if let error = object["error"] as? String {
            request?.continuation.resume(throwing: BridgeError.daemonError(error))
        } else if let result = object["result"] as? [String: Any] {
            request?.continuation.resume(returning: result)
        } else {
            request?.continuation.resume(returning: [:])
        }
    }
}

public enum BridgeError: Error, LocalizedError {
    case daemonNotRunning
    case disconnected
    case daemonError(String)
    case originNotAllowed
    case invalidRequest(String)

    public var errorDescription: String? {
        switch self {
        case .daemonNotRunning: "Vox daemon is not running"
        case .disconnected: "Disconnected from daemon"
        case .daemonError(let msg): "Daemon error: \(msg)"
        case .originNotAllowed: "Origin not in allowlist"
        case .invalidRequest(let msg): "Invalid request: \(msg)"
        }
    }
}
