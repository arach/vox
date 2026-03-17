import AVFoundation
import Foundation
import VoxCore

actor MicrophoneRecorder {
    private let log = VoxLog.audio
    private let settings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatLinearPCM),
        AVSampleRateKey: 16_000.0,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 32,
        AVLinearPCMIsFloatKey: true,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false
    ]

    private var recorder: AVAudioRecorder?
    private var currentURL: URL?

    func start() throws -> URL {
        guard recorder == nil else {
            throw NSError(domain: "VoxService", code: 20, userInfo: [
                NSLocalizedDescriptionKey: "A recording is already in progress."
            ])
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vox-\(UUID().uuidString)")
            .appendingPathExtension("wav")

        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.prepareToRecord()

        guard recorder.record() else {
            throw NSError(domain: "VoxService", code: 21, userInfo: [
                NSLocalizedDescriptionKey: "Unable to start microphone recording."
            ])
        }

        self.recorder = recorder
        self.currentURL = url
        log.info("Recording started: \(url.lastPathComponent, privacy: .public)")
        return url
    }

    func stop() throws -> URL {
        guard let recorder, let currentURL else {
            throw NSError(domain: "VoxService", code: 22, userInfo: [
                NSLocalizedDescriptionKey: "No recording is active."
            ])
        }

        recorder.stop()
        self.recorder = nil
        self.currentURL = nil
        return currentURL
    }

    func cancel() {
        recorder?.stop()
        recorder = nil
        if let currentURL {
            try? FileManager.default.removeItem(at: currentURL)
        }
        self.currentURL = nil
    }
}
