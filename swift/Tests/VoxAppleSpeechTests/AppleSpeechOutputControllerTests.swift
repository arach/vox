import AVFoundation
import Foundation
import Testing
import VoxCore
import VoxEngine
@testable import VoxAppleSpeech

struct AppleSpeechOutputControllerTests {
    @Test("direct explicit system voice is set and assistive-tech settings do not override it")
    func explicitSystemVoiceIsNotOverriddenByAssistiveSettings() async throws {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        let voice = try #require(voices.first)
        let synthesizer = FakeSystemSpeechSynthesizer()
        let provider = RecordingTTSProvider(modelId: TTSDefaults.localModelId, backend: "avspeech")
        let collector = EventCollector()
        let controller = AppleSpeechOutputController(
            engine: TTSEngineManager(provider: provider),
            synthesizer: synthesizer,
            playerFactory: { _ in ImmediateAudioPlayer() },
            onEvent: collector.handle
        )

        let request = SynthesisRequest(
            text: "Hello from Vox",
            modelId: TTSDefaults.localModelId,
            voiceId: voice.identifier
        )
        await controller.speak(request)

        let spoken = try await synthesizer.waitForSpeak()
        #expect(spoken.voiceIdentifier == voice.identifier)
        #expect(spoken.prefersAssistiveTechnologySettings == false)
        #expect(await provider.synthesizeCount() == 0)

        let starting = try await collector.wait(for: .starting, requestId: request.requestId)
        #expect(starting.synthesis.delivery == .liveSystem)
        #expect(starting.synthesis.voiceId == voice.identifier)
        #expect(starting.audioOutput.kind == .systemSynthesizer)
    }

    @Test("stop before didStart still cancels")
    func stopBeforeDidStartStillCancels() async throws {
        let voice = try #require(AVSpeechSynthesisVoice.speechVoices().first)
        let synthesizer = FakeSystemSpeechSynthesizer()
        let collector = EventCollector()
        let controller = AppleSpeechOutputController(
            engine: TTSEngineManager(provider: RecordingTTSProvider(
                modelId: TTSDefaults.localModelId,
                backend: "avspeech"
            )),
            synthesizer: synthesizer,
            playerFactory: { _ in ImmediateAudioPlayer() },
            onEvent: collector.handle
        )

        let request = SynthesisRequest(
            text: "Queued then cancelled",
            modelId: TTSDefaults.localModelId,
            voiceId: voice.identifier
        )
        await controller.speak(request)
        let starting = try await collector.wait(for: .starting, requestId: request.requestId)
        #expect(synthesizer.spokenCount == 1)

        await controller.stop()
        _ = try await collector.wait(for: .cancelled, requestId: request.requestId)

        synthesizer.emit(.didStart, generation: starting.generation, requestId: request.requestId)
        synthesizer.emit(.didFinish, generation: starting.generation, requestId: request.requestId)
        try await Task.sleep(nanoseconds: 20_000_000)

        let phases = collector.phases(for: request.requestId)
        #expect(phases.contains(.cancelled))
        #expect(!phases.contains(.playing))
        #expect(!phases.contains(.finished))
        #expect(synthesizer.stopGenerations.contains(starting.generation))
    }

    @Test("replacement ignores stale start/finish/cancel")
    func replacementIgnoresStaleCallbacks() async throws {
        let voice = try #require(AVSpeechSynthesisVoice.speechVoices().first)
        let synthesizer = FakeSystemSpeechSynthesizer()
        let collector = EventCollector()
        let controller = AppleSpeechOutputController(
            engine: TTSEngineManager(provider: RecordingTTSProvider(
                modelId: TTSDefaults.localModelId,
                backend: "avspeech"
            )),
            synthesizer: synthesizer,
            playerFactory: { _ in ImmediateAudioPlayer() },
            onEvent: collector.handle
        )

        let first = SynthesisRequest(
            requestId: "req-a",
            text: "First utterance",
            modelId: TTSDefaults.localModelId,
            voiceId: voice.identifier
        )
        let second = SynthesisRequest(
            requestId: "req-b",
            text: "Second utterance",
            modelId: TTSDefaults.localModelId,
            voiceId: voice.identifier
        )

        await controller.speak(first)
        let firstStarting = try await collector.wait(for: .starting, requestId: first.requestId)
        await controller.speak(second)
        _ = try await collector.wait(for: .cancelled, requestId: first.requestId)
        let secondStarting = try await collector.wait(for: .starting, requestId: second.requestId)

        synthesizer.emit(.didStart, generation: firstStarting.generation, requestId: first.requestId)
        synthesizer.emit(.didFinish, generation: firstStarting.generation, requestId: first.requestId)
        synthesizer.emit(.didCancel, generation: firstStarting.generation, requestId: first.requestId)
        try await Task.sleep(nanoseconds: 20_000_000)

        let secondPhases = collector.phases(for: second.requestId)
        #expect(!secondPhases.contains(.cancelled))
        #expect(!secondPhases.contains(.finished))
        #expect(!secondPhases.contains(.failed))
        #expect(secondPhases.contains(.starting))

        synthesizer.emit(.didStart, generation: secondStarting.generation, requestId: second.requestId)
        let playing = try await collector.wait(for: .playing, requestId: second.requestId)
        #expect(playing.generation == secondStarting.generation)
        #expect(playing.requestId == second.requestId)
    }

