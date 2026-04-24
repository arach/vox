import Foundation
import Testing
@testable import VoxEngine

struct TTSProviderTests {
    @Test("AVSpeechSynthesizerProvider lists system voices and emits wav audio")
    func avSpeechSynthesizerProviderGeneratesAudio() async throws {
        let provider = AVSpeechSynthesizerProvider()
        let voices = try await provider.voices(modelId: AVSpeechSynthesizerProvider.modelID)
        let voice = try #require(voices.first)

        let output = try await provider.synthesize(SynthesisRequest(
            text: "Vox synthesis test",
            modelId: AVSpeechSynthesizerProvider.modelID,
            voiceId: voice.id
        ))

        #expect(output.modelId == AVSpeechSynthesizerProvider.modelID)
        #expect(output.voiceId == voice.id)
        #expect(output.format == "wav")
        #expect(output.audioData.count > 0)
        #expect(output.metrics.audioDurationMs > 0)
        #expect(output.metrics.outputBytes == output.audioData.count)
    }
}
