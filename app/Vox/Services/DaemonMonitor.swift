import Dispatch
import Foundation
import VoxCore
import VoxBridge

#if canImport(Darwin)
import Darwin
#endif

/// Monitors whether voxd is running by polling runtime.json and checking the PID.
@MainActor
final class DaemonMonitor: ObservableObject {
    struct LiveSessionState: Equatable {
        var sessionId: String
        var clientId: String
        var modelId: String
        var startedAt: Date?
        var state: SessionState
    }

    struct SynthesisSessionState: Equatable {
        var sessionId: String
        var clientId: String
        var modelId: String
        var voiceId: String?
        var textLength: Int
        var startedAt: Date?
        var state: SessionState
    }

    struct State: Equatable {
        var isRunning = false
        var port: UInt16?
        var pid: Int32?
        var startedAt: Date?
        var modelName: String?
        var modelInstalled: Bool?
        var modelPreloaded: Bool?
        var liveSession: LiveSessionState?
        var synthesisSession: SynthesisSessionState?

        var isRecording: Bool {
            liveSession?.state == .recording
        }

        var hasLiveSession: Bool {
            liveSession != nil
        }

        var isSpeaking: Bool {
            switch synthesisSession?.state {
            case .starting, .recording, .processing:
                return true
            default:
                return false
            }
        }

        static let stopped = State()

        static func running(
            runtime: RuntimeInfo,
            liveSession: LiveSessionState? = nil,
            synthesisSession: SynthesisSessionState? = nil
        ) -> State {
            State(
                isRunning: true,
                port: runtime.port,
                pid: runtime.pid,
                startedAt: runtime.startedAt,
                liveSession: liveSession,
                synthesisSession: synthesisSession
            )
        }
    }

    @Published private(set) var state = State.stopped

    var isRunning: Bool { state.isRunning }
    var port: UInt16? { state.port }
    var pid: Int32? { state.pid }
    var startedAt: Date? { state.startedAt }
    var modelName: String? { state.modelName }
    var modelInstalled: Bool? { state.modelInstalled }
    var modelPreloaded: Bool? { state.modelPreloaded }
    var isRecording: Bool { state.isRecording }
    var hasLiveSession: Bool { state.hasLiveSession }
    var isSpeaking: Bool { state.isSpeaking }
    var liveSession: LiveSessionState? { state.liveSession }
    var synthesisSession: SynthesisSessionState? { state.synthesisSession }
    var liveSessionClientId: String? { state.liveSession?.clientId }
    var liveSessionModelId: String? { state.liveSession?.modelId }
    var liveSessionState: SessionState? { state.liveSession?.state }

    private let monitorQueue = DispatchQueue(label: "cc.voxd.daemon-monitor")
    private let proxy = DaemonProxy()
    private let log = VoxLog.service
    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let iso8601FormatterSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
    private var processSource: DispatchSourceProcess?
    private var observedPID: Int32?
    private var pendingRefreshTask: Task<Void, Never>?
    private var runtimePollTask: Task<Void, Never>?
    private var liveSessionPollTask: Task<Void, Never>?

    func start() {
        startRuntimePolling()
        startLiveSessionPolling()
        checkNow()
    }

    func stop() {
        pendingRefreshTask?.cancel()
        pendingRefreshTask = nil
        runtimePollTask?.cancel()
        runtimePollTask = nil
        liveSessionPollTask?.cancel()
        liveSessionPollTask = nil

        processSource?.cancel()
        processSource = nil
        observedPID = nil

        Task {
            await proxy.disconnect()
        }
    }

    func checkNow() {
        do {
            guard let runtime = try RuntimeRegistry.read() else {
                markStopped()
                return
            }

            errno = 0
            let processIsReachable = kill(runtime.pid, 0) == 0 || errno == EPERM
            guard processIsReachable else {
                markStopped()
                return
            }

            updateState(.running(
                runtime: runtime,
                liveSession: state.liveSession,
                synthesisSession: state.synthesisSession
            ))
        } catch {
            markStopped()
        }
    }

    func refreshSessionsNow() async {
        await refreshLiveSession()
    }

    /// Cancels the active live transcription session via the daemon and refreshes state.
    /// Returns nil on success, or an error message on failure.
    @discardableResult
    func cancelLiveSession() async -> String? {
        guard let sessionId = state.liveSession?.sessionId else {
            return nil
        }

        do {
            if !(await proxy.isConnected) {
                try await proxy.connect()
            }
            _ = try await proxy.call("transcribe.cancelSession", params: ["sessionId": sessionId])
            log.info("Cancelled live session \(sessionId) from UI")
            await refreshLiveSession()
            return nil
        } catch {
            log.warning("Failed to cancel live session \(sessionId): \(error.localizedDescription)")
            return error.localizedDescription
        }
    }

