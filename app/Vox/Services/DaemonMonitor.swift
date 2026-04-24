import Dispatch
import Foundation
import VoxCore

#if canImport(Darwin)
import Darwin
#endif

/// Monitors whether voxd is running by polling runtime.json and checking the PID.
@MainActor
final class DaemonMonitor: ObservableObject {
    struct State: Equatable {
        var isRunning = false
        var port: UInt16?
        var pid: Int32?
        var startedAt: Date?
        var modelName: String?
        var modelInstalled: Bool?
        var modelPreloaded: Bool?

        static let stopped = State()

        static func running(runtime: RuntimeInfo) -> State {
            State(
                isRunning: true,
                port: runtime.port,
                pid: runtime.pid,
                startedAt: runtime.startedAt
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

    private let monitorQueue = DispatchQueue(label: "dev.vox.daemon-monitor")
    private var runtimeDirectorySource: DispatchSourceFileSystemObject?
    private var runtimeDirectoryFileDescriptor: CInt = -1
    private var processSource: DispatchSourceProcess?
    private var observedPID: Int32?
    private var pendingRefreshTask: Task<Void, Never>?

    func start() {
        guard runtimeDirectorySource == nil else { return }
        startWatchingRuntimeDirectory()
        checkNow()
    }

    func stop() {
        pendingRefreshTask?.cancel()
        pendingRefreshTask = nil

        runtimeDirectorySource?.cancel()
        runtimeDirectorySource = nil
        runtimeDirectoryFileDescriptor = -1

        processSource?.cancel()
        processSource = nil
        observedPID = nil
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

            updateState(.running(runtime: runtime))
        } catch {
            markStopped()
        }
    }

    private func markStopped() {
        updateState(.stopped)
    }

    private func updateState(_ newState: State) {
        reconfigureProcessWatcher(for: newState.isRunning ? newState.pid : nil)

        guard state != newState else { return }
        state = newState
    }

    private func startWatchingRuntimeDirectory() {
        try? RuntimePaths.ensureDirectories()

        let directoryURL = RuntimePaths.runtimeFileURL().deletingLastPathComponent()
        let fileDescriptor = open(directoryURL.path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }

        runtimeDirectoryFileDescriptor = fileDescriptor

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename, .delete, .attrib, .extend, .link, .revoke],
            queue: monitorQueue
        )

        source.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                self?.scheduleRefresh()
            }
        }
        source.setCancelHandler { [fileDescriptor] in
            close(fileDescriptor)
        }

        runtimeDirectorySource = source
        source.resume()
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

        source.setEventHandler { [weak self] in
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
}
