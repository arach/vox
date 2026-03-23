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
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private var handlers: [String: Handler] = [:]
    private var streamingHandlers: [String: StreamingHandler] = [:]

    public init(port: UInt16, serviceName: String, bindAddress: String = "127.0.0.1") {
        self.port = port
        self.bindAddress = bindAddress
        self.serviceName = serviceName
        self.queue = DispatchQueue(label: "dev.vox.bridge.\(serviceName.lowercased())")
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
            return
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
        queue.async {
            self.connections.append(connection)
        }

        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.receive(on: connection)
            case .failed, .cancelled:
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
            self.connections.removeAll { $0 === connection }
            self.onClientDisconnected?(connectionID)
        }
    }

    private func receive(on connection: NWConnection) {
        connection.receiveMessage { [weak self] content, _, _, error in
            guard let self else { return }
            if let error {
                self.log.warning("Receive error: \(error.localizedDescription)")
                connection.cancel()
                return
            }

            if let content, let text = String(data: content, encoding: .utf8) {
                self.handleMessage(text, on: connection)
            }

            self.receive(on: connection)
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
        params["_connectionID"] = "\(ObjectIdentifier(connection).hashValue)"

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
                    guard let self, let connection else { return }
                    if let error {
                        self.sendError(id: id, message: error, on: connection)
                    } else {
                        self.sendResult(id: id, result: result ?? [:], on: connection)
                    }
                }
            )
            return
        }

        if let handler {
            handler(params) { [weak self, weak connection] result, error in
                guard let self, let connection else { return }
                if let error {
                    self.sendError(id: id, message: error, on: connection)
                } else {
                    self.sendResult(id: id, result: result ?? [:], on: connection)
                }
            }
            return
        }

        sendError(id: id, message: "Unknown method: \(method)", on: connection)
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
}
