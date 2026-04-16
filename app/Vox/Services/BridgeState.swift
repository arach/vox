import Foundation
import VoxBridge

@MainActor
final class BridgeState: ObservableObject {
    @Published var isRunning = false
    @Published var port: UInt16 = 0
    @Published var allowedOrigins: [String] = []
    @Published var draftOrigin = ""
    @Published var originError: String?

    private var allowlist: OriginAllowlist?

    var canAddOrigin: Bool {
        !draftOrigin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func attachAllowlist(_ allowlist: OriginAllowlist) {
        self.allowlist = allowlist
        Task { @MainActor in
            await reloadAllowedOrigins()
        }
    }

    func clearOriginError() {
        originError = nil
    }

    func addDraftOrigin() {
        let raw = draftOrigin
        guard let allowlist else { return }

        Task { @MainActor in
            do {
                _ = try await allowlist.add(raw)
                draftOrigin = ""
                originError = nil
                await reloadAllowedOrigins()
            } catch let error as OriginAllowlistError {
                originError = error.errorDescription
            } catch {
                originError = error.localizedDescription
            }
        }
    }

    func removeOrigin(_ origin: String) {
        guard let allowlist else { return }
        Task { @MainActor in
            await allowlist.remove(origin)
            await reloadAllowedOrigins()
        }
    }

    func reloadAllowedOrigins() async {
        guard let allowlist else {
            allowedOrigins = []
            return
        }

        allowedOrigins = await allowlist.list()
    }
}
