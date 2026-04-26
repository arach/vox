import Accelerate
@preconcurrency import CoreML
import Foundation

struct ParakeetModelInference: Sendable {
    private let predictionOptions: MLPredictionOptions

    init() {
        self.predictionOptions = ParakeetCoreMLSupport.optimizedPredictionOptions()
    }

    func runDecoder(
        token: Int,
        state: ParakeetDecoderState,
        model: MLModel,
        targetArray: MLMultiArray,
        targetLengthArray: MLMultiArray
    ) throws -> (output: MLFeatureProvider, newState: ParakeetDecoderState) {
        targetArray[0] = NSNumber(value: token)

        let input = try MLDictionaryFeatureProvider(dictionary: [
            "targets": MLFeatureValue(multiArray: targetArray),
            "target_length": MLFeatureValue(multiArray: targetLengthArray),
            "h_in": MLFeatureValue(multiArray: state.hiddenState),
            "c_in": MLFeatureValue(multiArray: state.cellState),
        ])

        predictionOptions.outputBackings = [
            "h_out": state.hiddenState,
            "c_out": state.cellState,
        ]

        let output = try model.prediction(from: input, options: predictionOptions)
        var newState = state
        newState.update(from: output)
        return (output, newState)
    }

    func runJointPrepared(
        encoderFrames: ParakeetEncoderFrameView,
        timeIndex: Int,
        preparedDecoderStep: MLMultiArray,
        model: MLModel,
        encoderStep: MLMultiArray,
        encoderDestPtr: UnsafeMutablePointer<Float>,
        encoderDestStride: Int,
        inputProvider: MLFeatureProvider,
        tokenIdBacking: MLMultiArray,
        tokenProbBacking: MLMultiArray,
        durationBacking: MLMultiArray,
        needsTopK: Bool = false
    ) throws -> ParakeetJointDecision {
        try encoderFrames.copyFrame(at: timeIndex, into: encoderDestPtr, destinationStride: encoderDestStride)

        predictionOptions.outputBackings = [
            "token_id": tokenIdBacking,
            "token_prob": tokenProbBacking,
            "duration": durationBacking,
        ]

        let output = try model.prediction(from: inputProvider, options: predictionOptions)
        let tokenIdArray = try ParakeetCoreMLSupport.extractFeatureValue(
            from: output,
            key: "token_id",
            errorMessage: "Joint decision output missing token_id"
        )
        let tokenProbArray = try ParakeetCoreMLSupport.extractFeatureValue(
            from: output,
            key: "token_prob",
            errorMessage: "Joint decision output missing token_prob"
        )
        let durationArray = try ParakeetCoreMLSupport.extractFeatureValue(
            from: output,
            key: "duration",
            errorMessage: "Joint decision output missing duration"
        )

        guard tokenIdArray.count == 1, tokenProbArray.count == 1, durationArray.count == 1 else {
            throw ParakeetDecodeError.processingFailed("Joint decision returned unexpected tensor shapes")
        }

        let tokenPointer = tokenIdArray.dataPointer.bindMemory(to: Int32.self, capacity: tokenIdArray.count)
        let probabilityPointer = tokenProbArray.dataPointer.bindMemory(to: Float.self, capacity: tokenProbArray.count)
        let durationPointer = durationArray.dataPointer.bindMemory(to: Int32.self, capacity: durationArray.count)

        var topKIds: [Int]?
        var topKLogits: [Float]?
        if needsTopK {
            topKIds = try extractInt32Array(from: output, key: "top_k_ids")
            topKLogits = try extractFloat32Array(from: output, key: "top_k_logits")

            switch (topKIds, topKLogits) {
            case (nil, nil):
                break
            case (let ids?, let logits?):
                guard ids.count == logits.count else {
                    throw ParakeetDecodeError.processingFailed(
                        "Joint decision top-K length mismatch: \(ids.count) vs \(logits.count)"
                    )
                }
            default:
                throw ParakeetDecodeError.processingFailed(
                    "Joint decision top-K outputs must be present as a pair"
                )
            }
        }

        return ParakeetJointDecision(
            token: Int(tokenPointer[0]),
            probability: probabilityPointer[0],
            durationBin: Int(durationPointer[0]),
            topKIds: topKIds,
            topKLogits: topKLogits
        )
    }

