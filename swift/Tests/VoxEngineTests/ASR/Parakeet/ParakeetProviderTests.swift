import Foundation
import Testing
@testable import VoxEngine

struct ParakeetProviderTests {
    @Test("Missing audio file fails before model loading")
    func missingAudioFileThrowsValidationError() async throws {
        let provider = ParakeetProvider()
        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")

        await #expect(throws: Error.self) {
            _ = try await provider.transcribe(url: missingURL, modelId: "parakeet:v3")
        }
    }
}
