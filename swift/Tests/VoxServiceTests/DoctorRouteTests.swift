import Foundation
import Testing
import VoxCore
import VoxEngine
@testable import VoxService

private actor DoctorMockTTSProvider: TTSProvider {
    func models() async -> [TTSModelInfo] {
        [
            TTSModelInfo(
                id: "avspeech:system",
                name: "System Speech",
                backend: "avspeech",
                installed: true,
                preloaded: true,
                available: true
            )
        ]
    }

    func voices(modelId: String?) async throws -> [TTSVoiceInfo] { [] }

    func preload(
        modelId: String,
        voiceId: String?,
        progress: @escaping @Sendable (ModelProgress) -> Void
    ) async throws -> TTSModelInfo {
        progress(ModelProgress(modelId: modelId, progress: 1.0, status: "ready"))
        return TTSModelInfo(
            id: modelId,
            name: "System Speech",
            backend: "avspeech",
            installed: true,
            preloaded: true,
            available: true
        )
    }

    func synthesize(_ request: SynthesisRequest) async throws -> SynthesisOutput {
        SynthesisOutput(
            modelId: request.modelId,
            voiceId: request.voiceId ?? "system",
            format: request.format,
            contentType: "audio/wav",
            audioData: Data(),
            elapsedMs: 1,
            metrics: SynthesisMetrics(
                traceId: "doctor-mock",
                characterCount: request.text.count,
                audioDurationMs: 0,
                outputBytes: 0,
                wasPreloaded: true,
                modelCheckMs: 0,
                modelLoadMs: 0,
                voiceResolveMs: 0,
                synthesisMs: 0,
                totalMs: 1
            )
        )
    }
}

struct DoctorRouteTests {
    @Test("doctor helper includes Kokoro-specific checks")
    func doctorHelperIncludesKokoroChecks() async throws {
        let service = VoxRuntimeService(ttsEngine: TTSEngineManager(provider: DoctorMockTTSProvider()))

        let report = await service.performDoctorRun(kokoroChecks: [
            DoctorCheck(name: "kokoro_prereq", status: "warning", detail: "Install uv to enable local Kokoro TTS"),
            DoctorCheck(name: "kokoro_model", status: "warning", detail: "Kokoro model will download on first preload"),
        ])

        #expect(report.checks.contains(where: { $0.name == "synthesis" && $0.status == "ok" }))
        #expect(report.checks.contains(where: { $0.name == "kokoro_prereq" && $0.status == "warning" }))
        #expect(report.checks.contains(where: { $0.name == "kokoro_model" && $0.status == "warning" }))
    }
}