    @Test("generated-audio player false/failure is surfaced")
    func generatedAudioPlayerFailureIsSurfaced() async throws {
        let collector = EventCollector()
        let controller = AppleSpeechOutputController(
            engine: TTSEngineManager(provider: RecordingTTSProvider(modelId: "test-tts")),
            synthesizer: FakeSystemSpeechSynthesizer(),
            playerFactory: { _ in FailingStartAudioPlayer() },
            onEvent: collector.handle
        )

        let request = SynthesisRequest(text: "Generated bytes", modelId: "test-tts", voiceId: "test")
        await controller.speak(request)
        let failed = try await collector.wait(for: .failed, requestId: request.requestId)
        #expect(failed.error == SpeechOutputError.playerFailedToStart.localizedDescription)
        #expect(failed.synthesis.delivery == .generatedAudio)
        #expect(failed.audioOutput.kind == .generatedAudioPlayer)
        #expect(!collector.phases(for: request.requestId).contains(.playing))
    }

    @Test("generation cancellation prevents late playback")
    func generationCancellationPreventsLatePlayback() async throws {
        let provider = GatedTTSProvider(modelId: "test-tts")
        let player = ImmediateAudioPlayer()
        let collector = EventCollector()
        let controller = AppleSpeechOutputController(
            engine: TTSEngineManager(provider: provider),
            synthesizer: FakeSystemSpeechSynthesizer(),
            playerFactory: { _ in player },
            onEvent: collector.handle
        )

        let request = SynthesisRequest(text: "Hold generation", modelId: "test-tts", voiceId: "test")
        await controller.speak(request)
        _ = try await collector.wait(for: .generating, requestId: request.requestId)
        await provider.waitUntilStarted()

        await controller.cancel()
        _ = try await collector.wait(for: .cancelled, requestId: request.requestId)
        await provider.releaseSynthesis()
        try await Task.sleep(nanoseconds: 40_000_000)

        #expect(player.playCount == 0)
        #expect(await provider.didReturn)
        let phases = collector.phases(for: request.requestId)
        #expect(phases.contains(.cancelled))
        #expect(!phases.contains(.starting))
        #expect(!phases.contains(.playing))
        #expect(!phases.contains(.finished))
    }

    @Test("no global serialization across controller instances")
    func noGlobalSerializationAcrossControllerInstances() async throws {
        let provider = ConcurrencyCheckingTTSProvider(modelId: "test-tts")
        let firstCollector = EventCollector()
        let secondCollector = EventCollector()

        let first = AppleSpeechOutputController(
            engine: TTSEngineManager(provider: provider),
            synthesizer: FakeSystemSpeechSynthesizer(),
            playerFactory: { _ in ImmediateAudioPlayer() },
            onEvent: firstCollector.handle
        )
        let second = AppleSpeechOutputController(
            engine: TTSEngineManager(provider: provider),
            synthesizer: FakeSystemSpeechSynthesizer(),
            playerFactory: { _ in ImmediateAudioPlayer() },
            onEvent: secondCollector.handle
        )

        let firstRequest = SynthesisRequest(requestId: "c1", text: "one", modelId: "test-tts")
        let secondRequest = SynthesisRequest(requestId: "c2", text: "two", modelId: "test-tts")

        async let firstSpeak: Void = first.speak(firstRequest)
        async let secondSpeak: Void = second.speak(secondRequest)
        _ = await (firstSpeak, secondSpeak)

        _ = try await firstCollector.wait(for: .finished, requestId: firstRequest.requestId)
        _ = try await secondCollector.wait(for: .finished, requestId: secondRequest.requestId)
        #expect(await provider.maxConcurrentSynthesisRequests() == 2)
    }

