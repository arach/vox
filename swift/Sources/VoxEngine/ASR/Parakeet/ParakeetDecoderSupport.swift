import Accelerate
@preconcurrency import CoreML
import Foundation

struct ParakeetTdtConfig: Sendable {
    let includeTokenDuration: Bool
    let maxSymbolsPerStep: Int
    let durationBins: [Int]
    let blankId: Int
    let boundarySearchFrames: Int
    let maxTokensPerChunk: Int
    let consecutiveBlankLimit: Int

    static let `default` = ParakeetTdtConfig()

    init(
        includeTokenDuration: Bool = true,
        maxSymbolsPerStep: Int = 10,
        durationBins: [Int] = [0, 1, 2, 3, 4],
        blankId: Int = 8192,
        boundarySearchFrames: Int = 20,
        maxTokensPerChunk: Int = 150,
        consecutiveBlankLimit: Int = 5
    ) {
        self.includeTokenDuration = includeTokenDuration
        self.maxSymbolsPerStep = maxSymbolsPerStep
        self.durationBins = durationBins
        self.blankId = blankId
        self.boundarySearchFrames = boundarySearchFrames
        self.maxTokensPerChunk = maxTokensPerChunk
        self.consecutiveBlankLimit = consecutiveBlankLimit
    }
}

struct ParakeetInferenceConfig: Sendable {
    let sampleRate: Int
    let tdtConfig: ParakeetTdtConfig
    let encoderHiddenSize: Int
    let parallelChunkConcurrency: Int
    let streamingEnabled: Bool
    let streamingThreshold: Int

    static let `default` = ParakeetInferenceConfig()

    init(
        sampleRate: Int = ParakeetConstants.sampleRate,
        tdtConfig: ParakeetTdtConfig = .default,
        encoderHiddenSize: Int = ParakeetConstants.encoderHiddenSize,
        parallelChunkConcurrency: Int = 4,
        streamingEnabled: Bool = true,
        streamingThreshold: Int = 480_000
    ) {
        self.sampleRate = sampleRate
        self.tdtConfig = tdtConfig
        self.encoderHiddenSize = encoderHiddenSize
        self.parallelChunkConcurrency = max(1, parallelChunkConcurrency)
        self.streamingEnabled = streamingEnabled
        self.streamingThreshold = streamingThreshold
    }
}

enum ParakeetDecodeError: LocalizedError {
    case processingFailed(String)

    var errorDescription: String? {
        switch self {
        case .processingFailed(let message):
            return message
        }
    }
}

struct ParakeetJointDecision: Sendable {
    let token: Int
    let probability: Float
    let durationBin: Int
    let topKIds: [Int]?
    let topKLogits: [Float]?

    init(
        token: Int,
        probability: Float,
        durationBin: Int,
        topKIds: [Int]? = nil,
        topKLogits: [Float]? = nil
    ) {
        assert(topKIds?.count == topKLogits?.count)
        self.token = token
        self.probability = probability
        self.durationBin = durationBin
        self.topKIds = topKIds
        self.topKLogits = topKLogits
    }
}

enum ParakeetDurationMapping {
    static func mapDurationBin(_ binIndex: Int, durationBins: [Int]) throws -> Int {
        guard binIndex >= 0 && binIndex < durationBins.count else {
            throw ParakeetDecodeError.processingFailed("Duration bin index out of range: \(binIndex)")
        }
        return durationBins[binIndex]
    }

    static func clampProbability(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        return max(0, min(1, value))
    }
}

enum ParakeetFrameNavigation {
    static func calculateInitialTimeIndices(
        timeJump: Int?,
        contextFrameAdjustment: Int
    ) -> Int {
        guard let previousTimeJump = timeJump else {
            return contextFrameAdjustment
        }

        if previousTimeJump == 0 && contextFrameAdjustment == 0 {
            return ParakeetConstants.standardOverlapFrames
        }

        return max(0, previousTimeJump + contextFrameAdjustment)
    }

    static func initializeNavigationState(
        timeIndices: Int,
        encoderSequenceLength: Int,
        actualAudioFrames: Int
    ) -> (effectiveSequenceLength: Int, safeTimeIndices: Int, lastTimestep: Int, activeMask: Bool) {
        let effectiveSequenceLength = min(encoderSequenceLength, actualAudioFrames)
        let safeTimeIndices = min(timeIndices, effectiveSequenceLength - 1)
        let lastTimestep = effectiveSequenceLength - 1
        let activeMask = timeIndices < effectiveSequenceLength
        return (effectiveSequenceLength, safeTimeIndices, lastTimestep, activeMask)
    }

