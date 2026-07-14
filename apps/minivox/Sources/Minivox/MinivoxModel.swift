import AppKit
import Carbon.HIToolbox
import Combine
import Foundation
import VoxCore
import VoxEngine

private enum MinivoxConfig {
    static let asrModelId = "parakeet:v3"
}

@MainActor
final class MinivoxModel: ObservableObject {
    private static let legacyShortcutDefaultsKey = "minivox.dictationShortcut"
    private static let shortcutKeyCodeDefaultsKey = "minivox.dictationShortcut.keyCode"
    private static let shortcutModifiersDefaultsKey = "minivox.dictationShortcut.modifiers"
    private static let shortcutTitleDefaultsKey = "minivox.dictationShortcut.title"

    @Published var didLoad = false
    @Published var isRecording = false
    @Published var isWorking = false
    @Published var isWarmingASR = false
    @Published var asrReadyInMemory = false
    @Published var asrStateTitle = "Checking Parakeet"
    @Published var asrStateDetail = "Checking whether Parakeet is ready."
    @Published var microphoneStatus = "Microphone access not checked."
    @Published var statusMessage = "Tap the microphone to dictate."
    @Published var transcript = ""
    @Published var transcriptionMetrics: TranscriptionMetrics?
    @Published var recordingDuration: TimeInterval = 0
    @Published var lastErrorMessage: String?
    @Published var didCopy = false
    @Published private(set) var dictationShortcut: DictationShortcut?
    @Published private(set) var isCapturingShortcut = false

    private let asr = EngineManager()
    private let recorder = AudioRecorder()
    private var shortcutController: GlobalShortcutController?
    private var shortcutEventMonitor: Any?

    init() {
        dictationShortcut = Self.loadShortcut()

        shortcutController = GlobalShortcutController { [weak self] in
            self?.toggleRecording()
        }
        applyShortcut()
    }

    func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true

