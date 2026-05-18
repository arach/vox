import Foundation
import VoxBridge
import VoxCore

@MainActor
final class RuntimeDoctorState: ObservableObject {
    @Published private(set) var report: DoctorReport?
    @Published private(set) var isRefreshing = false
    @Published private(set) var statusMessage = "Run Doctor to inspect daemon, microphone, ASR, and synthesis readiness."

    private let proxy = DaemonProxy()

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            if !(await proxy.isConnected) {
                try await proxy.connect()
            }
            defer {
                Task {
                    await proxy.disconnect()
                }
            }

            let result = try await proxy.call("doctor.run")
            report = parseDoctorReport(result)
            statusMessage = report?.ready == true
                ? "Doctor reports Vox is ready."
                : "Doctor found warnings or errors."
        } catch {
            report = nil
            statusMessage = error.localizedDescription
        }
    }

    private func parseDoctorReport(_ result: [String: Any]) -> DoctorReport {
        let checks = (result["checks"] as? [[String: Any]] ?? []).compactMap { check -> DoctorCheck? in
            guard let name = check["name"] as? String,
                  let status = check["status"] as? String,
                  let detail = check["detail"] as? String
            else {
                return nil
            }
            return DoctorCheck(name: name, status: status, detail: detail)
        }

        return DoctorReport(
            ready: (result["ready"] as? Bool) ?? checks.allSatisfy { $0.status != "error" },
            checks: checks
        )
    }
}
