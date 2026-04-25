import Foundation
import VoxBridge

@MainActor
final class BridgeState: ObservableObject {
    @Published var isRunning = false
    @Published var port: UInt16 = 0
    @Published var statusDetail: String?
    @Published var builtinOrigins: [String] = []
    @Published var userOrigins: [String] = []
    @Published var integrationOrigins: [String] = []
    @Published var draftOrigin = ""
    @Published var originsErrorMessage: String?

    private var allowlist: OriginAllowlist?

    var canAddOrigin: Bool {
        !draftOrigin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func bind(allowlist: OriginAllowlist) {
        self.allowlist = allowlist
        Task {
            await refreshOrigins()
        }
    }

    func clearOriginError() {
        originsErrorMessage = nil
    }

    func refreshOrigins() async {
        guard let allowlist else { return }
        let snapshot = await allowlist.snapshot()
        builtinOrigins = snapshot.builtinOrigins
        userOrigins = snapshot.userOrigins
        integrationOrigins = snapshot.integrationOrigins
    }

    func addDraftOrigin() {
        let raw = draftOrigin
        guard let allowlist else { return }

        Task { @MainActor in
            do {
                _ = try await allowlist.add(raw)
                draftOrigin = ""
                originsErrorMessage = nil
                await refreshOrigins()
            } catch let error as OriginAllowlistError {
                originsErrorMessage = error.errorDescription
            } catch {
                originsErrorMessage = error.localizedDescription
            }
        }
    }

    func addOrigin(_ origin: String) {
        guard let allowlist else { return }

        Task {
            do {
                _ = try await allowlist.add(origin)
                originsErrorMessage = nil
            } catch let error as OriginAllowlistError {
                originsErrorMessage = error.errorDescription
            } catch {
                originsErrorMessage = error.localizedDescription
            }
            await refreshOrigins()
        }
    }

    func removeOrigin(_ origin: String) {
        guard let allowlist else { return }

        Task {
            let removed = await allowlist.remove(origin)
            if !removed {
                originsErrorMessage = "Only origins added in Vox settings can be removed here."
            } else {
                originsErrorMessage = nil
            }
            await refreshOrigins()
        }
    }
}
