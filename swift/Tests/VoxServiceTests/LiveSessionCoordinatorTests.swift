import Foundation
import Testing
@testable import VoxService

struct LiveSessionCoordinatorTests {
    @Test("Only one live session can be active at a time")
    func beginRejectsSecondSession() throws {
        let coordinator = LiveSessionCoordinator()

        _ = try coordinator.begin(
            connectionID: "a",
            clientId: "client-a",
            modelId: "parakeet:v3",
            progress: { _, _ in },
            reply: { _, _ in }
        )

        #expect(throws: Error.self) {
            _ = try coordinator.begin(
                connectionID: "b",
                clientId: "client-b",
                modelId: "parakeet:v3",
                progress: { _, _ in },
                reply: { _, _ in }
            )
        }
    }

    @Test("Active session can be finished by connection")
    func finishByConnectionRemovesSession() throws {
        let coordinator = LiveSessionCoordinator()
        let session = try coordinator.begin(
            connectionID: "a",
            clientId: "client-a",
            modelId: "parakeet:v3",
            progress: { _, _ in },
            reply: { _, _ in }
        )

        let finished = coordinator.finish(connectionID: "a")
        #expect(finished?.sessionId == session.sessionId)
        #expect(coordinator.current(id: nil) == nil)
    }
}
