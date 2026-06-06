import Testing
import VoxCore
@testable import HudsonSpeechEngine

struct ParakeetTextProcessingTests {
    @Test("SentencePiece tokens join into readable text")
    func convertsTokensToReadableText() {
        let vocabulary = [
            1: "▁hello",
            2: "▁world",
            3: "!"
        ]

        #expect(
            ParakeetTextProcessing.convertTokensToText([1, 2, 3], vocabulary: vocabulary) == "hello world!"
        )
    }

    @Test("Word timings drop blank tokens and map frame durations")
    func createsWordTimingsFromDecoderOutputs() {
        let vocabulary = [
            1: "▁hello",
            2: "▁world",
            3: "▁"
        ]

        let timings = ParakeetTextProcessing.createWordTimings(
            tokenIds: [2, 3, 1],
            timestamps: [5, 6, 1],
            confidences: [0.8, 0.2, 0.9],
            tokenDurations: [2, 1, 1],
            vocabulary: vocabulary
        )

        #expect(timings.count == 2)
        #expect(timings[0] == WordTiming(word: "hello", start: 0.08, end: 0.16, confidence: 0.9))
        #expect(timings[1] == WordTiming(word: "world", start: 0.4, end: 0.56, confidence: 0.8))
    }
}
