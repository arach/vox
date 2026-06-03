import Foundation
import Network
import VoxCore

private final class StartupGate: @unchecked Sendable {
    private let lock = NSLock()
    private let signal = DispatchSemaphore(value: 0)
    private var resolved = false
    private var startupError: Error?

    func markReady() {
        lock.lock()
        defer { lock.unlock() }
        guard !resolved else { return }
        resolved = true
        signal.signal()
    }

    func markFailed(_ error: Error) {
        lock.lock()
        defer { lock.unlock() }
        startupError = error
        guard !resolved else { return }
        resolved = true
        signal.signal()
    }

    func wait(timeout: DispatchTime) throws {
        switch signal.wait(timeout: timeout) {
        case .success:
            if let startupError {
                throw startupError
            }
        case .timedOut:
            throw NSError(domain: "VoxService", code: 1001, userInfo: [
                NSLocalizedDescriptionKey: "Timed out waiting for ServiceBridge to start."
            ])
        }
    }
}

public final class ServiceBridge: @unchecked Sendable {
    public typealias Handler = (
        _ params: [String: Any]?,
        _ reply: @escaping @Sendable (_ result: [String: Any]?, _ error: String?) -> Void
    ) -> Void

    public typealias StreamingHandler = (
        _ params: [String: Any]?,
        _ progress: @escaping @Sendable (_ event: String, _ data: [String: Any]) -> Void,
        _ reply: @escaping @Sendable (_ result: [String: Any]?, _ error: String?) -> Void
    ) -> Void

    public var onClientDisconnected: ((_ connectionID: String) -> Void)?

    private let log = VoxLog.service
    private let port: UInt16
    private let bindAddress: String
    private let serviceName: String
    private let authToken: String?
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private var handlers: [String: Handler] = [:]
    private var streamingHandlers: [String: StreamingHandler] = [:]

    public init(
        port: UInt16,
        serviceName: String,
        bindAddress: String = VoxDefaults.host,
        authToken: String? = nil
    ) {
        self.port = port
        self.bindAddress = bindAddress
        self.serviceName = serviceName
        self.authToken = authToken?.isEmpty == false ? authToken : nil
        self.queue = DispatchQueue(label: "cc.voxd.bridge.\(serviceName.lowercased())")
    }

    public func handle(_ method: String, _ handler: @escaping Handler) {
        lock.lock()
        handlers[method] = handler
        lock.unlock()
    }

    public func handleStreaming(_ method: String, _ handler: @escaping StreamingHandler) {
        lock.lock()
        streamingHandlers[method] = handler
        lock.unlock()
    }

    public func start() throws {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true

        let wsOptions = NWProtocolWebSocket.Options()
        wsOptions.autoReplyPing = true
        parameters.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)

        do {
            listener = try NWListener(using: parameters, on: .init(rawValue: port)!)
        } catch {
            log.error("Failed to create WebSocket listener: \(error.localizedDescription)")
            throw error
        }

        let startup = StartupGate()

