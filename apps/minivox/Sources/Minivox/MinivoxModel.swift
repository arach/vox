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
    static let warmUpOnLaunchDefaultsKey = "minivox.warmUpOnLaunch"

    @Published var didLoad = false
    @Published var isRecording = false
    @Published var isWorking = false
    @Published var isWarmingASR = false
    @Published var asrReadyInMemory = false
    @Published var asrStateTitle = "Checking Parakeet"
    @Published var asrStateDetail = "Checking whether Parakeet is ready."
    @Published var microphoneStatus = "Microphone access not checked."
    @Published var statusMessage = ""
    @Published var transcript = ""
    @Published var transcriptionMetrics: TranscriptionMetrics?
    @Published var recordingDuration: TimeInterval = 0
    @Published var lastErrorMessage: String?
    @Published var didCopy = false
    @Published private(set) var historyRecords: [SpeechHistoryRecord] = []
    @Published private(set) var historyErrorMessage: String?
    @Published private(set) var dictationShortcut: DictationShortcut?
    @Published private(set) var isCapturingShortcut = false

    private let asr = EngineManager()
    private let historyRecorder = SpeechHistoryRecorder()
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

            if UserDefaults.standard.bool(forKey: Self.warmUpOnLaunchDefaultsKey), !asrReadyInMemory {
                await runTask {
                    try await self.preloadASR()
                }
            }
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
        statusMessage = ""
    }

    func beginShortcutCapture() {
        guard !isCapturingShortcut else { return }
        shortcutController?.register(nil)
        isCapturingShortcut = true
        statusMessage = "Press a shortcut. Hold Fn/Globe for a function key."
        NSApplication.shared.activate(ignoringOtherApps: true)

        shortcutEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .systemDefined]) { [weak self] event in
            self?.captureShortcut(event)
            return nil
        }
    }

    func cancelShortcutCapture() {
        guard isCapturingShortcut else { return }
        isCapturingShortcut = false
        stopShortcutCaptureMonitoring()
        applyShortcut()
        statusMessage = ""
    }

    func captureShortcut(_ event: NSEvent) {
        guard isCapturingShortcut else { return }

        if event.type == .systemDefined {
            NSSound.beep()
            statusMessage = "That was a media key. Hold Fn/Globe and press it again to record F1–F12."
            return
        }

        switch Int(event.keyCode) {
        case kVK_Escape:
            cancelShortcutCapture()
            return
        case kVK_Delete, kVK_ForwardDelete:
            setShortcut(nil)
            statusMessage = ""
            return
        default:
            break
        }

        guard let shortcut = DictationShortcut(event: event) else {
            NSSound.beep()
            statusMessage = "Use a modifier, or hold Fn/Globe and press a function key."
            return
        }

        setShortcut(shortcut)
        statusMessage = ""
    }

    func disableShortcut() {
        setShortcut(nil)
        statusMessage = ""
    }

    func loadHistory() {
        Task {
            await refreshHistory()
        }
    }

    func copyHistoryRecord(_ record: SpeechHistoryRecord) {
        guard let text = record.text, !text.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    func clearHistory() {
        Task {
            do {
                _ = try await historyRecorder.clear(filter: Self.minivoxHistoryFilter)
                historyRecords = []
                historyErrorMessage = nil
            } catch {
                historyErrorMessage = error.localizedDescription
            }
        }
    }

    private func stopRecording() {
        guard isRecording else { return }

        guard let clip = recorder.stop() else {
            isRecording = false
            statusMessage = ""
            return
        }

        isRecording = false
        recordingDuration = clip.duration
        statusMessage = ""

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
            statusMessage = ""
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

        let historyRecord = SpeechHistoryRecord.transcription(
            source: .file,
            route: "minivox.dictation",
            clientId: "minivox",
            modelId: MinivoxConfig.asrModelId,
            output: output,
            startedAt: Date().addingTimeInterval(-clip.duration)
        )
        await historyRecorder.record(historyRecord)
        await refreshHistory()

        copyTranscript(showConfirmation: false)
        statusMessage = ""
    }

    private func copyTranscript(showConfirmation: Bool) {
        guard !transcript.isEmpty else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(transcript, forType: .string)
        didCopy = true

        if showConfirmation { statusMessage = "" }
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
            statusMessage = ""
            return
        }

        isWarmingASR = true
        defer { isWarmingASR = false }

        statusMessage = ""
        let info = try await asr.preload(modelId: MinivoxConfig.asrModelId, progress: { _ in })
        applyASRState(info)
        statusMessage = ""
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

    private func refreshHistory() async {
        do {
            historyRecords = try await historyRecorder.list(filter: Self.minivoxHistoryFilter)
            historyErrorMessage = nil
        } catch {
            historyErrorMessage = error.localizedDescription
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

    private static var minivoxHistoryFilter: SpeechHistoryListFilter {
        SpeechHistoryListFilter(
            kind: .transcription,
            clientId: "minivox",
            limit: 100
        )
    }
}
