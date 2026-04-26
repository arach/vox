@preconcurrency import CoreML
import Foundation
import VoxCore

final class ParakeetSingleChunkTranscriber: @unchecked Sendable {
    private let models: ParakeetLoadedModels
    private let config: ParakeetInferenceConfig
    private let decoder: ParakeetDecoderV3
    private let predictionOptions: MLPredictionOptions

    init(
        models: ParakeetLoadedModels,
        config: ParakeetInferenceConfig = .default
    ) {
        self.models = models
        self.config = config
        self.decoder = ParakeetDecoderV3(config: config)
        self.predictionOptions = ParakeetCoreMLSupport.optimizedPredictionOptions()
    }

    func transcribe(samples: [Float]) async throws -> ParakeetInferenceResult {
        let minimumRequiredSamples = ParakeetConstants.minimumRequiredSamples(forSampleRate: config.sampleRate)
        guard samples.count >= minimumRequiredSamples else {
            throw ParakeetDecodeError.processingFailed("Audio must be at least \(minimumRequiredSamples) samples")
        }
        guard samples.count <= ParakeetConstants.maxModelSamples else {
            throw ParakeetDecodeError.processingFailed("Single-chunk transcriber only supports clips up to \(ParakeetConstants.maxModelSamples) samples")
        }

        let (alignedSamples, frameAlignedLength) = frameAlignedAudio(samples)
        let paddedAudio = padAudioIfNeeded(alignedSamples, targetLength: ParakeetConstants.maxModelSamples)
        let preprocessorInput = try preparePreprocessorInput(paddedAudio, actualLength: frameAlignedLength)
        let preprocessorOutput = try await models.preprocessor.compatPrediction(
            from: preprocessorInput,
            options: predictionOptions
        )

        let encoderInput = try prepareEncoderInput(
            encoder: models.encoder,
            preprocessorOutput: preprocessorOutput,
            originalInput: preprocessorInput
        )
        let encoderOutputProvider = try await models.encoder.compatPrediction(
            from: encoderInput,
            options: predictionOptions
        )

        let encoderOutput = try ParakeetCoreMLSupport.extractFeatureValue(
            from: encoderOutputProvider,
            key: "encoder",
            errorMessage: "Invalid encoder output"
        )
        let encoderLength = try ParakeetCoreMLSupport.extractFeatureValue(
            from: encoderOutputProvider,
            key: "encoder_length",
            errorMessage: "Invalid encoder output length"
        )

        var decoderState = try ParakeetDecoderState(decoderLayers: 2)
        let hypothesis = try await decoder.decodeWithTimings(
            encoderOutput: encoderOutput,
            encoderSequenceLength: encoderLength[0].intValue,
            actualAudioFrames: ParakeetConstants.calculateEncoderFrames(from: frameAlignedLength),
            decoderModel: models.decoder,
            jointModel: models.joint,
            decoderState: &decoderState,
            isLastChunk: true,
            vocabulary: models.vocabulary
        )

        return ParakeetInferenceResult(
            text: ParakeetTextProcessing.convertTokensToText(
                hypothesis.tokenIDs,
                vocabulary: models.vocabulary
            ),
            words: ParakeetTextProcessing.createWordTimings(
                tokenIds: hypothesis.tokenIDs,
                timestamps: hypothesis.timestamps,
                confidences: hypothesis.tokenConfidences,
                tokenDurations: hypothesis.tokenDurations,
                vocabulary: models.vocabulary
            )
        )
    }

    private func preparePreprocessorInput(
        _ audioSamples: [Float],
        actualLength: Int
    ) throws -> MLFeatureProvider {
        let audioArray = try ParakeetCoreMLSupport.createAlignedArray(
            shape: [1, NSNumber(value: audioSamples.count)],
            dataType: .float32
        )

        audioSamples.withUnsafeBufferPointer { buffer in
            let destination = audioArray.dataPointer.bindMemory(to: Float.self, capacity: audioSamples.count)
            destination.update(from: buffer.baseAddress!, count: audioSamples.count)
        }

        let lengthArray = try ParakeetCoreMLSupport.createScalarArray(value: actualLength)
        return try ParakeetCoreMLSupport.createFeatureProvider(features: [
            ("audio_signal", audioArray),
            ("audio_length", lengthArray),
        ])
    }

    private func prepareEncoderInput(
        encoder: MLModel,
        preprocessorOutput: MLFeatureProvider,
        originalInput: MLFeatureProvider
    ) throws -> MLFeatureProvider {
        let inputDescriptions = encoder.modelDescription.inputDescriptionsByName
        let missingNames = inputDescriptions.keys.filter { preprocessorOutput.featureValue(for: $0) == nil }

        if missingNames.isEmpty {
            return preprocessorOutput
        }

        var features: [String: MLFeatureValue] = [:]
        for name in inputDescriptions.keys {
            if let value = preprocessorOutput.featureValue(for: name) {
                features[name] = value
                continue
            }
            if let fallback = originalInput.featureValue(for: name) {
                features[name] = fallback
                continue
            }

            let availableInputs = preprocessorOutput.featureNames.sorted().joined(separator: ", ")
            let fallbackInputs = originalInput.featureNames.sorted().joined(separator: ", ")
            throw ParakeetDecodeError.processingFailed(
                "Missing required encoder input: \(name). Available inputs: \(availableInputs), fallback inputs: \(fallbackInputs)"
            )
        }

        return try MLDictionaryFeatureProvider(dictionary: features)
    }

    private func frameAlignedAudio(_ audioSamples: [Float]) -> (samples: [Float], frameAlignedLength: Int) {
        let originalLength = audioSamples.count
        let frameAlignedCandidate =
            ((originalLength + ParakeetConstants.samplesPerEncoderFrame - 1)
             / ParakeetConstants.samplesPerEncoderFrame) * ParakeetConstants.samplesPerEncoderFrame

        if frameAlignedCandidate > originalLength && frameAlignedCandidate <= ParakeetConstants.maxModelSamples {
            let aligned = audioSamples + Array(repeating: 0, count: frameAlignedCandidate - originalLength)
            return (aligned, frameAlignedCandidate)
        }

        return (audioSamples, originalLength)
    }

    private func padAudioIfNeeded(_ audioSamples: [Float], targetLength: Int) -> [Float] {
        guard audioSamples.count < targetLength else { return audioSamples }
        return audioSamples + Array(repeating: 0, count: targetLength - audioSamples.count)
    }

}
