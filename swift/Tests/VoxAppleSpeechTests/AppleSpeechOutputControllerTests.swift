import AVFoundation
import Foundation
import Testing
import VoxCore
import VoxEngine
@testable import VoxAppleSpeech

@Suite(.serialized)
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
        #expect(starting.synthesis.requestedModelId == TTSDefaults.localModelId)
        #expect(starting.synthesis.requestedVoiceId == voice.identifier)
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
        #expect(collector.terminalCount(for: request.requestId) == 1)
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
        #expect(collector.terminalCount(for: first.requestId) == 1)

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
        #expect(collector.terminalCount(for: request.requestId) == 1)
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
        #expect(collector.terminalCount(for: request.requestId) == 1)
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
        #expect(firstCollector.terminalCount(for: firstRequest.requestId) == 1)
        #expect(secondCollector.terminalCount(for: secondRequest.requestId) == 1)
    }

    @Test("route capability distinguishes live system delivery from generated bytes")
    func routeCapabilityDistinguishesDelivery() {
        let live = SpeechOutputCapabilities.capability(forModelId: TTSDefaults.localModelId, backend: "avspeech")
        #expect(live.delivery == .liveSystem)
        #expect(live.audioOutput.kind == .systemSynthesizer)

        let generated = SpeechOutputCapabilities.capability(forModelId: "gpt-4o-mini-tts", backend: "openai")
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

    @Test("generated-player replacement ignores stale finish and failure")
    func generatedPlayerReplacementIgnoresStaleFinishAndFailure() async throws {
        let firstPlayer = HeldAudioPlayer()
        let secondPlayer = HeldAudioPlayer()
        let players = LockedBox(value: [firstPlayer, secondPlayer])
        let collector = EventCollector()
        let controller = AppleSpeechOutputController(
            engine: TTSEngineManager(provider: RecordingTTSProvider(modelId: "test-tts")),
            synthesizer: FakeSystemSpeechSynthesizer(),
            playerFactory: { _ in
                var next: HeldAudioPlayer!
                players.mutate { queue in
                    next = queue.removeFirst()
                }
                return next
            },
            onEvent: collector.handle
        )

        let first = SynthesisRequest(requestId: "gen-a", text: "first", modelId: "test-tts", voiceId: "one")
        let second = SynthesisRequest(requestId: "gen-b", text: "second", modelId: "test-tts", voiceId: "two")
        await controller.speak(first)
        _ = try await collector.wait(for: .playing, requestId: first.requestId)
        await controller.speak(second)
        _ = try await collector.wait(for: .cancelled, requestId: first.requestId)
        _ = try await collector.wait(for: .playing, requestId: second.requestId)

        firstPlayer.emit(.didFinish)
        firstPlayer.emit(.didFail("stale decode"))
        try await Task.sleep(nanoseconds: 20_000_000)

        #expect(!collector.phases(for: second.requestId).contains(.finished))
        #expect(!collector.phases(for: second.requestId).contains(.failed))
        #expect(collector.terminalCount(for: first.requestId) == 1)

        secondPlayer.emit(.didFinish)
        _ = try await collector.wait(for: .finished, requestId: second.requestId)
        #expect(collector.terminalCount(for: second.requestId) == 1)
    }

    @Test("player is deallocated after terminal cleanup")
    func playerIsDeallocatedAfterTerminalCleanup() async throws {
        let flag = DeinitFlag()
        let collector = EventCollector()
        let playerBox = LockedBox<TrackingAudioPlayer?>(value: nil)
        let controller = AppleSpeechOutputController(
            engine: TTSEngineManager(provider: RecordingTTSProvider(modelId: "test-tts")),
            synthesizer: FakeSystemSpeechSynthesizer(),
            playerFactory: { _ in
                let player = TrackingAudioPlayer(flag: flag)
                playerBox.replace(player)
                return player
            },
            onEvent: collector.handle
        )

        let request = SynthesisRequest(text: "track lifetime", modelId: "test-tts")
        await controller.speak(request)
        _ = try await collector.wait(for: .playing, requestId: request.requestId)
        playerBox.value?.emit(.didFinish)
        _ = try await collector.wait(for: .finished, requestId: request.requestId)
        playerBox.replace(nil)

        try await waitUntil { flag.isSet }
        #expect(flag.isSet)
        #expect(collector.terminalCount(for: request.requestId) == 1)
    }

    @Test("events preserve requested versus actual model and voice")
    func eventsPreserveRequestedVersusActualIdentity() async throws {
        let collector = EventCollector()
        let controller = AppleSpeechOutputController(
            engine: TTSEngineManager(provider: RecordingTTSProvider(
                modelId: "requested-tts",
                backend: "openai",
                actualModelId: "actual-tts",
                actualVoiceId: "actual-voice"
            )),
            synthesizer: FakeSystemSpeechSynthesizer(),
            playerFactory: { _ in ImmediateAudioPlayer() },
            onEvent: collector.handle
        )

        let request = SynthesisRequest(
            text: "identity",
            modelId: "requested-tts",
            voiceId: "requested-voice"
        )
        await controller.speak(request)
        let finished = try await collector.wait(for: .finished, requestId: request.requestId)
        #expect(finished.synthesis.requestedModelId == "requested-tts")
        #expect(finished.synthesis.modelId == "actual-tts")
        #expect(finished.synthesis.requestedVoiceId == "requested-voice")
        #expect(finished.synthesis.voiceId == "actual-voice")
        #expect(finished.synthesis.backend == "openai")
        #expect(finished.audioOutput.kind == .generatedAudioPlayer)
    }

    @Test("audio-session failure is surfaced")
    func audioSessionFailureIsSurfaced() async throws {
        let collector = EventCollector()
        let controller = AppleSpeechOutputController(
            engine: TTSEngineManager(provider: RecordingTTSProvider(modelId: "test-tts")),
            synthesizer: FakeSystemSpeechSynthesizer(),
            playerFactory: { _ in ImmediateAudioPlayer() },
            audioSession: FailingAudioSession(message: "session exploded"),
            onEvent: collector.handle
        )
        let request = SynthesisRequest(text: "session fail", modelId: "test-tts")
        await controller.speak(request)
        let failed = try await collector.wait(for: .failed, requestId: request.requestId)
        #expect(failed.error == SpeechOutputError.audioSessionFailed("session exploded").localizedDescription)
        #expect(collector.terminalCount(for: request.requestId) == 1)
    }

    @Test("generation failure is surfaced")
    func generationFailureIsSurfaced() async throws {
        let collector = EventCollector()
        let controller = AppleSpeechOutputController(
            engine: TTSEngineManager(provider: FailingTTSProvider(modelId: "test-tts", message: "upstream down")),
            synthesizer: FakeSystemSpeechSynthesizer(),
            playerFactory: { _ in ImmediateAudioPlayer() },
            onEvent: collector.handle
        )
        let request = SynthesisRequest(text: "gen fail", modelId: "test-tts")
        await controller.speak(request)
        let failed = try await collector.wait(for: .failed, requestId: request.requestId)
        #expect(failed.error == SpeechOutputError.generationFailed("upstream down").localizedDescription)
        #expect(collector.terminalCount(for: request.requestId) == 1)
    }

    @Test("unsupported system voice is surfaced")
    func unsupportedSystemVoiceIsSurfaced() async throws {
        let collector = EventCollector()
        let controller = AppleSpeechOutputController(
            engine: TTSEngineManager(provider: RecordingTTSProvider(
                modelId: TTSDefaults.localModelId,
                backend: "avspeech"
            )),
            synthesizer: FakeSystemSpeechSynthesizer(),
            playerFactory: { _ in ImmediateAudioPlayer() },
            onEvent: collector.handle
        )
        let request = SynthesisRequest(
            text: "missing voice",
            modelId: TTSDefaults.localModelId,
            voiceId: "not.a.real.voice"
        )
        await controller.speak(request)
        let failed = try await collector.wait(for: .failed, requestId: request.requestId)
        #expect(failed.error == SpeechOutputError.unsupportedVoice("not.a.real.voice").localizedDescription)
        #expect(collector.terminalCount(for: request.requestId) == 1)
    }

    @Test("player factory and decode failures are surfaced")
    func playerFactoryAndDecodeFailuresAreSurfaced() async throws {
        let factoryCollector = EventCollector()
        let factoryController = AppleSpeechOutputController(
            engine: TTSEngineManager(provider: RecordingTTSProvider(modelId: "test-tts")),
            synthesizer: FakeSystemSpeechSynthesizer(),
            playerFactory: { _ in throw TestFailure("bad wav") },
            onEvent: factoryCollector.handle
        )
        let factoryRequest = SynthesisRequest(text: "factory", modelId: "test-tts")
        await factoryController.speak(factoryRequest)
        let factoryFailed = try await factoryCollector.wait(for: .failed, requestId: factoryRequest.requestId)
        #expect(factoryFailed.error == SpeechOutputError.playerFactoryFailed("bad wav").localizedDescription)
        #expect(factoryCollector.terminalCount(for: factoryRequest.requestId) == 1)

        let player = HeldAudioPlayer()
        let decodeCollector = EventCollector()
        let decodeController = AppleSpeechOutputController(
            engine: TTSEngineManager(provider: RecordingTTSProvider(modelId: "test-tts")),
            synthesizer: FakeSystemSpeechSynthesizer(),
            playerFactory: { _ in player },
            onEvent: decodeCollector.handle
        )
        let decodeRequest = SynthesisRequest(text: "decode", modelId: "test-tts")
        await decodeController.speak(decodeRequest)
        _ = try await decodeCollector.wait(for: .playing, requestId: decodeRequest.requestId)
        player.emit(.didFail("decode exploded"))
        let decodeFailed = try await decodeCollector.wait(for: .failed, requestId: decodeRequest.requestId)
        #expect(decodeFailed.error == SpeechOutputError.playerFailed("decode exploded").localizedDescription)
        #expect(decodeCollector.terminalCount(for: decodeRequest.requestId) == 1)
    }

    @Test("speed 1.0 maps to the platform default utterance rate")
    func speedOneMapsToDefaultUtteranceRate() async throws {
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
            text: "default rate",
            modelId: TTSDefaults.localModelId,
            voiceId: voice.identifier,
            speed: 1.0
        )
        await controller.speak(request)
        let spoken = try await synthesizer.waitForSpeak()
        #expect(spoken.rate == AVSpeechUtteranceDefaultSpeechRate)
        _ = try await collector.wait(for: .starting, requestId: request.requestId)
    }

    @Test("dropping the controller during generation prevents late playback")
    func droppingControllerDuringGenerationPreventsLatePlayback() async throws {
        let provider = GatedTTSProvider(modelId: "test-tts")
        let player = ImmediateAudioPlayer()
        let collector = EventCollector()
        var controller: AppleSpeechOutputController? = AppleSpeechOutputController(
            engine: TTSEngineManager(provider: provider),
            synthesizer: FakeSystemSpeechSynthesizer(),
            playerFactory: { _ in player },
            onEvent: collector.handle
        )

        let request = SynthesisRequest(text: "drop during generate", modelId: "test-tts")
        await controller!.speak(request)
        _ = try await collector.wait(for: .generating, requestId: request.requestId)
        await provider.waitUntilStarted()

        let weakBox = WeakControllerBox(controller)
        controller = nil
        try await waitUntil { weakBox.isNil }

        await provider.releaseSynthesis()
        try await Task.sleep(nanoseconds: 40_000_000)

        #expect(player.playCount == 0)
        #expect(!collector.phases(for: request.requestId).contains(.playing))
        #expect(!collector.phases(for: request.requestId).contains(.finished))
    }

    @Test("each request emits exactly one terminal event")
    func eachRequestEmitsExactlyOneTerminalEvent() async throws {
        let collector = EventCollector()
        let controller = AppleSpeechOutputController(
            engine: TTSEngineManager(provider: RecordingTTSProvider(modelId: "test-tts")),
            synthesizer: FakeSystemSpeechSynthesizer(),
            playerFactory: { _ in ImmediateAudioPlayer() },
            onEvent: collector.handle
        )
        let finished = SynthesisRequest(requestId: "term-finish", text: "done", modelId: "test-tts")
        await controller.speak(finished)
        _ = try await collector.wait(for: .finished, requestId: finished.requestId)
        await controller.stop()
        await controller.cancel()
        try await Task.sleep(nanoseconds: 20_000_000)
        #expect(collector.terminalCount(for: finished.requestId) == 1)
    }
}

