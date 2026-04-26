@preconcurrency import CoreML
import Foundation

struct ParakeetDecoderState {
    var hiddenState: MLMultiArray
    var cellState: MLMultiArray
    var lastToken: Int?
    var predictorOutput: MLMultiArray?
    var timeJump: Int?

    init(decoderLayers: Int = 2) throws {
        let decoderHiddenSize = ParakeetConstants.decoderHiddenSize
        hiddenState = try ParakeetCoreMLSupport.createAlignedArray(
            shape: [NSNumber(value: decoderLayers), 1, NSNumber(value: decoderHiddenSize)],
            dataType: .float32
        )
        cellState = try ParakeetCoreMLSupport.createAlignedArray(
            shape: [NSNumber(value: decoderLayers), 1, NSNumber(value: decoderHiddenSize)],
            dataType: .float32
        )
        hiddenState.resetData(to: 0)
        cellState.resetData(to: 0)
    }

    static func make(decoderLayers: Int = 2) -> ParakeetDecoderState {
        do {
            return try ParakeetDecoderState(decoderLayers: decoderLayers)
        } catch {
            fatalError("Failed to allocate Parakeet decoder state: \(error)")
        }
    }

    mutating func update(from decoderOutput: MLFeatureProvider) {
        hiddenState = decoderOutput.featureValue(for: "h_out")?.multiArrayValue ?? hiddenState
        cellState = decoderOutput.featureValue(for: "c_out")?.multiArrayValue ?? cellState
    }

    mutating func reset() {
        hiddenState.resetData(to: 0)
        cellState.resetData(to: 0)
        lastToken = nil
        predictorOutput = nil
        timeJump = nil
    }

    mutating func finalizeLastChunk() {
        predictorOutput = nil
        timeJump = nil
    }
}
