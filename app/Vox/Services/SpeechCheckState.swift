import AVFoundation
import Foundation
import VoxBridge
import VoxCore
import VoxEngine

private enum SpeechCheckConfig {
    static let clientId = "vox-app-check"
    static let voiceSampleText = "Vox is running. This is the currently selected speech voice."
    static let defaultTranscriptionModelId = "parakeet:v3"
}

@MainActor
final class SpeechCheckState: ObservableObject {
    @Published var isRecording = false
    @Published var isBusy = false
    @Published var status = "Ready."
    @Published var transcriptText = ""
    @Published var lastRecordingURL: URL?
    @Published var lastTranscriptionMetrics: TranscriptionMetrics?
    @Published var lastSynthesisMetrics: SynthesisMetrics?

    private let proxy = DaemonProxy()
    private var audioPlayer: AVAudioPlayer?
    private var captureSession: AVCaptureSession?
    private var captureOutput: AVCaptureAudioFileOutput?
    private var recordingDelegate: SpeechCheckRecordingDelegate?
    private var recordingURL: URL?

    var voiceSampleText: String {
        SpeechCheckConfig.voiceSampleText
    }

    func refreshInputDevices(_ speechPreferences: SpeechPreferencesState) {
        speechPreferences.refreshInputDevices()
    }

    func startRecording(inputDeviceId: String) {
        guard !isRecording, !isBusy else { return }

        Task {
            do {
                try await requestMicrophoneAccess()
                try startCapture(inputDeviceId: inputDeviceId)
            } catch {
                status = error.localizedDescription
            }
        }
    }

    func stopAndTranscribe(modelId: String) {
        guard isRecording, !isBusy else { return }

        Task {
            await runBusyTask {
                self.status = "Finishing recording..."
                let url = try await self.stopCapture()
                self.lastRecordingURL = url
                self.status = "Transcribing..."
                try await self.ensureConnected()

                let resolvedModelId = modelId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? SpeechCheckConfig.defaultTranscriptionModelId
                    : modelId
                let result = try await self.proxy.call("transcribe.file", params: [
                    "path": url.path,
                    "modelId": resolvedModelId,
                    "clientId": SpeechCheckConfig.clientId
                ])

                self.transcriptText = (result["text"] as? String) ?? ""
                self.lastTranscriptionMetrics = self.parseTranscriptionMetrics(result["metrics"])
                let elapsedMs = self.intValue(result["elapsedMs"])
                let model = (result["modelId"] as? String) ?? resolvedModelId
                self.status = "Transcribed with \(model) in \(elapsedMs)ms."
            } onError: { error in
                self.status = error.localizedDescription
                self.resetCapture()
            }
        }
    }

    func cancelRecording() {
        guard isRecording else { return }
        resetCapture(removeFile: true)
        status = "Recording cancelled."
    }

