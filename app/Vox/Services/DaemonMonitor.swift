import Foundation
import VoxCore

/// Monitors whether voxd is running by polling runtime.json and checking the PID.
@MainActor
final class DaemonMonitor: ObservableObject {
    @Published var isRunning = false
    @Published var port: UInt16?
    @Published var pid: Int32?
    @Published var uptime: TimeInterval?
    @Published var modelName: String?
    @Published var modelInstalled: Bool?
    @Published var modelPreloaded: Bool?

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
        let result: (runtime: RuntimeInfo, alive: Bool)?
        do {
            guard let runtime = try RuntimeRegistry.read() else {
                markStopped()
                return
            }
            let alive = kill(runtime.pid, 0) == 0
            result = (runtime, alive)
        } catch {
            markStopped()
            return
        }

        guard let result, result.alive else {
            markStopped()
            return
        }

        isRunning = true
        port = result.runtime.port
        pid = result.runtime.pid
        uptime = Date().timeIntervalSince(result.runtime.startedAt)
    }

    private func markStopped() {
        isRunning = false
        port = nil
        pid = nil
        uptime = nil
    }
}
