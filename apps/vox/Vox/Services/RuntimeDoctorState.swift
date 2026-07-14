import Foundation
import VoxBridge
import VoxCore

@MainActor
final class RuntimeDoctorState: ObservableObject {
    @Published private(set) var report: DoctorReport?
    @Published private(set) var isRefreshing = false
    @Published private(set) var statusMessage = "Run Doctor to inspect daemon, microphone, ASR, and synthesis readiness."

    private let proxy = DaemonProxy()
    private let diagnosticLog = DiagnosticLog.shared

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            statusMessage = "Connecting to the daemon over WebSocket \(voxPortString(VoxDefaults.daemonPort))..."
            diagnosticLog.info("Doctor: connecting to daemon on \(voxPortString(VoxDefaults.daemonPort))")
            if !(await proxy.isConnected) {
                try await proxy.connect()
            }
            defer {
                Task {
                    await proxy.disconnect()
                }
            }

            statusMessage = "Running daemon doctor checks..."
            diagnosticLog.info("Doctor: sending doctor.run")
            let result = try await proxy.call("doctor.run")
            report = parseDoctorReport(result)
            let checkCount = report?.checks.count ?? 0
            diagnosticLog.log(
                "Doctor: completed \(checkCount) checks; ready=\(report?.ready == true)",
                level: report?.ready == true ? .success : .warning
            )
            statusMessage = report?.ready == true
                ? "Doctor reports Vox is ready. Use Show Logs for the request and daemon trace."
                : "Doctor found warnings or errors. Use Show Logs to inspect daemon output."
        } catch {
            report = nil
            diagnosticLog.error("Doctor: failed - \(error.localizedDescription)")
            statusMessage = error.localizedDescription
        }
    }

    func requestMicrophoneAccess() async {
        do {
            statusMessage = "Requesting microphone access from the Vox runtime..."
            if !(await proxy.isConnected) {
                try await proxy.connect()
            }
            _ = try await proxy.call("microphone.requestAccess")
            await refresh()
        } catch {
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
            return DoctorCheck(
                name: name,
                status: status,
                detail: detail,
                remediation: parseDoctorRemediation(check["remediation"])
            )
        }

        return DoctorReport(
            ready: (result["ready"] as? Bool) ?? checks.allSatisfy { $0.status != "error" },
            checks: checks
        )
    }

    private func parseDoctorRemediation(_ raw: Any?) -> DoctorRemediation? {
        guard let remediation = raw as? [String: Any],
              let action = remediation["action"] as? String,
              let label = remediation["label"] as? String,
              let detail = remediation["detail"] as? String
        else {
            return nil
        }
        return DoctorRemediation(action: action, label: label, detail: detail)
    }
}
