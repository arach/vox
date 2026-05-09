import Foundation

enum ParakeetConstants {
    static let sampleRate: Int = 16_000
    static let maxDurationSeconds: Double = 15.0
    static let maxModelSamples: Int = 240_000
    static let minimumAudioDurationSeconds: Double = 0.3
    static let melHopSize: Int = 160
    static let encoderSubsampling: Int = 8
    static let encoderHiddenSize: Int = 1024
    static let decoderHiddenSize: Int = 640
    static let samplesPerEncoderFrame: Int = melHopSize * encoderSubsampling
    static let secondsPerEncoderFrame: Double = Double(samplesPerEncoderFrame) / Double(sampleRate)
    static let highWERThreshold: Double = 0.15
    static let punctuationTokens: [Int] = [7883, 7952, 7948]
    static let standardOverlapFrames: Int = 25
    static let minConfidence: Float = 0.1
    static let maxConfidence: Float = 1.0

    static func calculateEncoderFrames(from samples: Int) -> Int {
        Int(ceil(Double(samples) / Double(samplesPerEncoderFrame)))
    }

    static func minimumRequiredSamples(forSampleRate sampleRate: Int) -> Int {
        Int(Double(sampleRate) * minimumAudioDurationSeconds)
    }
}