        listener?.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.log.info("ServiceBridge listening on ws://\(self.bindAddress):\(self.port)")
                startup.markReady()
            case .failed(let error):
                self.log.error("Listener failed: \(error.localizedDescription)")
                self.listener?.cancel()
                startup.markFailed(error)
            case .cancelled:
                self.log.info("Listener cancelled")
            default:
                break
            }
        }

        listener?.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }

        listener?.start(queue: queue)
        do {
            try startup.wait(timeout: .now() + 5)
        } catch {
            listener?.cancel()
            listener = nil
            throw error
        }
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        queue.sync {
            for connection in connections {
                connection.cancel()
            }
            connections.removeAll()
        }
    }

    private func accept(_ connection: NWConnection) {
        let connectionID = "\(ObjectIdentifier(connection).hashValue)"
        if Self.isLoopbackHost(bindAddress) && !Self.isLoopbackEndpoint(connection.endpoint) {
            log.warning("Bridge rejected non-loopback connection connectionId=\(connectionID) endpoint=\(String(describing: connection.endpoint))")
            connection.cancel()
            return
        }

        log.info("Bridge accepted connection connectionId=\(connectionID)")
        queue.async {
            self.connections.append(connection)
        }

        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.log.info("Bridge connection ready connectionId=\(connectionID)")
                self.receive(on: connection)
            case .failed(let error):
                if self.isExpectedDisconnect(error) {
                    self.log.info("Bridge connection closed connectionId=\(connectionID) reason=\(error.localizedDescription)")
                } else {
                    self.log.warning("Bridge connection failed connectionId=\(connectionID) error=\(error.localizedDescription)")
                }
                self.remove(connection)
            case .cancelled:
                self.log.info("Bridge connection cancelled connectionId=\(connectionID)")
                self.remove(connection)
            default:
                break
            }
        }

        connection.start(queue: queue)
    }

    private func remove(_ connection: NWConnection) {
        let connectionID = "\(ObjectIdentifier(connection).hashValue)"
        queue.async {
            let previousCount = self.connections.count
            self.connections.removeAll { $0 === connection }
            guard self.connections.count != previousCount else {
                return
            }
            self.log.info("Bridge removed connection connectionId=\(connectionID)")
            self.onClientDisconnected?(connectionID)
        }
    }

    private func receive(on connection: NWConnection) {
        connection.receiveMessage { [weak self] content, _, _, error in
            guard let self else { return }
            if let error {
                let connectionID = "\(ObjectIdentifier(connection).hashValue)"
                if self.isExpectedDisconnect(error) {
                    self.log.info("Bridge receive closed connectionId=\(connectionID) reason=\(error.localizedDescription)")
                } else {
                    self.log.warning("Bridge receive error connectionId=\(connectionID) error=\(error.localizedDescription)")
                }
                connection.cancel()
                return
            }

            if let content, let text = String(data: content, encoding: .utf8) {
                self.handleMessage(text, on: connection)
            }

            self.receive(on: connection)
        }
    }

    private func isExpectedDisconnect(_ error: NWError) -> Bool {
        switch error {
        case .posix(let code):
            return code == .ECANCELED || code == .ECONNRESET || code == .ENOTCONN
        default:
            return false
        }
    }

    private func handleMessage(_ text: String, on connection: NWConnection) {
        guard
            let data = text.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            sendError(id: nil, message: "Invalid JSON", on: connection)
            return
        }

        let id = object["id"] as? String
        guard let method = object["method"] as? String else {
            sendError(id: id, message: "Missing method", on: connection)
            return
        }

        var params = object["params"] as? [String: Any] ?? [:]
        if let authToken, !Self.isAuthorized(object: object, params: params, token: authToken) {
            sendError(id: id, message: "Unauthorized", on: connection)
            return
        }
        params.removeValue(forKey: "authToken")
        params.removeValue(forKey: "_authToken")
        params.removeValue(forKey: "token")

        let connectionID = "\(ObjectIdentifier(connection).hashValue)"
        params["_connectionID"] = connectionID
        if shouldLogRequest(method) {
            log.info("Bridge received request method=\(method) id=\(id ?? "none") connectionId=\(connectionID)")
        }

        lock.lock()
        let streamingHandler = streamingHandlers[method]
        let handler = handlers[method]
        lock.unlock()

        if let streamingHandler {
            streamingHandler(
                params,
                { [weak self, weak connection] event, data in
                    guard let self, let connection else { return }
                    var payload: [String: Any] = ["event": event, "data": data]
                    if let id {
                        payload["id"] = id
                    }
                    self.sendJSON(payload, on: connection)
                },
                { [weak self, weak connection] result, error in
                    guard let self else { return }
                    guard let connection else {
                        self.log.warning("Bridge dropped streaming reply method=\(method) id=\(id ?? "none") connectionId=\(connectionID) reason=connection_released")
                        return
                    }
                    if let error {
                        self.log.error("Bridge sending streaming error method=\(method) id=\(id ?? "none") connectionId=\(connectionID) error=\(error)")
                        self.sendError(id: id, message: error, on: connection)
                    } else {
                        if self.shouldLogRequest(method) {
                            self.log.info("Bridge sending streaming result method=\(method) id=\(id ?? "none") connectionId=\(connectionID)")
                        }
                        self.sendResult(id: id, result: result ?? [:], on: connection)
                    }
                }
            )
            return
        }

        if let handler {
            handler(params) { [weak self, weak connection] result, error in
                guard let self else { return }
                guard let connection else {
                    self.log.warning("Bridge dropped reply method=\(method) id=\(id ?? "none") connectionId=\(connectionID) reason=connection_released")
                    return
                }
                if let error {
                    self.log.error("Bridge sending error method=\(method) id=\(id ?? "none") connectionId=\(connectionID) error=\(error)")
                    self.sendError(id: id, message: error, on: connection)
                } else {
                    if self.shouldLogRequest(method) {
                        self.log.info("Bridge sending result method=\(method) id=\(id ?? "none") connectionId=\(connectionID)")
                    }
                    self.sendResult(id: id, result: result ?? [:], on: connection)
                }
            }
            return
        }

        sendError(id: id, message: "Unknown method: \(method)", on: connection)
    }

    private func shouldLogRequest(_ method: String) -> Bool {
        switch method {
        case "transcribe.sessionStatus", "synthesize.sessionStatus":
            return false
        default:
            return true
        }
    }

    private func sendResult(id: String?, result: [String: Any], on connection: NWConnection) {
        var payload: [String: Any] = ["result": result]
        if let id {
            payload["id"] = id
        }
        sendJSON(payload, on: connection)
    }

    private func sendError(id: String?, message: String, on connection: NWConnection) {
        var payload: [String: Any] = ["error": message]
        if let id {
            payload["id"] = id
        }
        sendJSON(payload, on: connection)
    }

    private func sendJSON(_ object: [String: Any], on connection: NWConnection) {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else {
            return
        }

        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "vox-response", metadata: [metadata])
        connection.send(content: data, contentContext: context, completion: .contentProcessed { _ in })
    }

    private static func isAuthorized(object: [String: Any], params: [String: Any], token: String) -> Bool {
        let candidates = [
            object["authToken"],
            object["token"],
            params["authToken"],
            params["_authToken"],
            params["token"]
        ]
        for candidate in candidates {
            guard let value = candidate as? String else { continue }
            if timingSafeEquals(value, token) {
                return true
            }
        }
        return false
    }

    private static func timingSafeEquals(_ lhs: String, _ rhs: String) -> Bool {
        let left = Array(lhs.utf8)
        let right = Array(rhs.utf8)
        var diff = left.count ^ right.count
        let count = max(left.count, right.count)
        for index in 0..<count {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            diff |= Int(a ^ b)
        }
        return diff == 0
    }

    private static func isLoopbackEndpoint(_ endpoint: NWEndpoint) -> Bool {
        guard case .hostPort(let host, _) = endpoint else {
            return false
        }
        return isLoopbackHost(String(describing: host))
    }

    private static func isLoopbackHost(_ host: String) -> Bool {
        let normalized = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "localhost"
            || normalized == "::1"
            || normalized == "0:0:0:0:0:0:0:1"
            || normalized.hasPrefix("127.")
    }
}
