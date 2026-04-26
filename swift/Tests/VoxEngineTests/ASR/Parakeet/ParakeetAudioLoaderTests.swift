import AVFoundation
import Foundation
import Testing
@testable import VoxEngine

struct ParakeetAudioLoaderTests {
    @Test("Parakeet audio loader resamples files to 16kHz mono float samples")
    func resamplesAudioFileToTargetFormat() throws {
        let fileURL = try makeTestAudioFile(sampleRate: 48_000, durationSeconds: 0.5)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let loader = ParakeetAudioLoader()
        let input = try loader.load(from: fileURL)

        #expect(input.inputBytes > 0)
        #expect(input.audioDurationMs >= 490)
        #expect(input.audioDurationMs <= 510)
        #expect(input.samples.count >= 7_950)
        #expect(input.samples.count <= 8_050)
    }

    @Test("Parakeet sample preparer pads clips shorter than the minimum demo duration")
    func padsShortClipsToMinimumDuration() {
        let original = Array(repeating: Float(0.25), count: 8_000)

        let prepared = ParakeetSamplePreparer.ensureMinimumDuration(samples: original)

        #expect(prepared.wasPadded)
        #expect(prepared.samples.count == 24_000)
        #expect(prepared.samples.prefix(3) == original.prefix(3))
    }
}

private func makeTestAudioFile(sampleRate: Double, durationSeconds: Double) throws -> URL {
    let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: sampleRate,
        channels: 1,
        interleaved: false
    )!
    let frameCount = AVAudioFrameCount((sampleRate * durationSeconds).rounded(.up))
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
        throw NSError(domain: "VoxEngineTests", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Failed to allocate test audio buffer."
        ])
    }

    buffer.frameLength = frameCount
    if let channelData = buffer.floatChannelData {
        for frame in 0..<Int(frameCount) {
            let sample = sinf(Float(frame) * 2 * .pi * 440 / Float(sampleRate))
            channelData[0][frame] = sample
        }
    }

    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("wav")
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    try file.write(from: buffer)
    return url
}
