@preconcurrency import CoreML
import Foundation
import Testing
@testable import VoxEngine

struct ParakeetDecoderSupportTests {
    @Test("Language filter chooses matching-script top-K candidates")
    func tokenLanguageFilterPrefersMatchingScript() {
        let vocabulary = [
            1: "hello",
            2: "привет",
            3: "bonjour"
        ]

        let filtered = ParakeetTokenLanguageFilter.filterTopK(
            topKIds: [2, 1, 3],
            topKLogits: [4.0, 3.0, 2.0],
            vocabulary: vocabulary,
            preferredScript: .latin
        )

        #expect(filtered?.tokenId == 1)
        #expect((filtered?.probability ?? 0) > 0)
    }

    @Test("Duration mapping validates bin bounds and clamps probabilities")
    func durationMappingValidatesInputs() throws {
        #expect(try ParakeetDurationMapping.mapDurationBin(2, durationBins: [0, 1, 2, 3, 4]) == 2)
        #expect(ParakeetDurationMapping.clampProbability(1.5) == 1)
        #expect(ParakeetDurationMapping.clampProbability(-0.25) == 0)
        #expect(ParakeetDurationMapping.clampProbability(.nan) == 0)
        #expect(throws: Error.self) {
            _ = try ParakeetDurationMapping.mapDurationBin(9, durationBins: [0, 1, 2, 3, 4])
        }
    }

    @Test("Frame navigation handles first-chunk and overlap cases")
    func frameNavigationCalculations() {
        #expect(ParakeetFrameNavigation.calculateInitialTimeIndices(timeJump: nil, contextFrameAdjustment: 3) == 3)
        #expect(ParakeetFrameNavigation.calculateInitialTimeIndices(timeJump: 0, contextFrameAdjustment: 0) == ParakeetConstants.standardOverlapFrames)

        let state = ParakeetFrameNavigation.initializeNavigationState(
            timeIndices: 5,
            encoderSequenceLength: 10,
            actualAudioFrames: 8
        )
        #expect(state.effectiveSequenceLength == 8)
        #expect(state.safeTimeIndices == 5)
        #expect(state.lastTimestep == 7)
        #expect(state.activeMask)
        #expect(ParakeetFrameNavigation.calculateFinalTimeJump(currentTimeIndices: 11, effectiveSequenceLength: 8, isLastChunk: false) == 3)
        #expect(ParakeetFrameNavigation.calculateFinalTimeJump(currentTimeIndices: 11, effectiveSequenceLength: 8, isLastChunk: true) == nil)
    }

    @Test("Encoder frame view copies hidden vectors from contiguous encoder output")
    func encoderFrameViewCopiesFrames() throws {
        let array = try MLMultiArray(shape: [1, 2, 3], dataType: .float32)
        let values: [Float] = [1, 2, 3, 4, 5, 6]
        let pointer = array.dataPointer.bindMemory(to: Float.self, capacity: values.count)
        for (index, value) in values.enumerated() {
            pointer[index] = value
        }

        let view = try ParakeetEncoderFrameView(
            encoderOutput: array,
            validLength: 2,
            expectedHiddenSize: 3
        )
        let destination = UnsafeMutablePointer<Float>.allocate(capacity: 3)
        defer { destination.deallocate() }

        try view.copyFrame(at: 1, into: destination, destinationStride: 1)
        let copied = Array(UnsafeBufferPointer(start: destination, count: 3))

        #expect(copied == [4, 5, 6])
    }
}
