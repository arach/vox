import Foundation
import Testing
import VoxCore
@testable import HudsonSpeechEngine

struct ModelCatalogStoreTests {
    @Test("Bundled catalog exposes the native and next-generation ASR families")
    func bundledCatalogIncludesCurrentASRShortlist() throws {
        let catalog = ModelCatalogStore.loadBundledCatalog()
        let ids = Set(catalog.models.map(\.id))

        #expect(catalog.version == 2)
        #expect(ids.contains("apple:speech-transcriber"))
        #expect(ids.contains("moonshine:medium-streaming"))
        #expect(ids.contains("mlx-community/Qwen3-ASR-1.7B-8bit"))
        #expect(ids.contains("mlx-community/cohere-transcribe-03-2026-mlx-8bit"))
        #expect(ids.contains("mlx-community/nemotron-3.5-asr-streaming-0.6b-8bit"))

        let apple = try #require(catalog.models.first { $0.id == "apple:speech-transcriber" })
        #expect(apple.architectures == ["arm64"])
        #expect(apple.capabilities?.onDevice == true)
        #expect(apple.capabilities?.liveTranscription == false)
    }

    @Test("An older disk cache cannot hide models added by an app update")
    func newerBundledCatalogReplacesOlderCache() {
        let bundled = SpeechModelCatalog(
            version: 2,
            updatedAt: "2026-09-01",
            models: [SpeechModelCatalogEntry(id: "apple:speech-transcriber", family: SpeechModelFamily.appleSpeech, name: "Apple SpeechTranscriber")]
        )
        let cached = SpeechModelCatalog(
            version: 1,
            updatedAt: "2026-08-31",
            models: [SpeechModelCatalogEntry(id: "parakeet:v3", family: SpeechModelFamily.parakeetTDT, name: "Parakeet TDT v3")]
        )

        let selected = ModelCatalogStore.preferredCatalog(bundled: bundled, cached: cached)

        #expect(selected.version == 2)
        #expect(selected.models.map(\.id) == ["apple:speech-transcriber"])
    }

    @Test("Catalog store prefers a fetched document over the bundled snapshot")
    func refreshReplacesBundledCatalog() async throws {
        let cacheURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vox-catalog-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: cacheURL) }

        let fetched = SpeechModelCatalog(
            version: 2,
            updatedAt: "2026-08-29",
            models: [
                SpeechModelCatalogEntry(
                    id: "parakeet:v2",
                    family: SpeechModelFamily.parakeetTDT,
                    name: "Parakeet TDT v2",
                    source: SpeechModelSource(
                        type: "huggingface",
                        repo: "FluidInference/parakeet-tdt-0.6b-v2-coreml"
                    ),
                    parakeet: ParakeetCatalogSpec(
                        cacheDirectoryName: "parakeet-tdt-0.6b-v2",
                        jointFile: "JointDecision.mlmodelc",
                        vocabularyFile: "parakeet_vocab.json",
                        blankId: 1024,
                        requiredFiles: ["JointDecision.mlmodelc"]
                    )
                ),
                SpeechModelCatalogEntry(
                    id: "mlx-community/cohere-transcribe-03-2026-mlx-8bit",
                    family: SpeechModelFamily.mlxAudio,
                    name: "Cohere Transcribe"
                )
            ]
        )
        let encoder = JSONEncoder()
        let transport = StaticCatalogTransport(data: try encoder.encode(fetched))
        let store = ModelCatalogStore(
            bundledCatalog: ModelCatalogStore.fallbackCatalog,
            cachedCatalog: ModelCatalogStore.fallbackCatalog,
            transport: transport,
            cacheURL: cacheURL
        )

        let refreshed = try await store.refresh(from: URL(string: "https://voxd.cc/data/models.json")!)
        #expect(refreshed.version == 2)
        #expect(store.parakeetModelIDs() == ["parakeet:v2"])
        #expect(store.mlxAudioModelIDs() == ["mlx-community/cohere-transcribe-03-2026-mlx-8bit"])
        #expect(FileManager.default.fileExists(atPath: cacheURL.path))
    }
}

private struct StaticCatalogTransport: CatalogTransport {
    let data: Data

    func fetch(from url: URL) async throws -> Data {
        _ = url
        return data
    }
}
