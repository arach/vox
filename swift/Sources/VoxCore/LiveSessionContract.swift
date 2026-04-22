import Foundation

public struct LiveSessionOwner: Sendable, Equatable {
    public let sessionId: String
    public let connectionId: String?
    public let clientId: String
    public let originAppId: String?
    public let modelId: String
    public let startedAt: Date
    public let state: SessionState

    public init(
        sessionId: String,
        connectionId: String? = nil,
        clientId: String,
        originAppId: String? = nil,
        modelId: String,
        startedAt: Date,
        state: SessionState
    ) {
        self.sessionId = sessionId
        self.connectionId = connectionId
        self.clientId = clientId
        self.originAppId = originAppId
        self.modelId = modelId
        self.startedAt = startedAt
        self.state = state
    }

    public func dictionaryValue(includeConnectionId: Bool = true) -> [String: Any] {
        var payload: [String: Any] = [
            "sessionId": sessionId,
            "clientId": clientId,
            "modelId": modelId,
            "startedAt": ISO8601DateFormatter().string(from: startedAt),
            "state": state.rawValue
        ]

        if includeConnectionId, let connectionId {
            payload["connectionId"] = connectionId
        }

        if let originAppId {
            payload["originAppId"] = originAppId
        }

        return payload
    }
}

public enum LiveSessionErrorCode: String, Sendable {
    case liveSessionBusy = "live_session_busy"
    case liveSessionNotFound = "live_session_not_found"
    case liveSessionOwnerMismatch = "live_session_owner_mismatch"
    case sessionCancelled = "session_cancelled"
    case recordingTimeout = "recording_timeout"
    case connectionClosed = "connection_closed"
    case microphoneUnavailable = "microphone_unavailable"
    case transcriptionFailed = "transcription_failed"
    case daemonUnavailable = "daemon_unavailable"
    case originNotAllowed = "origin_not_allowed"
    case protocolError = "protocol_error"
}

public struct LiveSessionErrorPayload: Sendable, Equatable {
    public let code: LiveSessionErrorCode
    public let message: String
    public let sessionOwner: LiveSessionOwner?
    public let reason: String?
    public let retryable: Bool?

    public init(
        code: LiveSessionErrorCode,
        message: String,
        sessionOwner: LiveSessionOwner? = nil,
        reason: String? = nil,
        retryable: Bool? = nil
    ) {
        self.code = code
        self.message = message
        self.sessionOwner = sessionOwner
        self.reason = reason
        self.retryable = retryable
    }

    public func dictionaryValue(includeConnectionId: Bool = false) -> [String: Any] {
        var payload: [String: Any] = [
            "code": code.rawValue,
            "message": message
        ]

        if let sessionOwner {
            payload["sessionOwner"] = sessionOwner.dictionaryValue(includeConnectionId: includeConnectionId)
        }

        if let reason {
            payload["reason"] = reason
        }

        if let retryable {
            payload["retryable"] = retryable
        }

        return payload
    }
}
