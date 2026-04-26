import AppKit
import AVFoundation
import Foundation
import UniformTypeIdentifiers
import VoxCore
import VoxEngine

private enum ExampleConfig {
    static let ttsModelId = VoxKokoroTTS.modelID
    static let asrModelId = "parakeet:v3"

    static func makeTTSEngine() -> TTSEngineManager {
        VoxKokoroTTS.makeEngine()
    }
}

@MainActor
final class ExampleModel: ObservableObject {
    @Published var didLoad = false
    @Published var isRecording = false
    @Published var isWorking = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var hasPendingImportedClip = false
    @Published var microphoneAvailable = false
    @Published var microphoneStatus = "Request microphone access to start a voice turn."
    @Published var asrStateTitle = "Checking Parakeet"
    @Published var asrStateDetail = "Checking whether Parakeet is loaded in memory."
    @Published var asrReadyInMemory = false
    @Published var isWarmingASR = false
    @Published var responseEngineName = "Checking reply engine."
    @Published var responseEngineStatus = "Checking Apple Intelligence and Qwen fallback."
    @Published var statusMessage = "Press the record button to start."
    @Published var lastErrorMessage: String?
    @Published var speechText = ""
    @Published var replyText = ""
    @Published var ttsModel: TTSModelInfo?
    @Published var voices: [TTSVoiceInfo] = []
    @Published var selectedVoiceID: String?
    @Published var speechStatus = "The spoken reply will appear here."
    @Published var selectedAudioURL: URL?
    @Published var transcriptionStatus = "Your transcript will appear here."
    @Published var transcript = ""
    @Published var conversationTurns: [ConversationTurn] = []
    @Published var synthesisMetrics: SynthesisMetrics?
    @Published var transcriptionMetrics: TranscriptionMetrics?
    @Published var responseGenerationDurationMs: Int?

    private let tts = ExampleConfig.makeTTSEngine()
    private let asr = EngineManager()
    private let recorder = AudioRecorder()
    private var player: AVAudioPlayer?

    func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true

