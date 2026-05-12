import AVFoundation
import Foundation
import VoxCore

actor MicrophoneRecorder {
    private let log = VoxLog.audio

    private var session: AVCaptureSession?
    private var output: AVCaptureAudioFileOutput?
    private var recordingDelegate: AudioFileRecordingDelegate?
    private var currentURL: URL?

    func start() throws -> URL {
        guard session == nil else {
            throw NSError(domain: "VoxService", code: 20, userInfo: [
                NSLocalizedDescriptionKey: "A recording is already in progress."
            ])
        }

        let device = try resolveInputDevice()
        let input = try AVCaptureDeviceInput(device: device)
        let output = AVCaptureAudioFileOutput()
        let session = AVCaptureSession()

        session.beginConfiguration()
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw NSError(domain: "VoxService", code: 23, userInfo: [
                NSLocalizedDescriptionKey: "Unable to use input device \(device.localizedName)."
            ])
        }
        session.addInput(input)

        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            throw NSError(domain: "VoxService", code: 24, userInfo: [
                NSLocalizedDescriptionKey: "Unable to create microphone recording output."
            ])
        }
        session.addOutput(output)
        session.commitConfiguration()

        let fileType = preferredOutputFileType(for: output)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vox-\(UUID().uuidString)")
            .appendingPathExtension(fileExtension(for: fileType))
        let delegate = AudioFileRecordingDelegate()

        session.startRunning()
        output.startRecording(to: url, outputFileType: fileType, recordingDelegate: delegate)

        self.session = session
        self.output = output
        self.recordingDelegate = delegate
        self.currentURL = url
        log.info("Recording started with \(device.localizedName): \(url.lastPathComponent)")
        return url
    }

    func stop() async throws -> URL {
        guard let session, let output, let recordingDelegate, let currentURL else {
            throw NSError(domain: "VoxService", code: 22, userInfo: [
                NSLocalizedDescriptionKey: "No recording is active."
            ])
        }

        output.stopRecording()
        let finishedURL = try await recordingDelegate.waitForFinish()
        session.stopRunning()
        self.session = nil
        self.output = nil
        self.recordingDelegate = nil
        self.currentURL = nil
        log.info("Recording stopped: \(currentURL.lastPathComponent)")
        return finishedURL
    }

    func cancel() {
        let current = currentURL
        output?.stopRecording()
        session?.stopRunning()
        session = nil
        output = nil
        recordingDelegate = nil
        currentURL = nil
        if let current {
            try? FileManager.default.removeItem(at: current)
            log.warning("Recording cancelled: \(current.lastPathComponent)")
        }
    }

    private func resolveInputDevice() throws -> AVCaptureDevice {
        let preferredID = (try? VoxPreferences.load())
            .flatMap { $0.speech.preferredInputDeviceId?.trimmingCharacters(in: .whitespacesAndNewlines) }
        let devices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        ).devices

        if let preferredID, !preferredID.isEmpty,
           let device = devices.first(where: { $0.uniqueID == preferredID }) {
            return device
        }

        if let device = AVCaptureDevice.default(for: .audio) ?? devices.first {
            return device
        }

        throw NSError(domain: "VoxService", code: 25, userInfo: [
            NSLocalizedDescriptionKey: "No microphone input device is available."
        ])
    }

    private func preferredOutputFileType(for output: AVCaptureAudioFileOutput) -> AVFileType {
        let fileTypes = AVCaptureAudioFileOutput.availableOutputFileTypes()
        if fileTypes.contains(.wav) {
            return .wav
        }
        if fileTypes.contains(.m4a) {
            return .m4a
        }
        return fileTypes.first ?? .wav
    }

    private func fileExtension(for fileType: AVFileType) -> String {
        switch fileType {
        case .wav:
            return "wav"
        case .m4a:
            return "m4a"
        case .aiff:
            return "aiff"
        default:
            return "caf"
        }
    }
}

private final class AudioFileRecordingDelegate: NSObject, AVCaptureFileOutputRecordingDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL, Error>?
    private var result: Result<URL, Error>?

    func waitForFinish() async throws -> URL {
        if let result = existingResult() {
            return try result.get()
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.lock.lock()
            if let result = self.result {
                self.lock.unlock()
                continuation.resume(with: result)
                return
            }
            self.continuation = continuation
            self.lock.unlock()
        }
    }

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        let result: Result<URL, Error> = if let error {
            .failure(error)
        } else {
            .success(outputFileURL)
        }

        lock.lock()
        if let continuation {
            self.continuation = nil
            lock.unlock()
            continuation.resume(with: result)
        } else {
            self.result = result
            lock.unlock()
        }
    }

    private func existingResult() -> Result<URL, Error>? {
        lock.lock()
        defer { lock.unlock() }
        return result
    }
}
