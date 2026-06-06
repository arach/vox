import Testing
@testable import HudsonSpeechEngine

struct ParakeetChunkMergerTests {
    @Test("Chunk merger preserves exact overlap only once")
    func preservesExactOverlapOnce() {
        let left: [ParakeetChunkToken] = [
            .init(token: 1, timestamp: 0, confidence: 0.9, duration: 1),
            .init(token: 2, timestamp: 1, confidence: 0.9, duration: 1),
            .init(token: 3, timestamp: 2, confidence: 0.9, duration: 1),
            .init(token: 4, timestamp: 3, confidence: 0.9, duration: 1),
        ]
        let right: [ParakeetChunkToken] = [
            .init(token: 3, timestamp: 2, confidence: 0.8, duration: 1),
            .init(token: 4, timestamp: 3, confidence: 0.8, duration: 1),
            .init(token: 5, timestamp: 4, confidence: 0.8, duration: 1),
        ]

        let merged = ParakeetChunkMerger(overlapSeconds: 2.0).merge(left, right)
        #expect(merged.map(\.token) == [1, 2, 3, 4, 5])
    }

    @Test("Chunk merger falls back to midpoint split when there is no token match")
    func midpointFallback() {
        let left: [ParakeetChunkToken] = [
            .init(token: 10, timestamp: 10, confidence: 0.9, duration: 1),
            .init(token: 11, timestamp: 11, confidence: 0.9, duration: 1),
            .init(token: 12, timestamp: 12, confidence: 0.9, duration: 1),
        ]
        let right: [ParakeetChunkToken] = [
            .init(token: 20, timestamp: 12, confidence: 0.8, duration: 1),
            .init(token: 21, timestamp: 13, confidence: 0.8, duration: 1),
            .init(token: 22, timestamp: 14, confidence: 0.8, duration: 1),
        ]

        let merged = ParakeetChunkMerger(overlapSeconds: 2.0).merge(left, right)
        #expect(merged.first?.token == 10)
        #expect(merged.last?.token == 22)
        #expect(merged.map(\.token).contains(12) || merged.map(\.token).contains(20))
    }
}