@Suite(.serialized)
struct AVSpeechSynthesizerSinkTests {
    @Test("production enqueue stop is recorded before queued speak runs")
    func productionEnqueueStopIsRecordedBeforeQueuedSpeakRuns() {
        let scheduler = DeferredSpeechWorkScheduler()
        let engine = RecordingSpeechEngine()
        let sink = AVSpeechSynthesizerSink(engine: engine, scheduler: scheduler)
        let utterance = AVSpeechUtterance(string: "queued")

        sink.speak(utterance, generation: 1, requestId: "enqueue")
        #expect(engine.speakCount == 0)
        sink.stop(generation: 1)
        #expect(!sink.hasPendingGeneration(1))
        scheduler.flush()

        #expect(engine.speakCount == 0)
        #expect(engine.stopCount == 1)
    }

    @Test("queued speak still runs when stop targets a different generation")
    func queuedSpeakRunsForUncancelledGeneration() {
        let scheduler = DeferredSpeechWorkScheduler()
        let engine = RecordingSpeechEngine()
        let sink = AVSpeechSynthesizerSink(engine: engine, scheduler: scheduler)
        let utterance = AVSpeechUtterance(string: "keep")

        sink.speak(utterance, generation: 2, requestId: "keep")
        sink.stop(generation: 1)
        #expect(!sink.hasPendingGeneration(1))
        #expect(sink.hasPendingGeneration(2))
        scheduler.flush()

        #expect(engine.speakCount == 1)
        #expect(engine.stopCount == 0)
    }

