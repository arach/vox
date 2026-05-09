@preconcurrency import CoreML
import Foundation

struct ParakeetDecoderV3: Sendable {
    private let config: ParakeetInferenceConfig
    private let modelInference = ParakeetModelInference()

    init(config: ParakeetInferenceConfig = .default) {
        self.config = config
    }

    func decodeWithTimings(
        encoderOutput: MLMultiArray,
        encoderSequenceLength: Int,
        actualAudioFrames: Int,
        decoderModel: MLModel,
        jointModel: MLModel,
        decoderState: inout ParakeetDecoderState,
        contextFrameAdjustment: Int = 0,
        isLastChunk: Bool = false,
        globalFrameOffset: Int = 0,
        language: ParakeetLanguage? = nil,
        vocabulary: [Int: String]? = nil
    ) async throws -> ParakeetHypothesis {
        guard encoderSequenceLength > 1 else {
            return ParakeetHypothesis(decoderState: decoderState)
        }

        let needsTopK = language != nil
        let encoderFrames = try ParakeetEncoderFrameView(
            encoderOutput: encoderOutput,
            validLength: encoderSequenceLength,
            expectedHiddenSize: config.encoderHiddenSize
        )

        var hypothesis = ParakeetHypothesis(decoderState: decoderState)
        hypothesis.lastToken = decoderState.lastToken

        var timeIndices = ParakeetFrameNavigation.calculateInitialTimeIndices(
            timeJump: decoderState.timeJump,
            contextFrameAdjustment: contextFrameAdjustment
        )
        let navigationState = ParakeetFrameNavigation.initializeNavigationState(
            timeIndices: timeIndices,
            encoderSequenceLength: encoderSequenceLength,
            actualAudioFrames: actualAudioFrames
        )
        let effectiveSequenceLength = navigationState.effectiveSequenceLength
        var safeTimeIndices = navigationState.safeTimeIndices
        let lastTimestep = navigationState.lastTimestep
        var activeMask = navigationState.activeMask
        var timeIndicesCurrentLabels = timeIndices

        if timeIndices >= effectiveSequenceLength {
            return ParakeetHypothesis(decoderState: decoderState)
        }

        let reusableTargetArray = try MLMultiArray(shape: [1, 1] as [NSNumber], dataType: .int32)
        let reusableTargetLengthArray = try MLMultiArray(shape: [1] as [NSNumber], dataType: .int32)
        reusableTargetLengthArray[0] = NSNumber(value: 1)

        let reusableEncoderStep = try ParakeetCoreMLSupport.createAlignedArray(
            shape: [1, NSNumber(value: config.encoderHiddenSize), 1],
            dataType: .float32
        )
        let reusableDecoderStep = try ParakeetCoreMLSupport.createAlignedArray(
            shape: [1, NSNumber(value: ParakeetConstants.decoderHiddenSize), 1],
            dataType: .float32
        )
        let jointInput = ParakeetReusableJointInputProvider(
            encoderStep: reusableEncoderStep,
            decoderStep: reusableDecoderStep
        )
        let encoderDestinationStride = reusableEncoderStep.strides.map(\.intValue)[1]
        let encoderDestinationPointer = reusableEncoderStep.dataPointer.bindMemory(
            to: Float.self,
            capacity: config.encoderHiddenSize
        )

        let tokenIdBacking = try MLMultiArray(shape: [1, 1, 1] as [NSNumber], dataType: .int32)
        let tokenProbBacking = try MLMultiArray(shape: [1, 1, 1] as [NSNumber], dataType: .float32)
        let durationBacking = try MLMultiArray(shape: [1, 1, 1] as [NSNumber], dataType: .int32)

        if decoderState.lastToken == nil && decoderState.predictorOutput == nil {
            decoderState.hiddenState.resetData(to: 0)
            decoderState.cellState.resetData(to: 0)
        }

        if decoderState.predictorOutput == nil && hypothesis.lastToken == nil {
            let startOfSequence = config.tdtConfig.blankId
            let primed = try modelInference.runDecoder(
                token: startOfSequence,
                state: decoderState,
                model: decoderModel,
                targetArray: reusableTargetArray,
                targetLengthArray: reusableTargetLengthArray
            )
            let projection = try ParakeetCoreMLSupport.extractFeatureValue(
                from: primed.output,
                key: "decoder",
                errorMessage: "Invalid decoder output"
            )
            decoderState.predictorOutput = projection
            hypothesis.decoderState = primed.newState
        }

        var lastEmissionTimestamp = -1
        var emissionsAtThisTimestamp = 0
        let maxSymbolsPerStep = config.tdtConfig.maxSymbolsPerStep
        var tokensProcessedThisChunk = 0

        while activeMask {
            try Task.checkCancellation()
            var label = hypothesis.lastToken ?? config.tdtConfig.blankId
            let stateToUse = hypothesis.decoderState ?? decoderState

            let decoderResult: (output: MLFeatureProvider, newState: ParakeetDecoderState)
            if let cached = decoderState.predictorOutput {
                let provider = try MLDictionaryFeatureProvider(dictionary: [
                    "decoder": MLFeatureValue(multiArray: cached)
                ])
                decoderResult = (output: provider, newState: stateToUse)
            } else {
                decoderResult = try modelInference.runDecoder(
                    token: label,
                    state: stateToUse,
                    model: decoderModel,
                    targetArray: reusableTargetArray,
                    targetLengthArray: reusableTargetLengthArray
                )
            }

            let decoderProjection = try ParakeetCoreMLSupport.extractFeatureValue(
                from: decoderResult.output,
                key: "decoder",
                errorMessage: "Invalid decoder output"
            )
            try modelInference.normalizeDecoderProjection(decoderProjection, into: reusableDecoderStep)

            let decision = try modelInference.runJointPrepared(
                encoderFrames: encoderFrames,
                timeIndex: safeTimeIndices,
                preparedDecoderStep: reusableDecoderStep,
                model: jointModel,
                encoderStep: reusableEncoderStep,
                encoderDestPtr: encoderDestinationPointer,
                encoderDestStride: encoderDestinationStride,
                inputProvider: jointInput,
                tokenIdBacking: tokenIdBacking,
                tokenProbBacking: tokenProbBacking,
                durationBacking: durationBacking,
                needsTopK: needsTopK
            )

            label = decision.token
            var score = ParakeetDurationMapping.clampProbability(decision.probability)
            let blankID = config.tdtConfig.blankId

            Self.tokenLanguageFilter(
                label: &label,
                score: &score,
                topKIds: decision.topKIds,
                topKLogits: decision.topKLogits,
                language: language,
                vocabulary: vocabulary,
                blankId: blankID
            )

            var duration = try ParakeetDurationMapping.mapDurationBin(
                decision.durationBin,
                durationBins: config.tdtConfig.durationBins
            )
            var blankMask = (label == blankID)
            let currentTimeIndex = timeIndices

            if !blankMask && duration == 0
                && currentTimeIndex == lastEmissionTimestamp
                && emissionsAtThisTimestamp >= 1 {
                duration = 1
            }

            if blankMask && duration == 0 {
                duration = 1
            }

            timeIndicesCurrentLabels = timeIndices
            timeIndices += duration
            safeTimeIndices = min(timeIndices, lastTimestep)
            activeMask = timeIndices < effectiveSequenceLength
            var advanceMask = activeMask && blankMask

            while advanceMask {
                try Task.checkCancellation()
                timeIndicesCurrentLabels = timeIndices

                let innerDecision = try modelInference.runJointPrepared(
                    encoderFrames: encoderFrames,
                    timeIndex: safeTimeIndices,
                    preparedDecoderStep: reusableDecoderStep,
                    model: jointModel,
                    encoderStep: reusableEncoderStep,
                    encoderDestPtr: encoderDestinationPointer,
                    encoderDestStride: encoderDestinationStride,
                    inputProvider: jointInput,
                    tokenIdBacking: tokenIdBacking,
                    tokenProbBacking: tokenProbBacking,
                    durationBacking: durationBacking,
                    needsTopK: needsTopK
                )

                label = innerDecision.token
                score = ParakeetDurationMapping.clampProbability(innerDecision.probability)

                Self.tokenLanguageFilter(
                    label: &label,
                    score: &score,
                    topKIds: innerDecision.topKIds,
                    topKLogits: innerDecision.topKLogits,
                    language: language,
                    vocabulary: vocabulary,
                    blankId: blankID
                )

                duration = try ParakeetDurationMapping.mapDurationBin(
                    innerDecision.durationBin,
                    durationBins: config.tdtConfig.durationBins
                )
                blankMask = (label == blankID)
                if blankMask && duration == 0 {
                    duration = 1
                }

                timeIndices += duration
                safeTimeIndices = min(timeIndices, lastTimestep)
                activeMask = timeIndices < effectiveSequenceLength
                advanceMask = activeMask && blankMask
            }

            if activeMask && label != blankID {
                tokensProcessedThisChunk += 1
                if tokensProcessedThisChunk > config.tdtConfig.maxTokensPerChunk {
                    break
                }

                hypothesis.tokenIDs.append(label)
                hypothesis.score += score
                hypothesis.timestamps.append(timeIndicesCurrentLabels + globalFrameOffset)
                hypothesis.tokenConfidences.append(score)
                hypothesis.tokenDurations.append(duration)
                hypothesis.lastToken = label

                let step = try modelInference.runDecoder(
                    token: label,
                    state: decoderResult.newState,
                    model: decoderModel,
                    targetArray: reusableTargetArray,
                    targetLengthArray: reusableTargetLengthArray
                )
                hypothesis.decoderState = step.newState
                decoderState.predictorOutput = try ParakeetCoreMLSupport.extractFeatureValue(
                    from: step.output,
                    key: "decoder",
                    errorMessage: "Invalid decoder output"
                )

                if timeIndicesCurrentLabels == lastEmissionTimestamp {
                    emissionsAtThisTimestamp += 1
                } else {
                    lastEmissionTimestamp = timeIndicesCurrentLabels
                    emissionsAtThisTimestamp = 1
                }

                if emissionsAtThisTimestamp >= maxSymbolsPerStep {
                    timeIndices = min(timeIndices + 1, lastTimestep)
                    safeTimeIndices = min(timeIndices, lastTimestep)
                    emissionsAtThisTimestamp = 0
                    lastEmissionTimestamp = -1
                }
            }

            activeMask = timeIndices < effectiveSequenceLength
        }

        if isLastChunk {
            var additionalSteps = 0
            var consecutiveBlanks = 0
            let maxConsecutiveBlanks = config.tdtConfig.consecutiveBlankLimit
            var lastToken = hypothesis.lastToken ?? config.tdtConfig.blankId
            var finalProcessingTimeIndices = timeIndices

            while additionalSteps < maxSymbolsPerStep && consecutiveBlanks < maxConsecutiveBlanks {
                try Task.checkCancellation()
                let stateToUse = hypothesis.decoderState ?? decoderState

                let decoderResult: (output: MLFeatureProvider, newState: ParakeetDecoderState)
                if let cached = decoderState.predictorOutput {
                    let provider = try MLDictionaryFeatureProvider(dictionary: [
                        "decoder": MLFeatureValue(multiArray: cached)
                    ])
                    decoderResult = (output: provider, newState: stateToUse)
                } else {
                    decoderResult = try modelInference.runDecoder(
                        token: lastToken,
                        state: stateToUse,
                        model: decoderModel,
                        targetArray: reusableTargetArray,
                        targetLengthArray: reusableTargetLengthArray
                    )
                }

                let frameVariations = [
                    min(finalProcessingTimeIndices, encoderFrames.count - 1),
                    min(effectiveSequenceLength - 1, encoderFrames.count - 1),
                    min(max(0, effectiveSequenceLength - 2), encoderFrames.count - 1),
                ]
                let frameIndex = frameVariations[additionalSteps % frameVariations.count]
                let finalProjection = try ParakeetCoreMLSupport.extractFeatureValue(
                    from: decoderResult.output,
                    key: "decoder",
                    errorMessage: "Invalid decoder output"
                )
                try modelInference.normalizeDecoderProjection(finalProjection, into: reusableDecoderStep)

                let decision = try modelInference.runJointPrepared(
                    encoderFrames: encoderFrames,
                    timeIndex: frameIndex,
                    preparedDecoderStep: reusableDecoderStep,
                    model: jointModel,
                    encoderStep: reusableEncoderStep,
                    encoderDestPtr: encoderDestinationPointer,
                    encoderDestStride: encoderDestinationStride,
                    inputProvider: jointInput,
                    tokenIdBacking: tokenIdBacking,
                    tokenProbBacking: tokenProbBacking,
                    durationBacking: durationBacking,
                    needsTopK: needsTopK
                )

                let token = decision.token
                let score = ParakeetDurationMapping.clampProbability(decision.probability)
                let duration = try ParakeetDurationMapping.mapDurationBin(
                    decision.durationBin,
                    durationBins: config.tdtConfig.durationBins
                )

                if token == config.tdtConfig.blankId {
                    consecutiveBlanks += 1
                } else {
                    consecutiveBlanks = 0
                    hypothesis.tokenIDs.append(token)
                    hypothesis.score += score
                    let finalTimestamp = min(finalProcessingTimeIndices, effectiveSequenceLength - 1) + globalFrameOffset
                    hypothesis.timestamps.append(finalTimestamp)
                    hypothesis.tokenConfidences.append(score)
                    hypothesis.tokenDurations.append(duration)
                    hypothesis.lastToken = token

                    let step = try modelInference.runDecoder(
                        token: token,
                        state: decoderResult.newState,
                        model: decoderModel,
                        targetArray: reusableTargetArray,
                        targetLengthArray: reusableTargetLengthArray
                    )
                    hypothesis.decoderState = step.newState
                    decoderState.predictorOutput = try ParakeetCoreMLSupport.extractFeatureValue(
                        from: step.output,
                        key: "decoder",
                        errorMessage: "Invalid decoder output"
                    )
                    lastToken = token
                }

                finalProcessingTimeIndices = min(finalProcessingTimeIndices + max(1, duration), effectiveSequenceLength)
                additionalSteps += 1
            }

            decoderState.finalizeLastChunk()
        }

        if let finalState = hypothesis.decoderState {
            decoderState = finalState
        }
        decoderState.lastToken = hypothesis.lastToken

        if let lastToken = hypothesis.lastToken,
           ParakeetConstants.punctuationTokens.contains(lastToken) {
            decoderState.predictorOutput = nil
        }

        decoderState.timeJump = ParakeetFrameNavigation.calculateFinalTimeJump(
            currentTimeIndices: timeIndices,
            effectiveSequenceLength: effectiveSequenceLength,
            isLastChunk: isLastChunk
        )

        return hypothesis
    }

    private static func tokenLanguageFilter(
        label: inout Int,
        score: inout Float,
        topKIds: [Int]?,
        topKLogits: [Float]?,
        language: ParakeetLanguage?,
        vocabulary: [Int: String]?,
        blankId: Int
    ) {
        guard label != blankId,
              let language,
              let vocabulary,
              let topKIds,
              let topKLogits,
              !topKIds.isEmpty,
              let tokenText = vocabulary[label],
              !ParakeetTokenLanguageFilter.matches(tokenText, script: language.script),
              let filtered = ParakeetTokenLanguageFilter.filterTopK(
                topKIds: topKIds,
                topKLogits: topKLogits,
                vocabulary: vocabulary,
                preferredScript: language.script
              ) else {
            return
        }

        label = filtered.tokenId
        score = ParakeetDurationMapping.clampProbability(filtered.probability)
    }
}
