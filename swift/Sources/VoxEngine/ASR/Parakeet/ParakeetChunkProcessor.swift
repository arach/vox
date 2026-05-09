import Foundation

struct ParakeetChunkProcessor {
    let audioSamples: [Float]
    let transcriberFactory: @Sendable () -> ParakeetSingleChunkTranscriber
    let workerCount: Int
    let overlapSeconds: Double

    private let melContextSamples: Int = ParakeetConstants.samplesPerEncoderFrame

    init(
        audioSamples: [Float],
        workerCount: Int = max(1, ParakeetInferenceConfig.default.parallelChunkConcurrency),
        overlapSeconds: Double = 2.0,
        transcriberFactory: @escaping @Sendable () -> ParakeetSingleChunkTranscriber
    ) {
        self.audioSamples = audioSamples
        self.workerCount = max(1, workerCount)
        self.overlapSeconds = overlapSeconds
        self.transcriberFactory = transcriberFactory
    }

    private var chunkSamples: Int {
        let maxActualChunk = ParakeetConstants.maxModelSamples - melContextSamples
        let raw = max(maxActualChunk - ParakeetConstants.melHopSize, ParakeetConstants.samplesPerEncoderFrame)
        return raw / ParakeetConstants.samplesPerEncoderFrame * ParakeetConstants.samplesPerEncoderFrame
    }

    private var overlapSamples: Int {
        let requested = Int(overlapSeconds * Double(ParakeetConstants.sampleRate))
        let capped = min(requested, chunkSamples / 2)
        return capped / ParakeetConstants.samplesPerEncoderFrame * ParakeetConstants.samplesPerEncoderFrame
    }

    private var strideSamples: Int {
        let raw = max(chunkSamples - overlapSamples, ParakeetConstants.samplesPerEncoderFrame)
        return raw / ParakeetConstants.samplesPerEncoderFrame * ParakeetConstants.samplesPerEncoderFrame
    }

    func process() async throws -> ParakeetInferenceResult {
        guard !audioSamples.isEmpty else {
            return ParakeetInferenceResult(text: "", words: [])
        }

        let workers = (0..<workerCount).map { _ in transcriberFactory() }
        struct TaskResult: Sendable {
            let index: Int
            let tokens: [ParakeetChunkToken]
            let workerIndex: Int
        }

        var chunkOutputs: [[ParakeetChunkToken]?] = []
        var availableWorkers = Array(workers.indices)
        var inFlight = 0
        var chunkStart = 0
        var chunkIndex = 0

        func collectNextResult(_ group: inout ThrowingTaskGroup<TaskResult, Error>) async throws {
            guard inFlight > 0 else { return }
            guard let finished = try await group.next() else { return }
            chunkOutputs[finished.index] = finished.tokens
            availableWorkers.append(finished.workerIndex)
            inFlight -= 1
        }

        try await withThrowingTaskGroup(of: TaskResult.self) { group in
            while chunkStart < audioSamples.count {
                try Task.checkCancellation()
                let candidateEnd = chunkStart + chunkSamples
                let isLastChunk = candidateEnd >= audioSamples.count
                let chunkEnd = isLastChunk ? audioSamples.count : candidateEnd
                if chunkEnd <= chunkStart {
                    break
                }

                let contextSamples = chunkIndex > 0 ? melContextSamples : 0
                let contextStart = chunkStart - contextSamples
                let chunkSlice = Array(audioSamples[contextStart..<chunkEnd])

                if availableWorkers.isEmpty {
                    try await collectNextResult(&group)
                }
                if availableWorkers.isEmpty {
                    availableWorkers.append(0)
                }

                let workerIndex = availableWorkers.removeFirst()
                let worker = workers[workerIndex]
                let index = chunkIndex
                let chunkStartOffset = chunkStart
                chunkOutputs.append(nil)

                group.addTask {
                    let chunkResult = try await worker.transcribeChunk(
                        samples: chunkSlice,
                        contextSamples: contextSamples,
                        chunkStart: chunkStartOffset,
                        isLastChunk: isLastChunk
                    )
                    return TaskResult(index: index, tokens: chunkResult.tokens, workerIndex: workerIndex)
                }
                inFlight += 1
                chunkIndex += 1

                if isLastChunk {
                    break
                }

                chunkStart += strideSamples
                if availableWorkers.isEmpty && inFlight > 0 {
                    try await collectNextResult(&group)
                }
            }

            while inFlight > 0 {
                try Task.checkCancellation()
                try await collectNextResult(&group)
            }
        }

        let orderedChunkOutputs = chunkOutputs.compactMap { $0 }
        guard var mergedTokens = orderedChunkOutputs.first else {
            return ParakeetInferenceResult(text: "", words: [])
        }

        let merger = ParakeetChunkMerger(overlapSeconds: overlapSeconds)
        for chunk in orderedChunkOutputs.dropFirst() {
            mergedTokens = merger.merge(mergedTokens, chunk)
        }

        if mergedTokens.count > 1 {
            mergedTokens.sort { $0.timestamp < $1.timestamp }
        }

        let tokenIDs = mergedTokens.map(\.token)
        let timestamps = mergedTokens.map(\.timestamp)
        let confidences = mergedTokens.map(\.confidence)
        let durations = mergedTokens.map(\.duration)
        let vocabulary = workers[0].vocabulary

        return ParakeetInferenceResult(
            text: ParakeetTextProcessing.convertTokensToText(tokenIDs, vocabulary: vocabulary),
            words: ParakeetTextProcessing.createWordTimings(
                tokenIds: tokenIDs,
                timestamps: timestamps,
                confidences: confidences,
                tokenDurations: durations,
                vocabulary: vocabulary
            )
        )
    }
}