    @Test("plain utterances emit events from speak metadata")
    func plainUtterancesEmitEventsFromSpeakMetadata() {
        let scheduler = DeferredSpeechWorkScheduler()
        let engine = RecordingSpeechEngine()
        let sink = AVSpeechSynthesizerSink(engine: engine, scheduler: scheduler)
        let utterance = AVSpeechUtterance(string: "plain")
        let collector = EventCollector()
        sink.setCallback(collector.handleEvent)

        sink.speak(utterance, generation: 9, requestId: "meta")
        scheduler.flush()
        sink.handleEngineEvent(.didStart, identifier: ObjectIdentifier(utterance))
        sink.handleEngineEvent(.didFinish, identifier: ObjectIdentifier(utterance))

        #expect(collector.snapshot.map(\.phase) == [])
        #expect(collector.systemEvents.map(\.kind) == [.didStart, .didFinish])
        #expect(collector.systemEvents.map(\.generation) == [9, 9])
        #expect(collector.systemEvents.map(\.requestId) == ["meta", "meta"])
    }

    @Test("finish and cancel clear speaking generation so a later stop is not suppressed")
    func finishClearsSpeakingGeneration() {
        let scheduler = DeferredSpeechWorkScheduler()
        let engine = RecordingSpeechEngine()
        let sink = AVSpeechSynthesizerSink(engine: engine, scheduler: scheduler)
        let first = AVSpeechUtterance(string: "one")
        let second = AVSpeechUtterance(string: "two")

        sink.speak(first, generation: 1, requestId: "one")
        scheduler.flush()
        #expect(sink.currentSpeakingGeneration == 1)
        sink.handleEngineEvent(.didFinish, identifier: ObjectIdentifier(first))
        #expect(sink.currentSpeakingGeneration == nil)
        sink.speak(second, generation: 2, requestId: "two")
        sink.stop(generation: 2)
        scheduler.flush()

        #expect(engine.speakCount == 1)
        #expect(engine.stopCount == 1)
        #expect(sink.currentSpeakingGeneration == nil)
    }

