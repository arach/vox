import Foundation
import VoxBridge

@MainActor
final class BridgeState: ObservableObject {
    @Published var isRunning = false
    @Published var port: UInt16 = 0
    @Published var builtinOrigins: [String] = []
    @Published var userOrigins: [String] = []
    @Published var integrationOrigins: [String] = []
    @Published var originsErrorMessage: String?

    private var allowlist: OriginAllowlist?

    func bind(allowlist: OriginAllowlist) {
        self.allowlist = allowlist
        Task {
            await refreshOrigins()
        }
    }

    func refreshOrigins() async {
        guard let allowlist else { return }
        let snapshot = await allowlist.snapshot()
        builtinOrigins = snapshot.builtinOrigins
        userOrigins = snapshot.userOrigins
        integrationOrigins = snapshot.integrationOrigins
    }

    func addOrigin(_ origin: String) {
        guard let allowlist else { return }

        Task {
            if await allowlist.add(origin) == nil {
                originsErrorMessage = "Enter a valid http:// or https:// origin."
                return
            }

            originsErrorMessage = nil
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
