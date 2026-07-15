import AppKit
import Carbon.HIToolbox
import Combine
import Foundation
import VoxCore
import VoxEngine

private enum MinivoxConfig {
    static let asrModelId = "parakeet:v3"
}

private struct RecordedClip: Sendable {
    let url: URL
    let duration: TimeInterval
}

@MainActor
final class MinivoxModel: ObservableObject {
    private static let legacyShortcutDefaultsKey = "minivox.dictationShortcut"
    private static let shortcutKeyCodeDefaultsKey = "minivox.dictationShortcut.keyCode"
    private static let shortcutModifiersDefaultsKey = "minivox.dictationShortcut.modifiers"
    private static let shortcutTitleDefaultsKey = "minivox.dictationShortcut.title"
    static let autoPasteDefaultsKey = "minivox.autoPaste"
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
    @Published private(set) var didPaste = false
    @Published private(set) var autoPasteAccessGranted = CGPreflightPostEventAccess()
    @Published private(set) var historyRecords: [SpeechHistoryRecord] = []
    @Published private(set) var historyErrorMessage: String?
    @Published private(set) var dictationShortcut: DictationShortcut?
    @Published private(set) var isCapturingShortcut = false
    @Published private(set) var preferredInputDeviceId = ""
    @Published private(set) var inputDevices: [AudioInputDeviceInfo] = []

    private let asr = EngineManager()
    private let historyRecorder = SpeechHistoryRecorder()
    private let recorder = MicrophoneFileRecorder()
    private var shortcutController: GlobalShortcutController?
    private var shortcutEventMonitor: Any?
    private var recordingStartedAt: Date?

    init() {
        UserDefaults.standard.register(defaults: [Self.autoPasteDefaultsKey: true])
        dictationShortcut = Self.loadShortcut()
        preferredInputDeviceId = (try? VoxPreferences.load())?.speech.preferredInputDeviceId ?? ""

        shortcutController = GlobalShortcutController { [weak self] in
            self?.toggleRecording()
        }
        applyShortcut()
    }

    func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true

        Task {
            refreshInputDevices()
            refreshMicrophoneAvailability()
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
        didPaste = false
        statusMessage = ""
    }

    func requestAutoPasteAccess() {
        autoPasteAccessGranted = CGPreflightPostEventAccess() || CGRequestPostEventAccess()
        statusMessage = autoPasteAccessGranted
            ? ""
            : "Allow Minivox in Privacy & Security › Accessibility."
    }

    func refreshAutoPasteAccess() {
        autoPasteAccessGranted = CGPreflightPostEventAccess()
    }

    var effectiveInputDeviceLabel: String {
        AudioInputDevices.effectiveLabel(preferredID: preferredInputDeviceId)
    }

    func refreshInputDevices() {
        preferredInputDeviceId = (try? VoxPreferences.load())?.speech.preferredInputDeviceId ?? ""
        inputDevices = AudioInputDevices.available()

        if !preferredInputDeviceId.isEmpty,
           !inputDevices.contains(where: { $0.id == preferredInputDeviceId }) {
            preferredInputDeviceId = ""
            savePreferredInputDevice()
        }
    }

    func updatePreferredInputDeviceId(_ deviceId: String) {
        preferredInputDeviceId = deviceId
        guard savePreferredInputDevice() else { return }
        refreshInputDevices()
        statusMessage = ""
    }

    func autoPastePreferenceDidChange(isEnabled: Bool) {
        if isEnabled {
            requestAutoPasteAccess()
        } else {
            didPaste = false
            statusMessage = ""
        }
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
        isRecording = false
        let startedAt = recordingStartedAt
        recordingStartedAt = nil
        statusMessage = ""

        Task {
            await runTask {
                let url = try await self.recorder.stop()
                let clip = RecordedClip(
                    url: url,
                    duration: max(0, Date().timeIntervalSince(startedAt ?? Date()))
                )
                self.recordingDuration = clip.duration
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

        refreshInputDevices()
        refreshMicrophoneAvailability()
        if MicrophonePermission.statusString() == "not_determined" {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }

        do {
            _ = try await recorder.start(
                preferredInputDeviceID: preferredInputDeviceId,
                filePrefix: "minivox"
            )
            recordingStartedAt = Date()
            isRecording = true
            recordingDuration = 0
            transcript = ""
            transcriptionMetrics = nil
            lastErrorMessage = nil
            didCopy = false
            didPaste = false
            statusMessage = ""
            refreshMicrophoneAvailability()
        } catch {
            refreshMicrophoneAvailability()
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
        await pasteTranscriptIfEnabled()
    }

    private func copyTranscript(showConfirmation: Bool) {
        guard !transcript.isEmpty else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(transcript, forType: .string)
        didCopy = true
        didPaste = false

        if showConfirmation { statusMessage = "" }
    }

    private func pasteTranscriptIfEnabled() async {
        guard UserDefaults.standard.bool(forKey: Self.autoPasteDefaultsKey) else {
            statusMessage = ""
            return
        }

        guard CGPreflightPostEventAccess() || CGRequestPostEventAccess() else {
            autoPasteAccessGranted = false
            statusMessage = "Allow Minivox in Privacy & Security › Accessibility."
            return
        }

        autoPasteAccessGranted = true
        try? await Task.sleep(nanoseconds: 120_000_000)

        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(
                  keyboardEventSource: source,
                  virtualKey: CGKeyCode(kVK_ANSI_V),
                  keyDown: true
              ),
              let keyUp = CGEvent(
                  keyboardEventSource: source,
                  virtualKey: CGKeyCode(kVK_ANSI_V),
                  keyDown: false
              ) else {
            statusMessage = "Copied. Auto-paste was unavailable."
            return
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        didPaste = true
        statusMessage = ""
    }

    private func refreshMicrophoneAvailability() {
        microphoneStatus = switch MicrophonePermission.statusString() {
        case "authorized": "Microphone ready."
        case "not_determined": "Request microphone access to record."
        case "denied": "Microphone access is denied. Enable it in System Settings."
        case "restricted": "Microphone access is restricted."
        default: "Microphone access is unavailable."
        }
    }

    @discardableResult
    private func savePreferredInputDevice() -> Bool {
        do {
            var preferences = (try? VoxPreferences.load()) ?? VoxPreferences()
            let normalized = preferredInputDeviceId.trimmingCharacters(in: .whitespacesAndNewlines)
            preferences.speech.preferredInputDeviceId = normalized.isEmpty ? nil : normalized
            try preferences.save()
            return true
        } catch {
            statusMessage = error.localizedDescription
            return false
        }
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
