import Foundation
import VoxCore

/// Connects to the voxd WebSocket JSON-RPC daemon and proxies requests.
public actor DaemonProxy {
    private var webSocket: URLSessionWebSocketTask?
    private let session = URLSession(configuration: .default)
    private var pendingRequests: [String: CheckedContinuation<[String: Any], Error>] = [:]
    private var requestCounter = 0
    private var connected = false

    public init() {}

    public func connect() async throws {
        let runtime = try RuntimeRegistry.read()
        guard let runtime else {
            throw BridgeError.daemonNotRunning
        }
        let url = URL(string: "ws://127.0.0.1:\(runtime.port)")!
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
        for (_, continuation) in pending {
            continuation.resume(throwing: BridgeError.disconnected)
        }
    }

    public var isConnected: Bool {
        connected
    }

    public func call(_ method: String, params: [String: Any]? = nil) async throws -> sending [String: Any] {
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
            pendingRequests[id] = continuation
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

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        let text: String
        switch message {
        case .string(let s): text = s
        case .data(let d): text = String(data: d, encoding: .utf8) ?? ""
        @unknown default: return
        }

        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = object["id"] as? String
        else { return }

        let continuation = pendingRequests.removeValue(forKey: id)

        if let error = object["error"] as? String {
            continuation?.resume(throwing: BridgeError.daemonError(error))
        } else if let result = object["result"] as? [String: Any] {
            continuation?.resume(returning: result)
        } else {
            continuation?.resume(returning: [:])
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
