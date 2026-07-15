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
    @Published var synthesisText = SpeechCheckConfig.voiceSampleText
    @Published var lastRecordingURL: URL?
    @Published var lastTranscriptionMetrics: TranscriptionMetrics?
    @Published var lastSynthesisMetrics: SynthesisMetrics?

    private let proxy = DaemonProxy()
    private let recorder = MicrophoneFileRecorder()
    private var audioPlayer: AVAudioPlayer?

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
                let recording = try await recorder.start(
                    preferredInputDeviceID: inputDeviceId,
                    filePrefix: "vox-check"
                )
                isRecording = true
                transcriptText = ""
                lastTranscriptionMetrics = nil
                status = "Recording with \(recording.inputDevice.name)..."
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
        resetCapture()
        status = "Recording cancelled."
    }

    func playVoiceSample(modelId: String, voiceId: String?, text: String? = nil) {
        guard !isBusy else { return }

        Task {
            await runBusyTask {
                let inputText = (text ?? self.synthesisText)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !inputText.isEmpty else {
                    self.status = "Enter text to synthesize."
                    return
                }

                let resolvedModelId = modelId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? TTSDefaults.modelId
                    : modelId
                var params: [String: Any] = [
                    "text": inputText,
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

    private func stopCapture() async throws -> URL {
        let url = try await recorder.stop()
        isRecording = false
        return url
    }

    private func resetCapture() {
        isRecording = false
        Task {
            await recorder.cancel()
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