        Task {
            await refreshBackendState()
        }
    }

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    func startRecording() {
        Task {
            await beginRecording()
        }
    }

    func stopRecording() {
        guard isRecording else {
            statusMessage = "Not recording."
            return
        }

        guard let clip = recorder.stop() else {
            isRecording = false
            statusMessage = "Recording stopped."
            return
        }

        isRecording = false
        recordingDuration = clip.duration
        selectedAudioURL = clip.url
        statusMessage = "Processing your turn..."
        speechStatus = statusMessage
        transcriptionStatus = "Transcribing your turn..."

        Task {
            await runTask {
                try await self.processRecordedAudio(clip: clip, sourceLabel: "Live mic")
            } onError: { error in
                self.lastErrorMessage = error.localizedDescription
                self.statusMessage = error.localizedDescription
                self.speechStatus = error.localizedDescription
                self.transcriptionStatus = error.localizedDescription
            }
        }
    }

    func chooseAudioFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Choose Audio"

        if panel.runModal() == .OK {
            selectedAudioURL = panel.url
            hasPendingImportedClip = true
            transcript = ""
            replyText = ""
            speechText = ""
            synthesisMetrics = nil
            transcriptionMetrics = nil
            responseGenerationDurationMs = nil
            transcriptionStatus = "Selected \(panel.url?.lastPathComponent ?? "audio file")."
            speechStatus = "Run the clip to hear a spoken reply."
            statusMessage = "Ready to run the imported clip."
        }
    }

    func speak() {
        Task {
            await runTask {
                let trimmed = self.speechText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    self.speechStatus = "Record a turn first to hear the reply."
                    return
                }

                _ = try await self.speak(text: trimmed, statusPrefix: "Speaking reply")
            } onError: { error in
                self.speechStatus = error.localizedDescription
                self.lastErrorMessage = error.localizedDescription
            }
        }
    }

    func playReply(for turnID: UUID) {
        Task {
            await runTask {
                guard let turn = self.conversationTurns.first(where: { $0.id == turnID }) else {
                    return
                }

                _ = try await self.speak(text: turn.reply, statusPrefix: "Speaking reply")
            } onError: { error in
                self.speechStatus = error.localizedDescription
                self.lastErrorMessage = error.localizedDescription
            }
        }
    }

    func transcribe() {
        Task {
            await runTask {
                guard let selectedAudioURL = self.selectedAudioURL else {
                    self.transcriptionStatus = "Choose an audio file first."
                    return
                }

                self.statusMessage = "Processing imported clip..."
                self.speechStatus = self.statusMessage
                self.transcriptionStatus = "Transcribing imported clip..."
                try await self.processRecordedAudio(
                    clip: RecordedClip(url: selectedAudioURL, duration: 0),
                    sourceLabel: selectedAudioURL.lastPathComponent
                )
                self.hasPendingImportedClip = false
            } onError: { error in
                self.transcriptionStatus = error.localizedDescription
                self.lastErrorMessage = error.localizedDescription
            }
        }
    }

    func warmASR() {
        Task {
            await runTask {
                try await self.preloadASR()
            } onError: { error in
                self.lastErrorMessage = error.localizedDescription
                self.statusMessage = error.localizedDescription
                self.transcriptionStatus = error.localizedDescription
                self.asrStateDetail = error.localizedDescription
            }
        }
    }

    private func refreshBackendState() async {
        await refreshMicrophoneAvailability()
        await refreshASRState()
        await refreshResponseEngineAvailability()
        await refreshVoices()
    }

    private func refreshMicrophoneAvailability() async {
        let status = await AudioRecorder.authorizationStatus()
        microphoneAvailable = (status == .authorized)
        microphoneStatus = AudioRecorder.statusMessage(for: status)
    }

    private func refreshASRState() async {
        let info = await asr.models().first(where: { $0.id == ExampleConfig.asrModelId })
        applyASRState(info)
    }

    private func refreshResponseEngineAvailability() async {
        let availability = await ResponseEngineService.availability()
        responseEngineName = availability.preferredEngineName
        responseEngineStatus = availability.message
    }

    private func refreshVoices() async {
        ttsModel = await tts.models().first

        do {
            let loadedVoices = try await tts.voices(modelId: ExampleConfig.ttsModelId)
                .sorted { lhs, rhs in
                    if lhs.isDefault != rhs.isDefault {
                        return lhs.isDefault && !rhs.isDefault
                    }
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
            voices = loadedVoices
            if selectedVoiceID == nil {
                selectedVoiceID = loadedVoices.first(where: \.isDefault)?.id ?? loadedVoices.first?.id
            }
        } catch {
            speechStatus = error.localizedDescription
            lastErrorMessage = error.localizedDescription
        }
    }

    private func beginRecording() async {
        guard !isWorking else {
            statusMessage = "Please wait until the current turn finishes."
            return
        }
        guard !isRecording else {
            statusMessage = "Already listening."
            return
        }

        await refreshMicrophoneAvailability()
        let authorization = await AudioRecorder.authorizationStatus()
        switch authorization {
        case .authorized:
            break
        case .notDetermined:
            NSApplication.shared.activate(ignoringOtherApps: true)
            let granted = await AudioRecorder.requestMicrophoneAccess()
            if !granted {
                microphoneAvailable = false
                microphoneStatus = "Microphone access denied."
                lastErrorMessage = "Microphone access denied."
                statusMessage = microphoneStatus
                speechStatus = statusMessage
                transcriptionStatus = statusMessage
                return
            }
            microphoneAvailable = true
            microphoneStatus = "Microphone access granted."
        case .denied, .restricted:
            microphoneAvailable = false
            microphoneStatus = AudioRecorder.statusMessage(for: authorization)
            lastErrorMessage = microphoneStatus
            statusMessage = microphoneStatus
            speechStatus = statusMessage
            transcriptionStatus = statusMessage
            return
        @unknown default:
            microphoneAvailable = false
            microphoneStatus = "Microphone unavailable."
            lastErrorMessage = microphoneStatus
            statusMessage = microphoneStatus
            speechStatus = statusMessage
            transcriptionStatus = statusMessage
            return
        }

        do {
            let url = try recorder.start()
            isRecording = true
            recordingDuration = 0
            selectedAudioURL = url
            hasPendingImportedClip = false
            lastErrorMessage = nil
            transcript = ""
            replyText = ""
            speechText = ""
            synthesisMetrics = nil
            transcriptionMetrics = nil
            responseGenerationDurationMs = nil
            statusMessage = "Listening..."
            speechStatus = "Recording your turn."
            transcriptionStatus = "Recording your turn."
        } catch {
            lastErrorMessage = error.localizedDescription
            statusMessage = error.localizedDescription
            speechStatus = statusMessage
            transcriptionStatus = statusMessage
        }
    }

    private func processRecordedAudio(clip: RecordedClip, sourceLabel: String) async throws {
        let transcription = try await transcribeAudio(at: clip.url, statusPrefix: "Transcribing recording")
        transcript = transcription.text
        transcriptionMetrics = transcription.metrics
        transcriptionStatus = transcription.text.isEmpty
            ? "No speech detected."
            : "Transcribed with \(transcription.modelId)."

        let reply = try await generateReply(for: transcription.text)
        replyText = reply.text
        responseGenerationDurationMs = reply.elapsedMs
        responseEngineName = reply.engineName
        responseEngineStatus = reply.statusMessage

        let synthesis = try await speak(text: reply.text, statusPrefix: "Speaking reply")
        synthesisMetrics = synthesis.metrics
        conversationTurns.append(ConversationTurn(
            sourceLabel: sourceLabel,
            transcript: transcription.text.isEmpty ? "No speech detected." : transcription.text,
            reply: reply.text,
            engineName: reply.engineName,
            transcriptionMetrics: transcription.metrics,
            responseDurationMs: reply.elapsedMs,
            synthesisMetrics: synthesis.metrics
        ))
        speechStatus = "Spoke reply with \(synthesis.voiceId)."
        statusMessage = "Ready for another turn."
        transcriptionStatus = transcription.text.isEmpty
            ? "No speech detected."
            : "Transcribed and replied."
    }

    private func transcribeAudio(at url: URL, statusPrefix: String) async throws -> TranscriptionOutput {
        statusMessage = "\(statusPrefix)..."
        transcriptionStatus = "\(statusPrefix)..."
        let output = try await asr.transcribe(
            url: url,
            modelId: ExampleConfig.asrModelId
        )
        transcript = output.text
        transcriptionMetrics = output.metrics
        await refreshASRState()
        transcriptionStatus = "Transcribed with \(output.modelId)."
        return output
    }

    private func preloadASR() async throws {
        await refreshASRState()
        guard !asrReadyInMemory else {
            statusMessage = "Parakeet already ready."
            transcriptionStatus = "Parakeet is already loaded in memory."
            return
        }

        isWarmingASR = true
        defer { isWarmingASR = false }

        statusMessage = "Warming Parakeet..."
        transcriptionStatus = "Loading Parakeet into memory..."
        let info = try await asr.preload(modelId: ExampleConfig.asrModelId, progress: { _ in })
        applyASRState(info)
        statusMessage = "Parakeet ready."
        transcriptionStatus = "Parakeet is loaded in memory and ready."
    }

    private func applyASRState(_ info: ASRModelInfo?) {
        guard let info else {
            asrReadyInMemory = false
            asrStateTitle = "Parakeet unknown"
            asrStateDetail = "Parakeet model status is unavailable."
            return
        }

        asrReadyInMemory = info.preloaded

        if !info.available {
            asrStateTitle = "Parakeet unavailable"
            asrStateDetail = "The Parakeet backend is unavailable in this build."
            return
        }

        if info.preloaded {
            asrStateTitle = "Parakeet ready"
            asrStateDetail = "Loaded in memory and ready to transcribe."
            return
        }

        if info.installed {
            asrStateTitle = "Parakeet cold"
            asrStateDetail = "Installed on disk but not loaded in memory yet."
            return
        }

        asrStateTitle = "Parakeet not installed"
        asrStateDetail = "The first ASR turn will install and load the model."
    }

    private func generateReply(for transcript: String) async throws -> ReplyResult {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ReplyResult(
                text: "I didn't quite catch that. Try one more time.",
                elapsedMs: 0,
                engineName: responseEngineName,
                statusMessage: "No speech detected."
            )
        }

        let availability = await ResponseEngineService.availability()
        responseEngineName = availability.preferredEngineName
        responseEngineStatus = availability.message

        if availability.preferredEngineName == QwenFallbackService.displayName {
            statusMessage = "Starting \(QwenFallbackService.displayName)..."
            speechStatus = statusMessage
        }

        do {
            let result = try await ResponseEngineService.generateReply(for: trimmed)
            return ReplyResult(
                text: result.text,
                elapsedMs: result.elapsedMs,
                engineName: result.engineName,
                statusMessage: result.statusMessage
            )
        } catch {
            lastErrorMessage = error.localizedDescription
            responseEngineStatus = error.localizedDescription
            throw error
        }
    }

    private func speak(text: String, statusPrefix: String) async throws -> SynthesisOutput {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ExampleModelError.emptyText
        }

        statusMessage = "\(statusPrefix)..."
        speechStatus = statusMessage

        let output = try await tts.synthesize(SynthesisRequest(
            text: trimmed,
            modelId: ExampleConfig.ttsModelId,
            voiceId: selectedVoiceID
        ))

        let player = try AVAudioPlayer(data: output.audioData)
        player.prepareToPlay()
        player.play()
        self.player = player

        speechText = trimmed
        speechStatus = "Played \(output.audioData.count) bytes with \(output.voiceId)."
        statusMessage = "Ready."
        return output
    }

    private func runTask(
        operation: @escaping @MainActor () async throws -> Void,
        onError: @escaping @MainActor (Error) -> Void
    ) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }

        do {
            try await operation()
        } catch {
            onError(error)
        }
    }
}

private struct ReplyResult: Sendable {
    let text: String
    let elapsedMs: Int
    let engineName: String
    let statusMessage: String
}

struct ConversationTurn: Identifiable, Sendable {
    let id = UUID()
    let sourceLabel: String
    let transcript: String
    let reply: String
    let engineName: String
    let transcriptionMetrics: TranscriptionMetrics?
    let responseDurationMs: Int
    let synthesisMetrics: SynthesisMetrics?
}

private enum ExampleModelError: LocalizedError {
    case emptyText

    var errorDescription: String? {
        switch self {
        case .emptyText:
            return "Record a turn first."
        }
    }
}
