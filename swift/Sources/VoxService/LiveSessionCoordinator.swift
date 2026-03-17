import Foundation
import VoxCore

final class LiveSessionCoordinator: @unchecked Sendable {
    typealias ProgressHandler = @Sendable (_ event: String, _ data: [String: Any]) -> Void
    typealias ReplyHandler = @Sendable (_ result: [String: Any]?, _ error: String?) -> Void

    final class Session: @unchecked Sendable {
        let sessionId: String
        let connectionID: String
        let clientId: String
        let modelId: String
        let startedAt: Date
        let progress: ProgressHandler
        let reply: ReplyHandler
        var state: SessionState

        init(
            sessionId: String,
            connectionID: String,
            clientId: String,
            modelId: String,
            startedAt: Date,
            state: SessionState,
            progress: @escaping ProgressHandler,
            reply: @escaping ReplyHandler
        ) {
            self.sessionId = sessionId
            self.connectionID = connectionID
            self.clientId = clientId
            self.modelId = modelId
            self.startedAt = startedAt
            self.state = state
            self.progress = progress
            self.reply = reply
        }
    }

    enum CoordinatorError: LocalizedError {
        case busy

        var errorDescription: String? {
            switch self {
            case .busy:
                return "live_session_busy"
            }
        }
    }

    private let lock = NSLock()
    private var activeSession: Session?

    func begin(
        connectionID: String,
        clientId: String,
        modelId: String,
        progress: @escaping ProgressHandler,
        reply: @escaping ReplyHandler
    ) throws -> Session {
        lock.lock()
        defer { lock.unlock() }

        guard activeSession == nil else {
            throw CoordinatorError.busy
        }

        let session = Session(
            sessionId: UUID().uuidString,
            connectionID: connectionID,
            clientId: clientId,
            modelId: modelId,
            startedAt: Date(),
            state: .starting,
            progress: progress,
            reply: reply
        )
        activeSession = session
        return session
    }

    func current(id: String?) -> Session? {
        lock.lock()
        defer { lock.unlock() }

        guard let activeSession else { return nil }
        guard let id else { return activeSession }
        return activeSession.sessionId == id ? activeSession : nil
    }

    func finish(id: String?) -> Session? {
        lock.lock()
        defer { lock.unlock() }

        guard let activeSession else { return nil }
        if let id, activeSession.sessionId != id {
            return nil
        }

        self.activeSession = nil
        return activeSession
    }

    func finish(connectionID: String) -> Session? {
        lock.lock()
        defer { lock.unlock() }

        guard let activeSession, activeSession.connectionID == connectionID else {
            return nil
        }

        self.activeSession = nil
        return activeSession
    }
}