    @Test("more than 32 queued replacements cannot revive a stale speak")
    func moreThan32QueuedReplacementsCannotReviveStaleSpeak() {
        let scheduler = DeferredSpeechWorkScheduler()
        let engine = RecordingSpeechEngine()
        let sink = AVSpeechSynthesizerSink(engine: engine, scheduler: scheduler)

        var utterances: [AVSpeechUtterance] = []
        utterances.reserveCapacity(41)
        for generation in 1...40 {
            let utterance = AVSpeechUtterance(string: "gen-\(generation)")
            utterances.append(utterance)
            sink.speak(utterance, generation: UInt64(generation), requestId: "req-\(generation)")
            sink.stop(generation: UInt64(generation))
            #expect(!sink.hasPendingGeneration(UInt64(generation)))
        }

        let live = AVSpeechUtterance(string: "live")
        utterances.append(live)
        sink.speak(live, generation: 41, requestId: "live")
        #expect(sink.hasPendingGeneration(41))
        scheduler.flush()

        #expect(engine.speakCount == 1)
        #expect(sink.currentSpeakingGeneration == 41)
        #expect(!sink.hasPendingGeneration(1))
        #expect(!sink.hasPendingGeneration(8))
        #expect(sink.hasPendingGeneration(41))
    }

    @Test("started generation keeps metadata after stop until the terminal event")
    func startedGenerationKeepsMetadataAfterStopUntilTerminalEvent() {
        let scheduler = DeferredSpeechWorkScheduler()
        let engine = RecordingSpeechEngine()
        let sink = AVSpeechSynthesizerSink(engine: engine, scheduler: scheduler)
        let utterance = AVSpeechUtterance(string: "started")
        let collector = EventCollector()
        sink.setCallback(collector.handleEvent)

        sink.speak(utterance, generation: 4, requestId: "started")
        scheduler.flush()
        #expect(sink.hasPendingGeneration(4))
        #expect(sink.currentSpeakingGeneration == 4)

        sink.stop(generation: 4)
        #expect(sink.hasPendingGeneration(4))
        scheduler.flush()

        sink.handleEngineEvent(.didStart, identifier: ObjectIdentifier(utterance))
        #expect(collector.systemEvents.map(\.kind) == [.didStart])
        #expect(collector.systemEvents.first?.generation == 4)

        sink.handleEngineEvent(.didCancel, identifier: ObjectIdentifier(utterance))
        #expect(!sink.hasPendingGeneration(4))
    }
}

