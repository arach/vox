import Foundation
import VoxCore

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

    private var timer: Timer?

    func start() {
        checkNow()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkNow()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func checkNow() {
        do {
            guard let runtime = try RuntimeRegistry.read() else {
                markStopped()
                return
            }

            guard kill(runtime.pid, 0) == 0 else {
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
        guard state != newState else { return }
        state = newState
    }
}
