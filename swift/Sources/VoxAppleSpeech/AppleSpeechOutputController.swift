import AVFoundation
import Foundation
import VoxCore
import VoxEngine

/// Per-audible-surface speech output controller for Apple apps.
///
/// One instance owns one audible surface. There is no process-global playback
/// mutex. `TTSProvider` / `TTSEngineManager` stay generation-only; this type
/// composes the engine for generated-audio models and uses live
/// `AVSpeechSynthesizer.speak()` for `avspeech:system`.
public actor AppleSpeechOutputController {
    private let engine: TTSEngineManager
    private let synthesizer: any SystemSpeechSynthesizing
    private let playerFactory: SpeechAudioPlayerFactory
    private let audioSession: (any SpeechAudioSessionConfiguring)?
    private let preferredLanguages: [String]
    private let onEvent: (@Sendable (SpeechOutputEvent) -> Void)?
    private let lease: PlaybackLease

    private var nextGeneration: UInt64 = 1
    private var current: Session? {
        get { lease.current }
        set { lease.current = newValue }
    }

    public init(
        engine: TTSEngineManager = TTSEngineManager(),
        synthesizer: (any SystemSpeechSynthesizing)? = nil,
        playerFactory: @escaping SpeechAudioPlayerFactory = { try AVAudioPlayerSink.make($0) },
        audioSession: (any SpeechAudioSessionConfiguring)? = nil,
        preferredLanguages: [String] = Locale.preferredLanguages,
        onEvent: (@Sendable (SpeechOutputEvent) -> Void)? = nil
    ) {
        let resolvedSynthesizer = synthesizer ?? AVSpeechSynthesizerSink()
        self.engine = engine
        self.synthesizer = resolvedSynthesizer
        self.playerFactory = playerFactory
        self.audioSession = audioSession
        self.preferredLanguages = preferredLanguages
        self.onEvent = onEvent
        self.lease = PlaybackLease(synthesizer: resolvedSynthesizer)

        resolvedSynthesizer.setCallback { [weak self] event in
            guard let self else { return }
            Task { await self.handleSystemSpeech(event) }
        }
    }

    deinit {
        lease.abandon()
    }

    /// Start speaking. A new request replaces any pending generation or playback.
    public func speak(_ request: SynthesisRequest) {
        interruptCurrent(emitting: .cancelled)

        let generation = nextGeneration
        nextGeneration += 1
        let session = Session(request: request, generation: generation, engine: engine)
        current = session
        session.task = Task { [weak self] in
            do {
                try await self?.prepare(session)
                guard !session.cancelled else { return }
                switch session.synthesis.delivery {
                case .liveSystem:
                    try await self?.speakLive(session)
                case .generatedAudio:
                    await self?.emit(.generating, for: session)
                    let output = try await session.engine.synthesize(session.request)
                    guard !session.cancelled else { return }
                    try await self?.playGenerated(session, output: output)
                }
            } catch is CancellationError {
                await self?.finishIfActive(session.generation, phase: .cancelled)
            } catch {
                await self?.finishIfActive(
                    session.generation,
                    phase: .failed,
                    error: error.localizedDescription
                )
            }
        }
    }

    /// Stop current generation and playback. Idempotent.
    public func stop() {
        interruptCurrent(emitting: .cancelled)
    }

    /// Cancel current generation and playback. Idempotent.
    ///
    /// For this controller, cancel has the same effect as stop: the in-flight
    /// `Task`, audio player, and system synthesizer are all terminated,
    /// including during the enqueue window.
    public func cancel() {
        interruptCurrent(emitting: .cancelled)
    }

    private func prepare(_ session: Session) async throws {
        guard !session.request.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SpeechOutputError.missingText
        }

        if let audioSession {
            do {
                try audioSession.prepareForSpeechOutput()
            } catch {
                throw SpeechOutputError.audioSessionFailed(error.localizedDescription)
            }
        }

        let models = await engine.models()
        guard isActive(session.generation) else { return }

        let model = models.first { $0.id == session.request.modelId }
        let delivery = SpeechOutputCapabilities.delivery(
            forModelId: session.request.modelId,
            backend: model?.backend
        )
        session.synthesis = SpeechSynthesisIdentity(
            requestedModelId: session.request.modelId,
            modelId: session.request.modelId,
            requestedVoiceId: session.request.voiceId,
            voiceId: session.request.voiceId,
            backend: model?.backend,
            delivery: delivery
        )
        session.audioOutput = SpeechOutputCapabilities.audioOutput(for: delivery)
    }

    private func speakLive(_ session: Session) async throws {
        emit(.resolving, for: session)
        let voice = try resolveSystemVoice(voiceId: session.request.voiceId)
        guard isActive(session.generation) else { return }

        session.synthesis.voiceId = voice.identifier
        if session.synthesis.backend == nil {
            session.synthesis.backend = "avspeech"
        }

        let utterance = AVSpeechUtterance(string: session.request.text)
        utterance.voice = voice
        utterance.prefersAssistiveTechnologySettings = false
        if let speed = session.request.speed {
            utterance.rate = SpeechOutputRate.map(
                speed: speed,
                minimum: AVSpeechUtteranceMinimumSpeechRate,
                defaultRate: AVSpeechUtteranceDefaultSpeechRate,
                maximum: AVSpeechUtteranceMaximumSpeechRate
            )
        }

        guard isActive(session.generation) else { return }
        emit(.starting, for: session)
        guard isActive(session.generation) else { return }
        synthesizer.speak(
            utterance,
            generation: session.generation,
            requestId: session.request.requestId
        )
    }

    private func playGenerated(_ session: Session, output: SynthesisOutput) async throws {
        guard isActive(session.generation) else { return }

        session.synthesis.modelId = output.modelId
        session.synthesis.voiceId = output.voiceId

        emit(.starting, for: session)
        guard isActive(session.generation) else { return }

        let player: any SpeechAudioPlaying
        do {
            player = try playerFactory(output.audioData)
        } catch {
            throw SpeechOutputError.playerFactoryFailed(error.localizedDescription)
        }

        let generation = session.generation
        player.attach { [weak self] event in
            guard let self else { return }
            Task { await self.handlePlayer(event, generation: generation) }
        }
        session.player = player

        guard isActive(session.generation) else {
            detachPlayer(session)
            return
        }

        let started = player.play()
        if !isActive(session.generation) {
            detachPlayer(session)
            return
        }
        guard started else {
            detachPlayer(session)
            throw SpeechOutputError.playerFailedToStart
        }

        emit(.playing, for: session)
    }

    private func handleSystemSpeech(_ event: SystemSpeechEvent) {
        switch event.kind {
        case .didStart:
            guard isActive(event.generation), let session = current else {
                synthesizer.stop(generation: event.generation)
                return
            }
            emit(.playing, for: session)
        case .didFinish:
            finishIfActive(event.generation, phase: .finished)
        case .didCancel:
            finishIfActive(event.generation, phase: .cancelled)
        }
    }

    private func handlePlayer(_ event: SpeechAudioPlayerEvent, generation: UInt64) {
        switch event {
        case .didFinish:
            finishIfActive(generation, phase: .finished)
        case .didFail(let message):
            finishIfActive(generation, phase: .failed, error: SpeechOutputError.playerFailed(message).localizedDescription)
        }
    }

    private func interruptCurrent(emitting phase: SpeechOutputPhase) {
        guard let session = current else { return }
        abandon(session)
        emit(phase, for: session)
        current = nil
    }

    private func finishIfActive(
        _ generation: UInt64,
        phase: SpeechOutputPhase,
        error: String? = nil
    ) {
        guard isActive(generation), let session = current else { return }
        abandon(session)
        emit(phase, for: session, error: error)
        current = nil
    }

    private func abandon(_ session: Session) {
        session.cancelled = true
        session.task?.cancel()
        session.task = nil
        synthesizer.stop(generation: session.generation)
        detachPlayer(session)
    }

    private func detachPlayer(_ session: Session) {
        guard let player = session.player else { return }
        player.stop()
        player.detach()
        session.player = nil
    }

    private func isActive(_ generation: UInt64) -> Bool {
        guard let session = current else { return false }
        return session.generation == generation && !session.cancelled
    }

    private func emit(_ phase: SpeechOutputPhase, for session: Session, error: String? = nil) {
        let event = SpeechOutputEvent(
            requestId: session.request.requestId,
            generation: session.generation,
            phase: phase,
            synthesis: session.synthesis,
            audioOutput: session.audioOutput,
            error: error
        )
        onEvent?(event)
    }

    private func resolveSystemVoice(voiceId: String?) throws -> AVSpeechSynthesisVoice {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        let descriptors = voices.map {
            SystemVoiceDescriptor(identifier: $0.identifier, language: $0.language)
        }
        let picked = try SystemVoiceResolver.resolve(
            voiceId: voiceId,
            voices: descriptors,
            preferredLanguages: preferredLanguages
        )
        if let voice = voices.first(where: { $0.identifier == picked.identifier }) {
            return voice
        }
        throw SpeechOutputError.unsupportedVoice(picked.identifier)
    }
}