    static func calculateFinalTimeJump(
        currentTimeIndices: Int,
        effectiveSequenceLength: Int,
        isLastChunk: Bool
    ) -> Int? {
        if isLastChunk {
            return nil
        }

        return currentTimeIndices - effectiveSequenceLength
    }
}

typealias ParakeetBlasIndex = Int32

@inline(__always)
func makeParakeetBlasIndex(_ value: Int, label: String) throws -> ParakeetBlasIndex {
    guard let cast = ParakeetBlasIndex(exactly: value) else {
        throw ParakeetDecodeError.processingFailed("\(label) exceeds supported range")
    }
    return cast
}

struct ParakeetEncoderFrameView {
    let hiddenSize: Int
    let count: Int

    private let array: MLMultiArray
    private let timeAxis: Int
    private let hiddenAxis: Int
    private let timeStride: Int
    private let hiddenStride: Int
    private let timeBaseOffset: Int
    private let basePointer: UnsafeMutablePointer<Float>

    init(encoderOutput: MLMultiArray, validLength: Int, expectedHiddenSize: Int) throws {
        let shape = encoderOutput.shape.map { $0.intValue }
        guard shape.count == 3 else {
            throw ParakeetDecodeError.processingFailed("Invalid encoder output shape: \(shape)")
        }
        guard shape[0] == 1 else {
            throw ParakeetDecodeError.processingFailed("Unsupported batch dimension: \(shape[0])")
        }

        let hiddenSize = expectedHiddenSize
        let axis1MatchesHidden = shape[1] == hiddenSize
        let axis2MatchesHidden = shape[2] == hiddenSize
        guard axis1MatchesHidden || axis2MatchesHidden else {
            throw ParakeetDecodeError.processingFailed(
                "Encoder hidden size mismatch: \(shape), expected \(hiddenSize)"
            )
        }

        self.hiddenAxis = axis1MatchesHidden ? 1 : 2
        self.timeAxis = axis1MatchesHidden ? 2 : 1
        self.hiddenSize = hiddenSize

        let strides = encoderOutput.strides.map { $0.intValue }
        self.hiddenStride = strides[self.hiddenAxis]
        self.timeStride = strides[self.timeAxis]

        let availableFrames = shape[self.timeAxis]
        self.count = min(validLength, availableFrames)
        guard count > 0 else {
            throw ParakeetDecodeError.processingFailed("Encoder output has no frames")
        }
        self.array = encoderOutput

        guard encoderOutput.dataType == .float32 else {
            throw ParakeetDecodeError.processingFailed("Unsupported encoder output type: \(encoderOutput.dataType)")
        }

        self.basePointer = encoderOutput.dataPointer.bindMemory(to: Float.self, capacity: encoderOutput.count)
        self.timeBaseOffset = timeStride >= 0 ? 0 : (availableFrames - 1) * timeStride
    }

    init(encoderOutput: MLMultiArray, validLength: Int) throws {
        try self.init(
            encoderOutput: encoderOutput,
            validLength: validLength,
            expectedHiddenSize: ParakeetConstants.encoderHiddenSize
        )
    }

    func copyFrame(
        at index: Int,
        into destination: UnsafeMutablePointer<Float>,
        destinationStride: Int
    ) throws {
        guard index >= 0 && index < count else {
            throw ParakeetDecodeError.processingFailed("Encoder frame index out of range: \(index)")
        }

        let frameOffset = timeBaseOffset + index * timeStride
        let frameStart = basePointer.advanced(by: frameOffset)

        guard hiddenStride != 0 else {
            throw ParakeetDecodeError.processingFailed("Invalid hidden stride: 0")
        }

        let sourcePointer = UnsafePointer<Float>(frameStart)
        let count = try makeParakeetBlasIndex(hiddenSize, label: "Hidden size")
        let incX = try makeParakeetBlasIndex(hiddenStride, label: "Hidden stride")
        let incY = try makeParakeetBlasIndex(destinationStride, label: "Destination stride")

        if hiddenStride == 1 && destinationStride == 1 {
            destination.update(from: sourcePointer, count: hiddenSize)
        } else {
            cblas_scopy(count, sourcePointer, incX, destination, incY)
        }
    }
}