    @Test("route capability distinguishes live system delivery from generated bytes")
    func routeCapabilityDistinguishesDelivery() {
        let live = SpeechOutputCapabilities.capability(forModelId: TTSDefaults.localModelId, backend: "avspeech")
        #expect(live.delivery == .liveSystem)
        #expect(live.audioOutput.kind == .systemSynthesizer)

        let generated = SpeechOutputCapabilities.capability(forModelId: "gpt-4o-mini-tts", backend: "openai-tts")
        #expect(generated.delivery == .generatedAudio)
        #expect(generated.audioOutput.kind == .generatedAudioPlayer)
    }

    @Test("audio session configuration stays opt-in")
    func audioSessionConfigurationIsOptIn() async throws {
        let session = RecordingAudioSession()
        let provider = RecordingTTSProvider(modelId: "test-tts")
        let collector = EventCollector()
        let withoutSession = AppleSpeechOutputController(
            engine: TTSEngineManager(provider: provider),
            synthesizer: FakeSystemSpeechSynthesizer(),
            playerFactory: { _ in ImmediateAudioPlayer() },
            onEvent: collector.handle
        )
        let request = SynthesisRequest(text: "No session", modelId: "test-tts")
        await withoutSession.speak(request)
        _ = try await collector.wait(for: .finished, requestId: request.requestId)
        #expect(session.prepareCount == 0)

        let withSessionCollector = EventCollector()
        let withSession = AppleSpeechOutputController(
            engine: TTSEngineManager(provider: RecordingTTSProvider(modelId: "test-tts")),
            synthesizer: FakeSystemSpeechSynthesizer(),
            playerFactory: { _ in ImmediateAudioPlayer() },
            audioSession: session,
            onEvent: withSessionCollector.handle
        )
        let optedIn = SynthesisRequest(text: "Session on", modelId: "test-tts")
        await withSession.speak(optedIn)
        _ = try await withSessionCollector.wait(for: .finished, requestId: optedIn.requestId)
        #expect(session.prepareCount == 1)
    }
}