    /// Cancels the active synthesis session via the daemon and refreshes state.
    /// Returns nil on success, or an error message on failure.
    @discardableResult
    func cancelSynthesis() async -> String? {
        nil
    }

    private func markStopped() {
        updateState(.stopped)
    }

    private func updateState(_ newState: State) {
        reconfigureProcessWatcher(for: newState.isRunning ? newState.pid : nil)

        let mergedState: State
        if newState.isRunning {
            var runningState = newState
            runningState.liveSession = newState.liveSession ?? state.liveSession
            runningState.synthesisSession = newState.synthesisSession ?? state.synthesisSession
            mergedState = runningState
        } else {
            mergedState = newState
        }

        guard state != mergedState else { return }
        state = mergedState
    }

    private func updateLiveSession(_ liveSession: LiveSessionState?) {
        var newState = state
        newState.liveSession = state.isRunning ? liveSession : nil
        guard state != newState else { return }
        state = newState
    }

    private func updateSynthesisSession(_ synthesisSession: SynthesisSessionState?) {
        var newState = state
        newState.synthesisSession = state.isRunning ? synthesisSession : nil
        guard state != newState else { return }
        state = newState
    }

    private func startRuntimePolling() {
        guard runtimePollTask == nil else { return }
        try? RuntimePaths.ensureDirectories()
        runtimePollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self?.checkNow()
            }
        }
    }

    private func reconfigureProcessWatcher(for pid: Int32?) {
        guard observedPID != pid else { return }

        processSource?.cancel()
        processSource = nil
        observedPID = pid

        guard let pid else { return }

        let source = DispatchSource.makeProcessSource(
            identifier: pid,
            eventMask: .exit,
            queue: monitorQueue
        )

        source.setEventHandler { @Sendable [weak self] in
            Task { @MainActor [weak self] in
                self?.scheduleRefresh()
            }
        }

        processSource = source
        source.resume()
    }

    private func scheduleRefresh() {
        pendingRefreshTask?.cancel()
        pendingRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            self?.checkNow()
        }
    }

    private func startLiveSessionPolling() {
        guard liveSessionPollTask == nil else { return }
        liveSessionPollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshLiveSession()
                try? await Task.sleep(for: .milliseconds(600))
            }
        }
    }

    private func refreshLiveSession() async {
        guard isRunning else {
            updateLiveSession(nil)
            updateSynthesisSession(nil)
            await proxy.disconnect()
            return
        }

        do {
            if !(await proxy.isConnected) {
                try await proxy.connect()
            }

            let liveResult = try await proxy.call("transcribe.sessionStatus")
            updateLiveSession(parseLiveSession(liveResult["session"]))
            updateSynthesisSession(nil)
        } catch {
            await proxy.disconnect()
            updateLiveSession(nil)
            updateSynthesisSession(nil)
        }
    }

    private func parseLiveSession(_ rawSession: Any?) -> LiveSessionState? {
        guard let dictionary = rawSession as? [String: Any],
              let sessionId = dictionary["sessionId"] as? String,
              let clientId = dictionary["clientId"] as? String,
              let modelId = dictionary["modelId"] as? String,
              let rawState = dictionary["state"] as? String,
              let sessionState = SessionState(rawValue: rawState)
        else {
            return nil
        }

        return LiveSessionState(
            sessionId: sessionId,
            clientId: clientId,
            modelId: modelId,
            startedAt: Self.parseDate(dictionary["startedAt"]),
            state: sessionState
        )
    }

    private func parseSynthesisSession(_ rawSession: Any?) -> SynthesisSessionState? {
        guard let dictionary = rawSession as? [String: Any],
              let sessionId = dictionary["sessionId"] as? String,
              let clientId = dictionary["clientId"] as? String,
              let modelId = dictionary["modelId"] as? String,
              let rawState = dictionary["state"] as? String,
              let sessionState = SessionState(rawValue: rawState)
        else {
            return nil
        }

        return SynthesisSessionState(
            sessionId: sessionId,
            clientId: clientId,
            modelId: modelId,
            voiceId: dictionary["voiceId"] as? String,
            textLength: (dictionary["textLength"] as? Int) ?? 0,
            startedAt: Self.parseDate(dictionary["startedAt"]),
            state: sessionState
        )
    }

    private static func parseDate(_ raw: Any?) -> Date? {
        guard let value = raw as? String else { return nil }
        return iso8601Formatter.date(from: value) ?? iso8601FormatterSeconds.date(from: value)
    }
}