private final class PlaybackLease: @unchecked Sendable {
    private let lock = NSLock()
    private let synthesizer: any SystemSpeechSynthesizing
    private var session: Session?

    init(synthesizer: any SystemSpeechSynthesizing) {
        self.synthesizer = synthesizer
    }

    var current: Session? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return session
        }
        set {
            lock.lock()
            session = newValue
            lock.unlock()
        }
    }

    func abandon() {
        lock.lock()
        let session = self.session
        self.session = nil
        lock.unlock()
        guard let session else { return }
        session.cancelled = true
        session.task?.cancel()
        session.task = nil
        session.player?.stop()
        session.player?.detach()
        session.player = nil
        synthesizer.stop(generation: session.generation)
    }

    deinit {
        abandon()
    }
}

private final class Session: @unchecked Sendable {
    let request: SynthesisRequest
    let generation: UInt64
    let engine: TTSEngineManager
    private let lock = NSLock()
    private var _cancelled = false
    var task: Task<Void, Never>?
    var player: (any SpeechAudioPlaying)?
    var synthesis: SpeechSynthesisIdentity
    var audioOutput: SpeechAudioOutputRoute

    var cancelled: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _cancelled
        }
        set {
            lock.lock()
            _cancelled = newValue
            lock.unlock()
        }
    }

    init(request: SynthesisRequest, generation: UInt64, engine: TTSEngineManager) {
        self.request = request
        self.generation = generation
        self.engine = engine
        let capability = SpeechOutputCapabilities.capability(forModelId: request.modelId)
        self.synthesis = SpeechSynthesisIdentity(
            requestedModelId: request.modelId,
            modelId: request.modelId,
            requestedVoiceId: request.voiceId,
            voiceId: request.voiceId,
            delivery: capability.delivery
        )
        self.audioOutput = capability.audioOutput
    }
}