private final class EventCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [SpeechOutputEvent] = []
    private var waiters: [(predicate: (SpeechOutputEvent) -> Bool, continuation: CheckedContinuation<SpeechOutputEvent, Never>)] = []

    func handle(_ event: SpeechOutputEvent) {
        lock.lock()
        events.append(event)
        if let index = waiters.firstIndex(where: { $0.predicate(event) }) {
            let waiter = waiters.remove(at: index)
            lock.unlock()
            waiter.continuation.resume(returning: event)
            return
        }
        lock.unlock()
    }

    func wait(
        for phase: SpeechOutputPhase,
        requestId: String? = nil,
        timeoutNanoseconds: UInt64 = 2_000_000_000
    ) async throws -> SpeechOutputEvent {
        try await withThrowingTaskGroup(of: SpeechOutputEvent.self) { group in
            group.addTask {
                await self.waitUnbounded(for: phase, requestId: requestId)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
                throw WaitTimeout(phase: phase, requestId: requestId)
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    func phases(for requestId: String) -> [SpeechOutputPhase] {
        snapshot.filter { $0.requestId == requestId }.map(\.phase)
    }

    var snapshot: [SpeechOutputEvent] {
        lock.lock()
        defer { lock.unlock() }
        return events
    }

    private func waitUnbounded(for phase: SpeechOutputPhase, requestId: String?) async -> SpeechOutputEvent {
        await withCheckedContinuation { continuation in
            lock.lock()
            if let existing = events.first(where: { event in
                event.phase == phase && (requestId == nil || event.requestId == requestId)
            }) {
                lock.unlock()
                continuation.resume(returning: existing)
                return
            }
            waiters.append((
                predicate: { event in
                    event.phase == phase && (requestId == nil || event.requestId == requestId)
                },
                continuation: continuation
            ))
            lock.unlock()
        }
    }
}

private struct WaitTimeout: Error, CustomStringConvertible {
    var phase: SpeechOutputPhase
    var requestId: String?
    var description: String {
        "Timed out waiting for phase \(phase.rawValue) requestId=\(requestId ?? "any")"
    }
}

private struct SpokenUtteranceSnapshot: Sendable {
    var voiceIdentifier: String?
    var prefersAssistiveTechnologySettings: Bool
}

private final class FakeSystemSpeechSynthesizer: SystemSpeechSynthesizing, @unchecked Sendable {
    private let lock = NSLock()
    private var callback: (@Sendable (SystemSpeechEvent) -> Void)?
    private var cancelled: Set<UInt64> = []
    private var utterances: [SpokenUtteranceSnapshot] = []
    private var speakWaiters: [CheckedContinuation<SpokenUtteranceSnapshot, Never>] = []
    private(set) var stopGenerations: [UInt64] = []
    private var speakingGeneration: UInt64?

    var spokenCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return utterances.count
    }

    func setCallback(_ callback: @escaping @Sendable (SystemSpeechEvent) -> Void) {
        lock.lock()
        self.callback = callback
        lock.unlock()
    }

    func speak(_ utterance: AVSpeechUtterance, generation: UInt64, requestId: String) {
        let snapshot = SpokenUtteranceSnapshot(
            voiceIdentifier: utterance.voice?.identifier,
            prefersAssistiveTechnologySettings: utterance.prefersAssistiveTechnologySettings
        )
        lock.lock()
        if cancelled.contains(generation) {
            lock.unlock()
            return
        }
        speakingGeneration = generation
        utterances.append(snapshot)
        let waiters = speakWaiters
        speakWaiters.removeAll()
        lock.unlock()
        for waiter in waiters {
            waiter.resume(returning: snapshot)
        }
    }

    func stop(generation: UInt64) {
        lock.lock()
        cancelled.insert(generation)
        stopGenerations.append(generation)
        if speakingGeneration == generation {
            speakingGeneration = nil
        }
        lock.unlock()
    }

    func waitForSpeak() async throws -> SpokenUtteranceSnapshot {
        try await withThrowingTaskGroup(of: SpokenUtteranceSnapshot.self) { group in
            group.addTask { await self.waitForSpeakUnbounded() }
            group.addTask {
                try await Task.sleep(nanoseconds: 2_000_000_000)
                throw WaitTimeout(phase: .starting, requestId: nil)
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    func emit(_ kind: SystemSpeechEvent.Kind, generation: UInt64, requestId: String) {
        lock.lock()
        let callback = self.callback
        lock.unlock()
        callback?(SystemSpeechEvent(kind: kind, generation: generation, requestId: requestId))
    }

    private func waitForSpeakUnbounded() async -> SpokenUtteranceSnapshot {
        await withCheckedContinuation { continuation in
            lock.lock()
            if let utterance = utterances.last {
                lock.unlock()
                continuation.resume(returning: utterance)
                return
            }
            speakWaiters.append(continuation)
            lock.unlock()
        }
    }
}

private final class ImmediateAudioPlayer: SpeechAudioPlaying, @unchecked Sendable {
    private let lock = NSLock()
    private var callback: (@Sendable (SpeechAudioPlayerEvent) -> Void)?
    private(set) var playCount = 0
    private(set) var stopCount = 0

    func attach(callback: @escaping @Sendable (SpeechAudioPlayerEvent) -> Void) {
        lock.lock()
        self.callback = callback
        lock.unlock()
    }

    func play() -> Bool {
        lock.lock()
        playCount += 1
        let callback = self.callback
        lock.unlock()
        callback?(.didFinish)
        return true
    }

    func stop() {
        lock.lock()
        stopCount += 1
        lock.unlock()
    }
}

private final class FailingStartAudioPlayer: SpeechAudioPlaying, @unchecked Sendable {
    func attach(callback: @escaping @Sendable (SpeechAudioPlayerEvent) -> Void) {}
    func play() -> Bool { false }
    func stop() {}
}

private final class RecordingAudioSession: SpeechAudioSessionConfiguring, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var prepareCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func prepareForSpeechOutput() throws {
        lock.lock()
        count += 1
        lock.unlock()
    }
}

private actor RecordingTTSProvider: TTSProvider {
    let modelId: String
    let backend: String
    private var count = 0

    init(modelId: String, backend: String = "test") {
        self.modelId = modelId
        self.backend = backend
    }

    func synthesizeCount() -> Int { count }

    func models() async -> [TTSModelInfo] {
        [
            TTSModelInfo(
                id: modelId,
                name: modelId,
                backend: backend,
                installed: true,
                preloaded: true,
                available: true
            )
        ]
    }

    func voices(modelId: String?) async throws -> [TTSVoiceInfo] {
        [
            TTSVoiceInfo(
                id: "test",
                name: "Test",
                backend: backend,
                modelId: modelId ?? self.modelId,
                available: true,
                isDefault: true
            )
        ]
    }

    func preload(
        modelId: String,
        voiceId: String?,
        progress: @escaping @Sendable (ModelProgress) -> Void
    ) async throws -> TTSModelInfo {
        progress(ModelProgress(modelId: modelId, progress: 1, status: "ready"))
        return TTSModelInfo(
            id: modelId,
            name: modelId,
            backend: backend,
            installed: true,
            preloaded: true,
            available: true
        )
    }

    func synthesize(_ request: SynthesisRequest) async throws -> SynthesisOutput {
        count += 1
        return Self.output(for: request)
    }

    static func output(for request: SynthesisRequest) -> SynthesisOutput {
        SynthesisOutput(
            modelId: request.modelId,
            voiceId: request.voiceId ?? "test",
            format: request.format,
            contentType: "audio/wav",
            audioData: Data("RIFF".utf8),
            elapsedMs: 10,
            metrics: SynthesisMetrics(
                traceId: "test",
                characterCount: request.text.count,
                audioDurationMs: 100,
                outputBytes: 4,
                wasPreloaded: true,
                modelCheckMs: 0,
                modelLoadMs: 0,
                voiceResolveMs: 0,
                synthesisMs: 10,
                totalMs: 10
            )
        )
    }
}

private actor GatedTTSProvider: TTSProvider {
    let modelId: String
    private var started: CheckedContinuation<Void, Never>?
    private var release: CheckedContinuation<Void, Never>?
    private var startedCount = 0
    private(set) var didReturn = false

    init(modelId: String) {
        self.modelId = modelId
    }

    func models() async -> [TTSModelInfo] {
        [
            TTSModelInfo(
                id: modelId,
                name: modelId,
                backend: "test",
                installed: true,
                preloaded: true,
                available: true
            )
        ]
    }

    func voices(modelId: String?) async throws -> [TTSVoiceInfo] {
        [
            TTSVoiceInfo(
                id: "test",
                name: "Test",
                backend: "test",
                modelId: modelId ?? self.modelId,
                available: true,
                isDefault: true
            )
        ]
    }

    func preload(
        modelId: String,
        voiceId: String?,
        progress: @escaping @Sendable (ModelProgress) -> Void
    ) async throws -> TTSModelInfo {
        progress(ModelProgress(modelId: modelId, progress: 1, status: "ready"))
        return TTSModelInfo(
            id: modelId,
            name: modelId,
            backend: "test",
            installed: true,
            preloaded: true,
            available: true
        )
    }

    func synthesize(_ request: SynthesisRequest) async throws -> SynthesisOutput {
        startedCount += 1
        started?.resume()
        started = nil
        await withCheckedContinuation { continuation in
            release = continuation
        }
        didReturn = true
        return RecordingTTSProvider.output(for: request)
    }

    func waitUntilStarted() async {
        if startedCount > 0 { return }
        await withCheckedContinuation { continuation in
            started = continuation
        }
    }

    func releaseSynthesis() {
        release?.resume()
        release = nil
    }
}

private actor ConcurrencyCheckingTTSProvider: TTSProvider {
    let modelId: String
    private var activeSynthesisRequests = 0
    private var maxActiveSynthesisRequests = 0

    init(modelId: String) {
        self.modelId = modelId
    }

    func maxConcurrentSynthesisRequests() -> Int {
        maxActiveSynthesisRequests
    }

    func models() async -> [TTSModelInfo] {
        [
            TTSModelInfo(
                id: modelId,
                name: modelId,
                backend: "test",
                installed: true,
                preloaded: true,
                available: true
            )
        ]
    }

    func voices(modelId: String?) async throws -> [TTSVoiceInfo] {
        [
            TTSVoiceInfo(
                id: "test",
                name: "Test",
                backend: "test",
                modelId: modelId ?? self.modelId,
                available: true,
                isDefault: true
            )
        ]
    }

    func preload(
        modelId: String,
        voiceId: String?,
        progress: @escaping @Sendable (ModelProgress) -> Void
    ) async throws -> TTSModelInfo {
        progress(ModelProgress(modelId: modelId, progress: 1, status: "ready"))
        return TTSModelInfo(
            id: modelId,
            name: modelId,
            backend: "test",
            installed: true,
            preloaded: true,
            available: true
        )
    }

    func synthesize(_ request: SynthesisRequest) async throws -> SynthesisOutput {
        activeSynthesisRequests += 1
        maxActiveSynthesisRequests = max(maxActiveSynthesisRequests, activeSynthesisRequests)
        try await Task.sleep(nanoseconds: 80_000_000)
        activeSynthesisRequests -= 1
        return RecordingTTSProvider.output(for: request)
    }
}
