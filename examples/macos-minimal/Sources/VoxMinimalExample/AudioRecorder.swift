import AVFoundation
import Foundation

struct RecordedClip: Sendable {
    let url: URL
    let duration: TimeInterval
}

@MainActor
final class AudioRecorder: NSObject {
    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?

    var isRecording: Bool {
        recorder?.isRecording == true
    }

    static func authorizationStatus() async -> AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    static func requestMicrophoneAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    static func statusMessage(for status: AVAuthorizationStatus) -> String {
        switch status {
        case .authorized:
            return "Microphone ready."
        case .notDetermined:
            return "Request microphone access to record."
        case .denied:
            return "Microphone access is denied. Enable it in System Settings."
        case .restricted:
            return "Microphone access is restricted."
        @unknown default:
            return "Microphone access is unavailable."
        }
    }

    func start() throws -> URL {
        guard !isRecording else {
            throw AudioRecorderError.alreadyRecording
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vox-minimal-\(UUID().uuidString)")
            .appendingPathExtension("wav")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16_000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]

        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.delegate = self
        recorder.prepareToRecord()
        guard recorder.record() else {
            throw AudioRecorderError.couldNotStart
        }

        self.recorder = recorder
        recordingURL = url
        return url
    }

    func stop() -> RecordedClip? {
        guard let recorder, let recordingURL else { return nil }

        let duration = recorder.currentTime
        recorder.stop()
        self.recorder = nil
        self.recordingURL = nil
        return RecordedClip(url: recordingURL, duration: duration)
    }
}

extension AudioRecorder: AVAudioRecorderDelegate {}

enum AudioRecorderError: LocalizedError {
    case alreadyRecording
    case couldNotStart

    var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            return "Already recording."
        case .couldNotStart:
            return "Could not start recording."
        }
    }
}
