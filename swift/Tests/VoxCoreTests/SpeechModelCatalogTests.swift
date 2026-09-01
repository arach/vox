import Foundation
import Testing
import VoxCore

struct SpeechModelCatalogTests {
    @Test("Speech model catalog decodes published model records")
    func decodesPublishedCatalogShape() throws {
        let data = Data(#"""
        {
          "version": 1,
          "updatedAt": "2026-08-29",
          "plugins": [
            {
              "id": "mlx-vlm",
              "kind": "asr",
              "name": "MLX-VLM",
              "install": { "kind": "bundle", "id": "mlx-vlm" }
            }
          ],
          "models": [
            {
              "id": "parakeet:v3",
              "kind": "asr",
              "family": "parakeet-tdt",
              "name": "Parakeet TDT v3",
              "default": true,
              "parakeet": {
                "cacheDirectoryName": "parakeet-tdt-0.6b-v3",
                "jointFile": "JointDecisionv3.mlmodelc",
                "vocabularyFile": "parakeet_vocab.json",
                "blankId": 8192,
                "requiredFiles": ["JointDecisionv3.mlmodelc"]
              }
            },
            {
              "id": "gpt-transcribe",
              "kind": "asr",
              "family": "openai-transcribe",
              "name": "GPT Transcribe",
              "status": "ready",
              "requires": ["OPENAI_API_KEY"],
              "platforms": ["macOS 14+"],
              "architectures": ["arm64"],
              "capabilities": {
                "fileTranscription": true,
                "liveTranscription": false,
                "onDevice": false,
                "wordTimestamps": false
              }
            },
            {
              "id": "gemma-4-e2b-it",
              "kind": "asr",
              "family": "mlx-vlm",
              "name": "Gemma 4 E2B",
              "status": "plugin",
              "plugin": "mlx-vlm"
            }
          ]
        }
        """#.utf8)

        let catalog = try SpeechModelCatalog.decode(from: data)
        #expect(catalog.version == 1)
        #expect(catalog.models(family: SpeechModelFamily.parakeetTDT, readyOnly: true).map(\.id) == ["parakeet:v3"])
        #expect(catalog.models(family: SpeechModelFamily.openaiTranscribe).map(\.id) == ["gpt-transcribe"])
        let openAI = try #require(catalog.models.first { $0.id == "gpt-transcribe" })
        #expect(openAI.platforms == ["macOS 14+"])
        #expect(openAI.architectures == ["arm64"])
        #expect(openAI.capabilities?.fileTranscription == true)
        #expect(openAI.capabilities?.liveTranscription == false)
        #expect(openAI.capabilities?.onDevice == false)
        #expect(catalog.models(family: SpeechModelFamily.mlxVlm, readyOnly: true).isEmpty)
        #expect(catalog.models(family: SpeechModelFamily.mlxVlm, readyOnly: false).map(\.id) == ["gemma-4-e2b-it"])
        #expect(catalog.plugin(id: "mlx-vlm")?.install?.kind == "bundle")
        #expect(VoxDefaults.resolvedModelCatalogURL().absoluteString.hasSuffix("/data/models.json"))
    }
}
