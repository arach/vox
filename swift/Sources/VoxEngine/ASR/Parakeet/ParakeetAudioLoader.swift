@preconcurrency import AVFoundation
import Foundation
import os

struct ParakeetAudioInput: Sendable {
    let samples: [Float]
    let inputBytes: Int
    let audioDurationMs: Int
    let audioLoadMs: Int
}

struct ParakeetAudioLoader: Sendable {
    private static let targetSampleRate: Double = 16_000
    private static let chunkFrameCount: AVAudioFrameCount = 4096

    private let targetFormat: AVAudioFormat

    init() {
        self.targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.targetSampleRate,
            channels: 1,
            interleaved: false
        )!
    }

    func load(from url: URL) throws -> ParakeetAudioInput {
        let inputBytes = ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue) ?? 0
        let startedAt = CFAbsoluteTimeGetCurrent()
        let audioFile = try AVAudioFile(forReading: url)
        let format = audioFile.processingFormat
        let audioDurationMs = Int((Double(audioFile.length) / format.sampleRate) * 1000)

        var samples: [Float] = []
        samples.reserveCapacity(estimatedOutputSampleCount(frameCount: Int(audioFile.length), sampleRate: format.sampleRate))

        while audioFile.framePosition < audioFile.length {
            let remainingFrames = Int(audioFile.length - audioFile.framePosition)
            let framesToRead = AVAudioFrameCount(min(Int(Self.chunkFrameCount), remainingFrames))
            guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: framesToRead) else {
                throw NSError(domain: "VoxEngine", code: 107, userInfo: [
                    NSLocalizedDescriptionKey: "Failed to allocate input audio buffer."
                ])
            }

            try audioFile.read(into: inputBuffer)
            guard inputBuffer.frameLength > 0 else {
                break
            }

            let converted = try convert(buffer: inputBuffer, from: format)
            samples.append(contentsOf: converted)
        }

        let audioLoadMs = Int((CFAbsoluteTimeGetCurrent() - startedAt) * 1000)

        return ParakeetAudioInput(
            samples: samples,
            inputBytes: inputBytes,
            audioDurationMs: audioDurationMs,
            audioLoadMs: audioLoadMs
        )
    }

    private func convert(buffer: AVAudioPCMBuffer, from inputFormat: AVAudioFormat) throws -> [Float] {
        if isTargetFormat(inputFormat) {
            return try extractFloatSamples(from: buffer)
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw NSError(domain: "VoxEngine", code: 108, userInfo: [
                NSLocalizedDescriptionKey: "Failed to create audio converter."
            ])
        }

        let ratio = targetFormat.sampleRate / inputFormat.sampleRate
        let estimatedFrames = AVAudioFrameCount(ceil(Double(buffer.frameLength) * ratio)) + 32
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: max(estimatedFrames, 1)
        ) else {
            throw NSError(domain: "VoxEngine", code: 109, userInfo: [
                NSLocalizedDescriptionKey: "Failed to allocate output audio buffer."
            ])
        }

        let didProvideInput = OSAllocatedUnfairLock(initialState: false)
        let inputBlock: AVAudioConverterInputBlock = { _, status in
            let wasProvided = didProvideInput.withLock { state -> Bool in
                if state { return true }
                state = true
                return false
            }

            if !wasProvided {
                status.pointee = .haveData
                return buffer
            }

            status.pointee = .endOfStream
            return nil
        }

        var conversionError: NSError?
        let status = converter.convert(to: outputBuffer, error: &conversionError, withInputFrom: inputBlock)
        if status == .error {
            throw conversionError ?? NSError(domain: "VoxEngine", code: 110, userInfo: [
                NSLocalizedDescriptionKey: "Audio conversion failed."
            ])
        }

        return try extractFloatSamples(from: outputBuffer)
    }

    private func extractFloatSamples(from buffer: AVAudioPCMBuffer) throws -> [Float] {
        guard
            buffer.format.commonFormat == .pcmFormatFloat32,
            buffer.format.channelCount == 1,
            !buffer.format.isInterleaved,
            let channelData = buffer.floatChannelData
        else {
            throw NSError(domain: "VoxEngine", code: 111, userInfo: [
                NSLocalizedDescriptionKey: "Expected mono Float32 PCM audio after conversion."
            ])
        }

        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else {
            return []
        }

        return Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))
    }

    private func isTargetFormat(_ format: AVAudioFormat) -> Bool {
        format.commonFormat == .pcmFormatFloat32
            && format.channelCount == 1
            && !format.isInterleaved
            && format.sampleRate == targetFormat.sampleRate
    }

    private func estimatedOutputSampleCount(frameCount: Int, sampleRate: Double) -> Int {
        Int(ceil(Double(frameCount) * (Self.targetSampleRate / sampleRate)))
    }
}
