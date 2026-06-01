import Foundation
import VoxCore

final class LiveSessionCoordinator: @unchecked Sendable {
    typealias ProgressHandler = @Sendable (_ event: String, _ data: [String: Any]) -> Void
    typealias ReplyHandler = @Sendable (_ result: [String: Any]?, _ error: String?) -> Void

    struct SessionStatus: Sendable {
        let sessionId: String
        let connectionID: String
        let clientId: String
        let modelId: String
        let startedAt: Date
        let state: SessionState

        func dictionaryValue() -> [String: Any] {
            [
                "sessionId": sessionId,
                "connectionId": connectionID,
                "clientId": clientId,
                "modelId": modelId,
                "startedAt": ISO8601DateFormatter().string(from: startedAt),
                "state": state.rawValue
            ]
        }
    }

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
        case busy(active: SessionStatus, requesterClientId: String)

        var errorDescription: String? {
            switch self {
            case .busy(let active, let requesterClientId):
                if active.clientId == requesterClientId {
                    return "live_session_busy: client \(requesterClientId) already owns session \(active.sessionId) in \(active.state.rawValue); cancel the active session and retry"
                }
                return "live_session_busy: session \(active.sessionId) is \(active.state.rawValue) for client \(active.clientId); cancel the active session or wait for it to finish"
            }
        }
    }

    /// Max recording duration before auto-cancel. Prevents mic from being left on indefinitely.
    static let maxRecordingSeconds: TimeInterval = 120
    /// Max startup duration before auto-cancel. Prevents a failed capture start from holding ownership forever.
    static let maxStartingSeconds: TimeInterval = 10

    private let lock = NSLock()
    private var activeSession: Session?
    private var startingTimer: DispatchSourceTimer?
    private var recordingTimer: DispatchSourceTimer?

    func begin(
        connectionID: String,
        clientId: String,
        modelId: String,
        progress: @escaping ProgressHandler,
        reply: @escaping ReplyHandler
    ) throws -> Session {
        lock.lock()
        defer { lock.unlock() }

        if let activeSession {
            throw CoordinatorError.busy(
                active: SessionStatus(
                    sessionId: activeSession.sessionId,
                    connectionID: activeSession.connectionID,
                    clientId: activeSession.clientId,
                    modelId: activeSession.modelId,
                    startedAt: activeSession.startedAt,
                    state: activeSession.state
                ),
                requesterClientId: clientId
            )
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

    func markProcessing(id: String?) -> Session? {
        lock.lock()
        defer { lock.unlock() }

        guard let activeSession else { return nil }
        if let id, activeSession.sessionId != id {
            return nil
        }

        activeSession.state = .processing
        cancelRecordingTimer()
        return activeSession
    }

    func status() -> SessionStatus? {
        lock.lock()
        defer { lock.unlock() }

        guard let activeSession else { return nil }
        return SessionStatus(
            sessionId: activeSession.sessionId,
            connectionID: activeSession.connectionID,
            clientId: activeSession.clientId,
            modelId: activeSession.modelId,
            startedAt: activeSession.startedAt,
            state: activeSession.state
        )
    }

    func finish(id: String?) -> Session? {
        lock.lock()
        defer { lock.unlock() }

        guard let activeSession else { return nil }
        if let id, activeSession.sessionId != id {
            return nil
        }

        self.activeSession = nil
        cancelTimers()
        return activeSession
    }

    func finish(connectionID: String) -> Session? {
        lock.lock()
        defer { lock.unlock() }

        guard let activeSession, activeSession.connectionID == connectionID else {
            return nil
        }

        self.activeSession = nil
        cancelTimers()
        return activeSession
    }

    // MARK: - Session timeouts

    /// Called if a session remains in .starting longer than maxStartingSeconds.
    var onStartingTimeout: ((Session) -> Void)?
    /// Called after session transitions to .recording. Fires onTimeout if recording exceeds max duration.
    var onRecordingTimeout: ((Session) -> Void)?

    func startStartingTimer(timeout: TimeInterval = LiveSessionCoordinator.maxStartingSeconds) {
        cancelStartingTimer()
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + timeout)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let session = self.activeSession
            let didTimeout = session?.state == .starting
            if didTimeout {
                self.activeSession = nil
            }
            self.lock.unlock()
            self.cancelStartingTimer()
            if didTimeout, let session {
                self.onStartingTimeout?(session)
            }
        }
        timer.resume()
        startingTimer = timer
    }

    func startRecordingTimer(timeout: TimeInterval = LiveSessionCoordinator.maxRecordingSeconds) {
        cancelStartingTimer()
        cancelRecordingTimer()
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + timeout)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let session = self.activeSession
            let didTimeout = session?.state == .recording
            if didTimeout {
                self.activeSession = nil
            }
            self.lock.unlock()
            self.cancelRecordingTimer()
            if didTimeout, let session {
                self.onRecordingTimeout?(session)
            }
        }
        timer.resume()
        recordingTimer = timer
    }

    private func cancelTimers() {
        cancelStartingTimer()
        cancelRecordingTimer()
    }

    private func cancelStartingTimer() {
        startingTimer?.cancel()
        startingTimer = nil
    }

    private func cancelRecordingTimer() {
        recordingTimer?.cancel()
        recordingTimer = nil
    }
}
