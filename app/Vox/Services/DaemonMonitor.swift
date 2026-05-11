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
        var clientId: String
        var modelId: String
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

        var isRecording: Bool {
            liveSession?.state == .recording
        }

        static let stopped = State()

        static func running(runtime: RuntimeInfo, liveSession: LiveSessionState? = nil) -> State {
            State(
                isRunning: true,
                port: runtime.port,
                pid: runtime.pid,
                startedAt: runtime.startedAt,
                liveSession: liveSession
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
    var liveSessionClientId: String? { state.liveSession?.clientId }
    var liveSessionModelId: String? { state.liveSession?.modelId }
    var liveSessionState: SessionState? { state.liveSession?.state }

    private let monitorQueue = DispatchQueue(label: "cc.voxd.daemon-monitor")
    private let proxy = DaemonProxy()
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

            updateState(.running(runtime: runtime, liveSession: state.liveSession))
        } catch {
            markStopped()
        }
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
            await proxy.disconnect()
            return
        }

        do {
            if !(await proxy.isConnected) {
                try await proxy.connect()
            }

            let result = try await proxy.call("transcribe.sessionStatus")
            updateLiveSession(parseLiveSession(result["session"]))
        } catch {
            await proxy.disconnect()
            updateLiveSession(nil)
        }
    }

    private func parseLiveSession(_ rawSession: Any?) -> LiveSessionState? {
        guard let dictionary = rawSession as? [String: Any],
              let clientId = dictionary["clientId"] as? String,
              let modelId = dictionary["modelId"] as? String,
              let rawState = dictionary["state"] as? String,
              let sessionState = SessionState(rawValue: rawState)
        else {
            return nil
        }

        return LiveSessionState(
            clientId: clientId,
            modelId: modelId,
            state: sessionState
        )
    }
}
