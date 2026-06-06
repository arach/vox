import Accelerate
@preconcurrency import CoreML
import Darwin
import Foundation

enum ParakeetCoreMLSupport {
    private static let aneAlignment = 64
    private static let aneTileSize = 16

    static func optimizedPredictionOptions() -> MLPredictionOptions {
        let options = MLPredictionOptions()
        options.outputBackings = [:]
        return options
    }

    static func createFeatureProvider(features: [(name: String, array: MLMultiArray)]) throws -> MLFeatureProvider {
        var featureDict: [String: MLFeatureValue] = [:]
        featureDict.reserveCapacity(features.count)
        for (name, array) in features {
            featureDict[name] = MLFeatureValue(multiArray: array)
        }
        return try MLDictionaryFeatureProvider(dictionary: featureDict)
    }

    static func createScalarArray(
        value: Int,
        shape: [NSNumber] = [1],
        dataType: MLMultiArrayDataType = .int32
    ) throws -> MLMultiArray {
        let array = try MLMultiArray(shape: shape, dataType: dataType)
        array[0] = NSNumber(value: value)
        return array
    }

    static func extractFeatureValue(
        from provider: MLFeatureProvider,
        key: String,
        errorMessage: String
    ) throws -> MLMultiArray {
        guard let value = provider.featureValue(for: key)?.multiArrayValue else {
            throw ParakeetDecodeError.processingFailed(errorMessage)
        }
        return value
    }

    static func createAlignedArray(
        shape: [NSNumber],
        dataType: MLMultiArrayDataType,
        zeroClear: Bool = true
    ) throws -> MLMultiArray {
        let elementSize = getElementSize(for: dataType)
        let strides = calculateOptimalStrides(for: shape)

        let totalElementsNeeded: Int
        if !shape.isEmpty {
            totalElementsNeeded = strides[0].intValue * shape[0].intValue
        } else {
            totalElementsNeeded = 0
        }

        let bytesNeeded = totalElementsNeeded * elementSize
        let alignedBytes = max(aneAlignment, ((bytesNeeded + aneAlignment - 1) / aneAlignment) * aneAlignment)

        var alignedPointer: UnsafeMutableRawPointer?
        let result = posix_memalign(&alignedPointer, aneAlignment, alignedBytes)

        guard result == 0, let pointer = alignedPointer else {
            throw ParakeetDecodeError.processingFailed("Failed to allocate aligned CoreML buffer")
        }

        if zeroClear {
            memset(pointer, 0, alignedBytes)
        }

        return try MLMultiArray(
            dataPointer: pointer,
            shape: shape,
            dataType: dataType,
            strides: strides,
            deallocator: { bytes in
                Darwin.free(bytes)
            }
        )
    }

    private static func calculateOptimalStrides(for shape: [NSNumber]) -> [NSNumber] {
        var strides: [Int] = []
        var currentStride = 1

        for index in (0..<shape.count).reversed() {
            strides.insert(currentStride, at: 0)
            let dimensionSize = shape[index].intValue

            if index == shape.count - 1, dimensionSize % aneTileSize != 0 {
                let paddedSize = ((dimensionSize + aneTileSize - 1) / aneTileSize) * aneTileSize
                currentStride *= paddedSize
            } else {
                currentStride *= dimensionSize
            }
        }

        return strides.map(NSNumber.init(value:))
    }

    private static func getElementSize(for dataType: MLMultiArrayDataType) -> Int {
        switch dataType {
        case .int8:
            return 1
        case .float16:
            return 2
        case .float32:
            return 4
        case .double:
            return 8
        case .int32:
            return MemoryLayout<Int32>.stride
        @unknown default:
            return MemoryLayout<Float>.stride
        }
    }
}

extension MLModel {
    func compatPrediction(
        from input: MLFeatureProvider,
        options: MLPredictionOptions
    ) async throws -> MLFeatureProvider {
        try await prediction(from: input, options: options)
    }
}

extension MLMultiArray {
    func resetData(to value: NSNumber) {
        for index in 0..<count {
            self[index] = value
        }
    }

    func copyData(from source: MLMultiArray) {
        for index in 0..<count {
            self[index] = source[index]
        }
    }
}