    func playVoiceSample(modelId: String, voiceId: String?) {
        guard !isBusy else { return }

        Task {
            await runBusyTask {
                let resolvedModelId = modelId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? TTSDefaults.modelId
                    : modelId
                var params: [String: Any] = [
                    "text": SpeechCheckConfig.voiceSampleText,
                    "modelId": resolvedModelId,
                    "format": TTSDefaults.format,
                    "clientId": SpeechCheckConfig.clientId
                ]
                if let voiceId, !voiceId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    params["voiceId"] = voiceId
                }

                self.status = "Synthesizing voice check..."
                try await self.ensureConnected()
                let result = try await self.proxy.call("synthesize.generate", params: params)

                guard let audioBase64 = result["audioBase64"] as? String,
                      let audioData = Data(base64Encoded: audioBase64)
                else {
                    throw NSError(domain: "VoxApp", code: 41, userInfo: [
                        NSLocalizedDescriptionKey: "Synthesis returned no audio."
                    ])
                }

                let player = try AVAudioPlayer(data: audioData)
                player.prepareToPlay()
                player.play()
                self.audioPlayer = player

                self.lastSynthesisMetrics = self.parseSynthesisMetrics(result["metrics"])
                let voice = (result["voiceId"] as? String) ?? voiceId ?? "provider default"
                self.status = "Playing \(voice)."
            } onError: { error in
                self.status = error.localizedDescription
            }
        }
    }

    private func requestMicrophoneAccess() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            if granted {
                return
            }
            fallthrough
        case .denied, .restricted:
            throw NSError(domain: "VoxApp", code: 40, userInfo: [
                NSLocalizedDescriptionKey: "Microphone access is not allowed for Vox."
            ])
        @unknown default:
            throw NSError(domain: "VoxApp", code: 40, userInfo: [
                NSLocalizedDescriptionKey: "Microphone access is unavailable."
            ])
        }
    }

    private func startCapture(inputDeviceId: String) throws {
        let device = try resolveInputDevice(inputDeviceId: inputDeviceId)
        let input = try AVCaptureDeviceInput(device: device)
        let output = AVCaptureAudioFileOutput()
        let session = AVCaptureSession()

        session.beginConfiguration()
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw NSError(domain: "VoxApp", code: 42, userInfo: [
                NSLocalizedDescriptionKey: "Unable to use input device \(device.localizedName)."
            ])
        }
        session.addInput(input)

        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            throw NSError(domain: "VoxApp", code: 43, userInfo: [
                NSLocalizedDescriptionKey: "Unable to create microphone recording output."
            ])
        }
        session.addOutput(output)
        session.commitConfiguration()

        let fileType = preferredOutputFileType(for: output)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vox-check-\(UUID().uuidString)")
            .appendingPathExtension(fileExtension(for: fileType))
        let delegate = SpeechCheckRecordingDelegate()

        session.startRunning()
        output.startRecording(to: url, outputFileType: fileType, recordingDelegate: delegate)

        captureSession = session
        captureOutput = output
        recordingDelegate = delegate
        recordingURL = url
        isRecording = true
        transcriptText = ""
        lastTranscriptionMetrics = nil
        status = "Recording with \(device.localizedName)..."
    }

    private func stopCapture() async throws -> URL {
        guard let output = captureOutput, let recordingDelegate else {
            throw NSError(domain: "VoxApp", code: 44, userInfo: [
                NSLocalizedDescriptionKey: "No recording is active."
            ])
        }

        output.stopRecording()
        let url = try await recordingDelegate.waitForFinish()
        resetCapture(removeFile: false, stopOutput: false)
        return url
    }

    private func resetCapture(removeFile: Bool = false, stopOutput: Bool = true) {
        let url = recordingURL
        if stopOutput {
            captureOutput?.stopRecording()
        }
        captureSession?.stopRunning()
        captureSession = nil
        captureOutput = nil
        recordingDelegate = nil
        recordingURL = nil
        isRecording = false
        if removeFile, let url {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func resolveInputDevice(inputDeviceId: String) throws -> AVCaptureDevice {
        let devices = audioInputDevices()
        let trimmed = inputDeviceId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, let device = devices.first(where: { $0.uniqueID == trimmed }) {
            return device
        }
        if let device = AVCaptureDevice.default(for: .audio) ?? devices.first {
            return device
        }
        throw NSError(domain: "VoxApp", code: 45, userInfo: [
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

    private func audioInputDevices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        ).devices
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

    private func ensureConnected() async throws {
        if !(await proxy.isConnected) {
            try await proxy.connect()
        }
    }

    private func runBusyTask(
        operation: @escaping @MainActor () async throws -> Void,
        onError: @escaping @MainActor (Error) -> Void
    ) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        do {
            try await operation()
        } catch {
            onError(error)
        }
    }

    private func parseTranscriptionMetrics(_ raw: Any?) -> TranscriptionMetrics? {
        decode(TranscriptionMetrics.self, from: raw)
    }

    private func parseSynthesisMetrics(_ raw: Any?) -> SynthesisMetrics? {
        decode(SynthesisMetrics.self, from: raw)
    }

    private func decode<T: Decodable>(_ type: T.Type, from raw: Any?) -> T? {
        guard let raw, JSONSerialization.isValidJSONObject(raw),
              let data = try? JSONSerialization.data(withJSONObject: raw)
        else {
            return nil
        }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func intValue(_ raw: Any?) -> Int {
        if let value = raw as? Int {
            return value
        }
        if let value = raw as? NSNumber {
            return value.intValue
        }
        return 0
    }
}

private final class SpeechCheckRecordingDelegate: NSObject, AVCaptureFileOutputRecordingDelegate, @unchecked Sendable {
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