    @discardableResult
    func normalizeDecoderProjection(
        _ projection: MLMultiArray,
        into destination: MLMultiArray? = nil
    ) throws -> MLMultiArray {
        let hiddenSize = ParakeetConstants.decoderHiddenSize
        let shape = projection.shape.map(\.intValue)

        guard shape.count == 3 else {
            throw ParakeetDecodeError.processingFailed("Invalid decoder projection rank: \(shape)")
        }
        guard shape[0] == 1 else {
            throw ParakeetDecodeError.processingFailed("Unsupported decoder batch dimension: \(shape[0])")
        }
        guard projection.dataType == .float32 else {
            throw ParakeetDecodeError.processingFailed(
                "Unsupported decoder projection type: \(projection.dataType)"
            )
        }

        let hiddenAxis: Int
        if shape[2] == hiddenSize {
            hiddenAxis = 2
        } else if shape[1] == hiddenSize {
            hiddenAxis = 1
        } else {
            throw ParakeetDecodeError.processingFailed("Decoder projection hidden size mismatch: \(shape)")
        }

        let timeAxis = (0...2).first { $0 != hiddenAxis && $0 != 0 } ?? 1
        guard shape[timeAxis] == 1 else {
            throw ParakeetDecodeError.processingFailed("Decoder projection time axis must be 1: \(shape)")
        }

        let out: MLMultiArray
        if let destination {
            let outShape = destination.shape.map(\.intValue)
            guard destination.dataType == .float32, outShape.count == 3, outShape[0] == 1,
                  outShape[2] == 1, outShape[1] == hiddenSize else {
                throw ParakeetDecodeError.processingFailed("Prepared decoder step shape mismatch: \(outShape)")
            }
            out = destination
        } else {
            out = try ParakeetCoreMLSupport.createAlignedArray(
                shape: [1, NSNumber(value: hiddenSize), 1],
                dataType: .float32
            )
        }

        let strides = projection.strides.map(\.intValue)
        let hiddenStride = strides[hiddenAxis]
        let dataPointer = projection.dataPointer.bindMemory(to: Float.self, capacity: projection.count)
        let destPtr = out.dataPointer.bindMemory(to: Float.self, capacity: hiddenSize)
        let destStrides = out.strides.map(\.intValue)
        let destHiddenStride = destStrides[1]

        let count = try makeParakeetBlasIndex(hiddenSize, label: "Decoder projection length")
        let sourceStride = try makeParakeetBlasIndex(hiddenStride, label: "Decoder projection stride")
        let destStride = try makeParakeetBlasIndex(destHiddenStride, label: "Decoder destination stride")
        cblas_scopy(count, dataPointer, sourceStride, destPtr, destStride)

        return out
    }

    private func extractInt32Array(from output: MLFeatureProvider, key: String) throws -> [Int]? {
        guard let array = output.featureValue(for: key)?.multiArrayValue else { return nil }
        guard array.dataType == .int32 else {
            throw ParakeetDecodeError.processingFailed("Expected Int32 for \(key), got \(array.dataType.rawValue)")
        }
        let count = array.count
        let pointer = array.dataPointer.bindMemory(to: Int32.self, capacity: count)
        return (0..<count).map { Int(pointer[$0]) }
    }

    private func extractFloat32Array(from output: MLFeatureProvider, key: String) throws -> [Float]? {
        guard let array = output.featureValue(for: key)?.multiArrayValue else { return nil }
        guard array.dataType == .float32 else {
            throw ParakeetDecodeError.processingFailed("Expected Float32 for \(key), got \(array.dataType.rawValue)")
        }
        let count = array.count
        let pointer = array.dataPointer.bindMemory(to: Float.self, capacity: count)
        return (0..<count).map { pointer[$0] }
    }
}
