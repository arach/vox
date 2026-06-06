import Foundation
import Testing
@testable import HudsonSpeechEngine

struct ParakeetModelLoaderTests {
    @Test("Parakeet model loader resolves the expected v3 artifact paths")
    func resolvesExpectedArtifactPaths() {
        let loader = ParakeetModelLoader(manifest: .v3)
        let directory = URL(fileURLWithPath: "/tmp/parakeet-test-models", isDirectory: true)

        let urls = loader.modelURLs(in: directory)

        #expect(urls.preprocessor.lastPathComponent == "Preprocessor.mlmodelc")
        #expect(urls.encoder.lastPathComponent == "Encoder.mlmodelc")
        #expect(urls.decoder.lastPathComponent == "Decoder.mlmodelc")
        #expect(urls.joint.lastPathComponent == "JointDecisionv3.mlmodelc")
        #expect(urls.vocabulary.lastPathComponent == "parakeet_vocab.json")
    }
}