private struct TestFailure: Error, LocalizedError {
    var message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

private final class EventCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [SpeechOutputEvent] = []
    private var rawSystemEvents: [SystemSpeechEvent] = []

    func handle(_ event: SpeechOutputEvent) {
        lock.lock()
        events.append(event)
        lock.unlock()
    }

    func handleEvent(_ event: SystemSpeechEvent) {
        lock.lock()
        rawSystemEvents.append(event)
        lock.unlock()
    }

    func wait(
        for phase: SpeechOutputPhase,
        requestId: String? = nil,
        timeoutNanoseconds: UInt64 = 2_000_000_000
    ) async throws -> SpeechOutputEvent {
        let step: UInt64 = 5_000_000
        var waited: UInt64 = 0
        while waited <= timeoutNanoseconds {
            if Task.isCancelled { throw CancellationError() }
            if let existing = snapshot.first(where: { event in
                event.phase == phase && (requestId == nil || event.requestId == requestId)
            }) {
                return existing
            }
            try await Task.sleep(nanoseconds: step)
            waited += step
        }
        throw WaitTimeout(phase: phase, requestId: requestId)
    }

    func phases(for requestId: String) -> [SpeechOutputPhase] {
        snapshot.filter { $0.requestId == requestId }.map(\.phase)
    }

