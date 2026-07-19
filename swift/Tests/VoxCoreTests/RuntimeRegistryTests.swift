import Foundation
import Testing
@testable import VoxCore

@Suite(.serialized)
struct RuntimeRegistryTests {
    @Test("Runtime registry writes and reads runtime metadata")
    func runtimeRegistryRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        setenv("VOX_HOME", directory.path, 1)
        defer {
            unsetenv("VOX_HOME")
            try? FileManager.default.removeItem(at: directory)
        }

        let runtime = RuntimeInfo(
            version: "0.1.0",
            serviceName: "Vox",
            port: 42137,
            pid: 99,
            startedAt: Date(timeIntervalSince1970: 0)
        )

        try RuntimeRegistry.write(runtime)
        let loaded = try RuntimeRegistry.read()
        #expect(loaded == runtime)

        try RuntimeRegistry.remove()
        #expect(try RuntimeRegistry.read() == nil)
    }

    @Test("Speech preferences round-trip through the shared Vox home")
    func speechPreferencesRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        setenv("VOX_HOME", directory.path, 1)
        defer {
            unsetenv("VOX_HOME")
            try? FileManager.default.removeItem(at: directory)
        }

        let preferences = VoxPreferences(
            speech: VoxSpeechPreferences(
                preferredTranscriptionModelId: "mlx-community/whisper-large-v3",
                preferredSynthesisModelId: "openai-tts:alloy",
                preferredSynthesisVoiceId: "alloy",
                preferredInputDeviceId: "system-mic",
                modelDownloadPolicy: .eager
            )
        )

        try preferences.save()

        let loaded = try VoxPreferences.load()
        #expect(loaded == preferences)
        #expect(FileManager.default.fileExists(atPath: RuntimePaths.preferencesFileURL().path))
    }

    @Test("Legacy speech preferences acquire the model on first use")
    func legacySpeechPreferencesDefaultDownloadPolicy() throws {
        let data = Data(#"{"preferredTranscriptionModelId":"parakeet:v3"}"#.utf8)

        let preferences = try JSONDecoder().decode(VoxSpeechPreferences.self, from: data)

        #expect(preferences.modelDownloadPolicy == .onFirstUse)
        #expect(!VoxModelDownloadPolicy.never.warmsAtServiceStart)
        #expect(!VoxModelDownloadPolicy.never.warmsOnFirstUse)
        #expect(!VoxModelDownloadPolicy.onFirstUse.warmsAtServiceStart)
        #expect(VoxModelDownloadPolicy.onFirstUse.warmsOnFirstUse)
        #expect(VoxModelDownloadPolicy.eager.warmsAtServiceStart)
        #expect(VoxModelDownloadPolicy.eager.warmsOnFirstUse)
    }

    @Test("Microphone permission doctor details include remediation")
    func microphonePermissionDoctorDetails() {
        let notDetermined = MicrophonePermission.remediation(for: "not_determined")
        #expect(MicrophonePermission.detail(for: "not_determined") == "Microphone access has not been requested")
        #expect(notDetermined?.action == "request_microphone_access")
        #expect(notDetermined?.label == "Request Access")

        let denied = MicrophonePermission.remediation(for: "denied")
        #expect(MicrophonePermission.detail(for: "denied") == "Microphone access denied")
        #expect(denied?.action == "open_microphone_privacy_settings")

        let check = DoctorCheck(
            name: "microphone",
            status: "warning",
            detail: MicrophonePermission.detail(for: "not_determined"),
            remediation: notDetermined
        )
        let remediation = check.dictionaryValue()["remediation"] as? [String: Any]
        #expect(remediation?["action"] as? String == "request_microphone_access")
    }
}