        Task {
            await refreshMicrophoneAvailability()
            await refreshASRState()
        }
    }

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            Task { await beginRecording() }
        }
    }

    func warmASR() {
        Task {
            await runTask {
                try await self.preloadASR()
            }
        }
    }

    func copyTranscript() {
        copyTranscript(showConfirmation: true)
    }

    func clearTranscript() {
        transcript = ""
        transcriptionMetrics = nil
        didCopy = false
        statusMessage = "Tap the microphone to dictate."
    }

    func beginShortcutCapture() {
        guard !isCapturingShortcut else { return }
        shortcutController?.register(nil)
        isCapturingShortcut = true
        statusMessage = "Press any key or key combination."
        NSApplication.shared.activate(ignoringOtherApps: true)

        shortcutEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.captureShortcut(event)
            return nil
        }
    }

    func cancelShortcutCapture() {
        guard isCapturingShortcut else { return }
        isCapturingShortcut = false
        stopShortcutCaptureMonitoring()
        applyShortcut()
        statusMessage = "Shortcut unchanged."
    }

    func captureShortcut(_ event: NSEvent) {
        guard isCapturingShortcut else { return }

        switch Int(event.keyCode) {
        case kVK_Escape:
            cancelShortcutCapture()
            return
        case kVK_Delete, kVK_ForwardDelete:
            setShortcut(nil)
            statusMessage = "Global shortcut turned off."
            return
        default:
            break
        }

        guard let shortcut = DictationShortcut(event: event) else {
            NSSound.beep()
            statusMessage = "That key cannot be used as a shortcut."
            return
        }

        setShortcut(shortcut)
        statusMessage = "Shortcut set to \(shortcut.title)."
    }

    func disableShortcut() {
        setShortcut(nil)
        statusMessage = "Global shortcut turned off."
    }

    private func stopRecording() {
        guard isRecording else { return }

        guard let clip = recorder.stop() else {
            isRecording = false
            statusMessage = "Recording stopped."
            return
        }

        isRecording = false
        recordingDuration = clip.duration
        statusMessage = "Transcribing…"

        Task {
            await runTask {
                try await self.transcribe(clip)
            }
        }
    }

    private func beginRecording() async {
        guard !isWorking, !isWarmingASR else {
            statusMessage = "Minivox is still getting ready."
            return
        }
        guard !isRecording else { return }

        await refreshMicrophoneAvailability()
        let authorization = await AudioRecorder.authorizationStatus()
        switch authorization {
        case .authorized:
            break
        case .notDetermined:
            NSApplication.shared.activate(ignoringOtherApps: true)
            let granted = await AudioRecorder.requestMicrophoneAccess()
            guard granted else {
                microphoneStatus = "Microphone access denied."
                lastErrorMessage = microphoneStatus
                statusMessage = microphoneStatus
                return
            }
            microphoneStatus = "Microphone ready."
        case .denied, .restricted:
            microphoneStatus = AudioRecorder.statusMessage(for: authorization)
            lastErrorMessage = microphoneStatus
            statusMessage = microphoneStatus
            return
        @unknown default:
            microphoneStatus = "Microphone unavailable."
            lastErrorMessage = microphoneStatus
            statusMessage = microphoneStatus
            return
        }

        do {
            _ = try recorder.start()
            isRecording = true
            recordingDuration = 0
            transcript = ""
            transcriptionMetrics = nil
            lastErrorMessage = nil
            didCopy = false
            statusMessage = "Listening…"
        } catch {
            lastErrorMessage = error.localizedDescription
            statusMessage = error.localizedDescription
        }
    }

    private func transcribe(_ clip: RecordedClip) async throws {
        defer { try? FileManager.default.removeItem(at: clip.url) }

        let output = try await asr.transcribe(
            url: clip.url,
            modelId: MinivoxConfig.asrModelId
        )
        await refreshASRState()

        let text = output.text.trimmingCharacters(in: .whitespacesAndNewlines)
        transcript = text
        transcriptionMetrics = output.metrics

        guard !text.isEmpty else {
            statusMessage = "No speech detected. Try once more."
            return
        }

        copyTranscript(showConfirmation: false)
        statusMessage = "Copied to your clipboard."
    }

    private func copyTranscript(showConfirmation: Bool) {
        guard !transcript.isEmpty else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(transcript, forType: .string)
        didCopy = true

        if showConfirmation {
            statusMessage = "Copied to your clipboard."
        }
    }

    private func refreshMicrophoneAvailability() async {
        microphoneStatus = AudioRecorder.statusMessage(for: await AudioRecorder.authorizationStatus())
    }

    private func refreshASRState() async {
        let info = await asr.models().first(where: { $0.id == MinivoxConfig.asrModelId })
        applyASRState(info)
    }

    private func preloadASR() async throws {
        await refreshASRState()
        guard !asrReadyInMemory else {
            statusMessage = "Parakeet is already ready."
            return
        }

        isWarmingASR = true
        defer { isWarmingASR = false }

        statusMessage = "Warming up Parakeet…"
        let info = try await asr.preload(modelId: MinivoxConfig.asrModelId, progress: { _ in })
        applyASRState(info)
        statusMessage = "Parakeet is ready."
    }

    private func applyASRState(_ info: ASRModelInfo?) {
        guard let info else {
            asrReadyInMemory = false
            asrStateTitle = "Parakeet unknown"
            asrStateDetail = "Model status is unavailable."
            return
        }

        asrReadyInMemory = info.preloaded

        if !info.available {
            asrStateTitle = "Parakeet unavailable"
            asrStateDetail = "The transcription backend is unavailable in this build."
        } else if info.preloaded {
            asrStateTitle = "Parakeet ready"
            asrStateDetail = "Loaded in memory and ready to transcribe."
        } else if info.installed {
            asrStateTitle = "Parakeet cold"
            asrStateDetail = "Installed, but not loaded into memory yet."
        } else {
            asrStateTitle = "Parakeet not installed"
            asrStateDetail = "The first dictation will install and load the model."
        }
    }

    private func runTask(operation: @escaping @MainActor () async throws -> Void) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }

        do {
            try await operation()
        } catch {
            lastErrorMessage = error.localizedDescription
            statusMessage = error.localizedDescription
        }
    }

    private func applyShortcut() {
        guard let shortcutController else { return }
        let registered = shortcutController.register(dictationShortcut)
        if !registered {
            statusMessage = "That shortcut is already used by another app."
        }
    }

    private func setShortcut(_ shortcut: DictationShortcut?) {
        dictationShortcut = shortcut
        isCapturingShortcut = false
        stopShortcutCaptureMonitoring()

        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Self.legacyShortcutDefaultsKey)

        if let shortcut {
            defaults.set(Int(shortcut.keyCode), forKey: Self.shortcutKeyCodeDefaultsKey)
            defaults.set(Int(shortcut.modifiers), forKey: Self.shortcutModifiersDefaultsKey)
            defaults.set(shortcut.title, forKey: Self.shortcutTitleDefaultsKey)
        } else {
            defaults.removeObject(forKey: Self.shortcutKeyCodeDefaultsKey)
            defaults.removeObject(forKey: Self.shortcutModifiersDefaultsKey)
            defaults.removeObject(forKey: Self.shortcutTitleDefaultsKey)
        }

        applyShortcut()
    }

    private func stopShortcutCaptureMonitoring() {
        guard let shortcutEventMonitor else { return }
        NSEvent.removeMonitor(shortcutEventMonitor)
        self.shortcutEventMonitor = nil
    }

    private static func loadShortcut() -> DictationShortcut? {
        let defaults = UserDefaults.standard
        if let keyCode = defaults.object(forKey: shortcutKeyCodeDefaultsKey) as? NSNumber,
           let modifiers = defaults.object(forKey: shortcutModifiersDefaultsKey) as? NSNumber,
           let title = defaults.string(forKey: shortcutTitleDefaultsKey) {
            return DictationShortcut(
                keyCode: keyCode.uint32Value,
                modifiers: modifiers.uint32Value,
                title: title
            )
        }

        switch defaults.string(forKey: legacyShortcutDefaultsKey) {
        case "controlSpace": return .controlSpace
        case "optionShiftSpace": return .optionShiftSpace
        case "off": return nil
        default: return .optionSpace
        }
    }
}