    func terminalCount(for requestId: String) -> Int {
        phases(for: requestId).filter { phase in
            phase == .finished || phase == .cancelled || phase == .failed
        }.count
    }

    var snapshot: [SpeechOutputEvent] {
        lock.lock()
        defer { lock.unlock() }
        return events
    }

    var systemEvents: [SystemSpeechEvent] {
        lock.lock()
        defer { lock.unlock() }
        return rawSystemEvents
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
    var rate: Float
}

private final class FakeSystemSpeechSynthesizer: SystemSpeechSynthesizing, @unchecked Sendable {
    private let lock = NSLock()
    private var callback: (@Sendable (SystemSpeechEvent) -> Void)?
    private var cancelled: Set<UInt64> = []
    private var utterances: [SpokenUtteranceSnapshot] = []
    private(set) var stopGenerations: [UInt64] = []
    private var speakingGeneration: UInt64?

    var spokenCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return utterances.count
    }

    private var lastSpoken: SpokenUtteranceSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        return utterances.last
    }

    func setCallback(_ callback: @escaping @Sendable (SystemSpeechEvent) -> Void) {
        lock.lock()
        self.callback = callback
        lock.unlock()
    }

    func speak(_ utterance: AVSpeechUtterance, generation: UInt64, requestId: String) {
        let snapshot = SpokenUtteranceSnapshot(
            voiceIdentifier: utterance.voice?.identifier,
            prefersAssistiveTechnologySettings: utterance.prefersAssistiveTechnologySettings,
            rate: utterance.rate
        )
        lock.lock()
        if cancelled.contains(generation) {
            lock.unlock()
            return
        }
        speakingGeneration = generation
        utterances.append(snapshot)
        lock.unlock()
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
        let step: UInt64 = 5_000_000
        var waited: UInt64 = 0
        while waited <= 2_000_000_000 {
            if Task.isCancelled { throw CancellationError() }
            if let spoken = lastSpoken {
                return spoken
            }
            try await Task.sleep(nanoseconds: step)
            waited += step
        }
        throw WaitTimeout(phase: .starting, requestId: nil)
    }

    func emit(_ kind: SystemSpeechEvent.Kind, generation: UInt64, requestId: String) {
        lock.lock()
        let callback = self.callback
        lock.unlock()
        callback?(SystemSpeechEvent(kind: kind, generation: generation, requestId: requestId))
    }
}

private class BaseAudioPlayer: SpeechAudioPlaying, @unchecked Sendable {
    private let lock = NSLock()
    private var callback: (@Sendable (SpeechAudioPlayerEvent) -> Void)?
    private(set) var playCount = 0
    private(set) var stopCount = 0

    func attach(callback: @escaping @Sendable (SpeechAudioPlayerEvent) -> Void) {
        lock.lock()
        self.callback = callback
        lock.unlock()
    }

    func detach() {
        lock.lock()
        callback = nil
        lock.unlock()
    }

    func play() -> Bool {
        lock.lock()
        playCount += 1
        lock.unlock()
        return true
    }

    func stop() {
        lock.lock()
        stopCount += 1
        lock.unlock()
    }

    func emit(_ event: SpeechAudioPlayerEvent) {
        lock.lock()
        let callback = self.callback
        lock.unlock()
        callback?(event)
    }
}

private final class ImmediateAudioPlayer: BaseAudioPlayer, @unchecked Sendable {
    override func play() -> Bool {
        let started = super.play()
        emit(.didFinish)
        return started
    }
}

private final class HeldAudioPlayer: BaseAudioPlayer, @unchecked Sendable {}

