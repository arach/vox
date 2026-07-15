import Foundation
import SwiftUI
import VoxBridge

@MainActor
final class OnboardingState: ObservableObject {
    enum TrustState: Equatable {
        case unknown
        case verified
        case unverified(origin: String)
        case noOrigin
    }

    @Published private(set) var context: GettingStartedContext
    @Published private(set) var returnToOrigin: String?
    @Published private(set) var trust: TrustState
    @Published private(set) var requestToken: UUID
    @Published var trustErrorMessage: String?

    private weak var allowlist: OriginAllowlist?
    private weak var bridgeState: BridgeState?

    init() {
        self.context = .welcome
        self.returnToOrigin = nil
        self.trust = .unknown
        self.requestToken = UUID()
    }

    func attach(allowlist: OriginAllowlist, bridgeState: BridgeState) {
        self.allowlist = allowlist
        self.bridgeState = bridgeState
    }

    func presentWelcome() {
        context = .welcome
        returnToOrigin = nil
        trust = .unknown
        trustErrorMessage = nil
        requestToken = UUID()
    }

    func present(
        context: GettingStartedContext,
        returnTo: String?,
        isTrusted: Bool
    ) {
        let normalizedReturn = returnTo?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedReturn = (normalizedReturn?.isEmpty == false) ? normalizedReturn : nil

        self.context = context
        self.returnToOrigin = resolvedReturn
        self.trust = Self.resolveTrust(returnTo: resolvedReturn, isTrusted: isTrusted)
        self.trustErrorMessage = nil
        self.requestToken = UUID()
    }

    func allowReturnOrigin() async {
        guard let allowlist, let returnToOrigin else { return }
        do {
            _ = try await allowlist.add(returnToOrigin)
            trust = .verified
            trustErrorMessage = nil
            await bridgeState?.refreshOrigins()
        } catch let error as OriginAllowlistError {
            trustErrorMessage = error.errorDescription
        } catch {
            trustErrorMessage = error.localizedDescription
        }
    }

    private static func resolveTrust(returnTo: String?, isTrusted: Bool) -> TrustState {
        guard let returnTo, !returnTo.isEmpty else { return .noOrigin }
        return isTrusted ? .verified : .unverified(origin: returnTo)
    }
}
