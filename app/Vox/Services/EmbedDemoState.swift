import AppKit
import AVFoundation
import Foundation
import UniformTypeIdentifiers
import VoxCore
import VoxEngine

private enum EmbedDemoConfig {
    static let ttsModelId = VoxKokoroTTS.modelID

    static func makeTTSEngine() -> TTSEngineManager {
        VoxKokoroTTS.makeEngine()
    }
}

@MainActor
final class EmbedDemoState: ObservableObject {
    @Published var didLoad = false
    @Published var isBusy = false
    @Published var speechText =
        "Hello from Vox embed mode. This audio was generated inside the macOS app using VoxEngine and Kokoro."
    @Published var voiceModel: TTSModelInfo?
    @Published var voices: [TTSVoiceInfo] = []
    @Published var selectedVoiceID: String?
    @Published var speechStatus = "Ready to synthesize with the built-in VoxEngine MLX TTS path."
    @Published var lastSynthesisMetrics: SynthesisMetrics?
    @Published var selectedAudioFileURL: URL?
    @Published var asrModel: ASRModelInfo?
    @Published var transcriptionStatus = "Choose an audio file to run through VoxEngine in process."
    @Published var transcriptText = ""
    @Published var lastTranscriptionMetrics: TranscriptionMetrics?

    private let ttsEngine = EmbedDemoConfig.makeTTSEngine()
    private let asrEngine = EngineManager()
    private var audioPlayer: AVAudioPlayer?

    func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true

        Task {
            await refreshVoiceMetadata()
            await refreshASRMetadata()
        }
    }

    func chooseAudioFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        panel.prompt = "Choose Audio"

        if panel.runModal() == .OK {
            selectedAudioFileURL = panel.url
            transcriptText = ""
            lastTranscriptionMetrics = nil
            if let path = panel.url?.path {
                transcriptionStatus = "Selected \(path)."
            } else {
                transcriptionStatus = "Audio file selected."
            }
        }
    }

    func preloadSpeech() {
        Task {
            await runBusyTask {
                self.speechStatus = "Preloading Kokoro..."
                _ = try await self.ttsEngine.preload(
                    modelId: EmbedDemoConfig.ttsModelId,
                    voiceId: self.selectedVoiceID
                ) { update in
                    Task { @MainActor in
                        self.speechStatus =
                            "Speech preload \(Int(update.progress * 100))% · \(update.status)"
                    }
                }
                await self.refreshVoiceMetadata()
                self.speechStatus = "Speech engine ready."
            } onError: { error in
                self.speechStatus = error.localizedDescription
            }
        }
    }

    func synthesizeAndPlay() {
        Task {
            await runBusyTask {
                let trimmed = self.speechText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    self.speechStatus = "Enter some text first."
                    return
                }

                self.speechStatus = "Synthesizing in process..."
                let output = try await self.ttsEngine.synthesize(
                    SynthesisRequest(
                        text: trimmed,
                        modelId: EmbedDemoConfig.ttsModelId,
                        voiceId: self.selectedVoiceID
                    )
                )

                let player = try AVAudioPlayer(data: output.audioData)
                player.prepareToPlay()
                player.play()
                self.audioPlayer = player

                self.lastSynthesisMetrics = output.metrics
                self.speechStatus =
                    "Played \(output.audioData.count) bytes with \(output.voiceId)."
                await self.refreshVoiceMetadata()
            } onError: { error in
                self.speechStatus = error.localizedDescription
            }
        }
    }

    func preloadASR() {
        Task {
            await runBusyTask {
                self.transcriptionStatus = "Preloading Parakeet..."
                _ = try await self.asrEngine.preload(modelId: "parakeet:v3") { update in
                    Task { @MainActor in
                        self.transcriptionStatus =
                            "ASR preload \(Int(update.progress * 100))% · \(update.status)"
                    }
                }
                await self.refreshASRMetadata()
                self.transcriptionStatus = "ASR model ready."
            } onError: { error in
                self.transcriptionStatus = error.localizedDescription
            }
        }
    }

    func transcribeSelectedFile() {
        Task {
            await runBusyTask {
                guard let fileURL = self.selectedAudioFileURL else {
                    self.transcriptionStatus = "Choose an audio file first."
                    return
                }

                self.transcriptionStatus = "Transcribing \(fileURL.lastPathComponent)..."
                let output = try await self.asrEngine.transcribe(
                    url: fileURL,
                    modelId: "parakeet:v3"
                )

                self.transcriptText = output.text
                self.lastTranscriptionMetrics = output.metrics
                self.transcriptionStatus =
                    "Transcribed \(fileURL.lastPathComponent) with \(output.modelId)."
                await self.refreshASRMetadata()
            } onError: { error in
                self.transcriptionStatus = error.localizedDescription
            }
        }
    }

    private func refreshVoiceMetadata() async {
        voiceModel = await ttsEngine.models().first

        do {
            let loadedVoices = try await ttsEngine.voices(modelId: EmbedDemoConfig.ttsModelId)
                .sorted { lhs, rhs in
                    if lhs.isDefault != rhs.isDefault {
                        return lhs.isDefault && !rhs.isDefault
                    }
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
            voices = loadedVoices
            if selectedVoiceID == nil || !loadedVoices.contains(where: { $0.id == selectedVoiceID }) {
                selectedVoiceID =
                    loadedVoices.first(where: \.isDefault)?.id ?? loadedVoices.first?.id
            }
        } catch {
            speechStatus = localTTSStatus(for: error)
        }
    }

    private func refreshASRMetadata() async {
        asrModel = await asrEngine.models().first
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

    private func localTTSStatus(for error: Error) -> String {
        let message = error.localizedDescription
        if message.localizedCaseInsensitiveContains("mlx-audio is not installed") {
            return message
        }

        if message.localizedCaseInsensitiveContains("provider command is empty or invalid")
            || message.localizedCaseInsensitiveContains("provider process is not running")
        {
            return
                "Kokoro TTS needs uv on PATH so Vox can launch the local speech provider environment."
        }

        return message
    }
}