private final class TrackingAudioPlayer: BaseAudioPlayer, @unchecked Sendable {
    private let flag: DeinitFlag

    init(flag: DeinitFlag) {
        self.flag = flag
    }

    deinit {
        flag.mark()
    }
}

private final class FailingStartAudioPlayer: SpeechAudioPlaying, @unchecked Sendable {
    func attach(callback: @escaping @Sendable (SpeechAudioPlayerEvent) -> Void) {}
    func detach() {}
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

private struct FailingAudioSession: SpeechAudioSessionConfiguring {
    var message: String

    func prepareForSpeechOutput() throws {
        throw TestFailure(message)
    }
}

private final class DeinitFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func mark() {
        lock.lock()
        value = true
        lock.unlock()
    }
}

private final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value

    init(value: Value) {
        storage = value
    }

    var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func replace(_ value: Value) {
        lock.lock()
        storage = value
        lock.unlock()
    }

    func mutate(_ body: (inout Value) -> Void) {
        lock.lock()
        body(&storage)
        lock.unlock()
    }
}

private final class DeferredSpeechWorkScheduler: SpeechWorkScheduling, @unchecked Sendable {
    private let lock = NSLock()
    private var pending: [@Sendable () -> Void] = []

    func enqueue(_ work: @escaping @Sendable () -> Void) {
        lock.lock()
        pending.append(work)
        lock.unlock()
    }

    func flush() {
        lock.lock()
        let work = pending
        pending.removeAll()
        lock.unlock()
        for item in work {
            item()
        }
    }
}

private final class RecordingSpeechEngine: SpeechSynthesizerEngine, @unchecked Sendable {
    private let lock = NSLock()
    private var speaks = 0
    private var stops = 0

    var speakCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return speaks
    }

    var stopCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return stops
    }

    func speak(_ utterance: AVSpeechUtterance) {
        lock.lock()
        speaks += 1
        lock.unlock()
    }

    func stopSpeaking() {
        lock.lock()
        stops += 1
        lock.unlock()
    }
}

private actor RecordingTTSProvider: TTSProvider {
    let modelId: String
    let backend: String
    let actualModelId: String
    let actualVoiceId: String
    private var count = 0

    init(
        modelId: String,
        backend: String = "test",
        actualModelId: String? = nil,
        actualVoiceId: String = "test"
    ) {
        self.modelId = modelId
        self.backend = backend
        self.actualModelId = actualModelId ?? modelId
        self.actualVoiceId = actualVoiceId
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
                id: actualVoiceId,
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
        return Self.output(
            for: request,
            modelId: actualModelId,
            voiceId: actualVoiceId
        )
    }

    static func output(
        for request: SynthesisRequest,
        modelId: String? = nil,
        voiceId: String? = nil
    ) -> SynthesisOutput {
        SynthesisOutput(
            modelId: modelId ?? request.modelId,
            voiceId: voiceId ?? request.voiceId ?? "test",
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

private actor FailingTTSProvider: TTSProvider {
    let modelId: String
    let message: String

    init(modelId: String, message: String) {
        self.modelId = modelId
        self.message = message
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
        throw TestFailure(message)
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

private final class WeakControllerBox: @unchecked Sendable {
    private let lock = NSLock()
    private weak var value: AppleSpeechOutputController?

    init(_ value: AppleSpeechOutputController?) {
        self.value = value
    }

    var isNil: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value == nil
    }
}

private func waitUntil(
    timeoutNanoseconds: UInt64 = 2_000_000_000,
    _ predicate: @Sendable () -> Bool
) async throws {
    let step: UInt64 = 5_000_000
    var waited: UInt64 = 0
    while waited <= timeoutNanoseconds {
        if Task.isCancelled { throw CancellationError() }
        if predicate() { return }
        try await Task.sleep(nanoseconds: step)
        waited += step
    }
    throw WaitTimeout(phase: .finished, requestId: nil)
}
