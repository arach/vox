import Foundation
import Testing
import VoxCore
@testable import HudsonSpeechEngine

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

    @Test("Parakeet provider advertises catalog TDT models")
    func listsCatalogParakeetModels() async {
        let store = ModelCatalogStore(
            bundledCatalog: ModelCatalogStore.fallbackCatalog,
            cachedCatalog: ModelCatalogStore.fallbackCatalog,
            transport: StaticCatalogTransport(data: Data()),
            cacheURL: FileManager.default.temporaryDirectory.appendingPathComponent("unused.json")
        )
        let provider = ParakeetProvider(catalogStore: store)
        let models = await provider.models()
        #expect(models.map(\.id) == ["parakeet:v3", "parakeet:v2"])
    }

    @Test("Unknown Parakeet model ids are rejected")
    func unknownModelIdThrows() async {
        let provider = ParakeetProvider(manifest: .v3)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sample.wav")
        try? Data().write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        await #expect(throws: Error.self) {
            _ = try await provider.transcribe(url: url, modelId: "parakeet:v9")
        }
    }
}

private struct StaticCatalogTransport: CatalogTransport {
    let data: Data

    func fetch(from url: URL) async throws -> Data {
        _ = url
        return data
    }
}
