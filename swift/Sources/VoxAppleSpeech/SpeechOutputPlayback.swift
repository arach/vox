import AVFoundation
import Foundation

public struct SystemSpeechEvent: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case didStart
        case didFinish
        case didCancel
    }

    public var kind: Kind
    public var generation: UInt64
    public var requestId: String

    public init(kind: Kind, generation: UInt64, requestId: String) {
        self.kind = kind
        self.generation = generation
        self.requestId = requestId
    }
}

public enum SpeechAudioPlayerEvent: Sendable, Equatable {
    case didFinish
    case didFail(String)
}

/// Live system speech sink. Implementations must honor `stop` during the
/// enqueue window so a cancelled generation never becomes audible.
public protocol SystemSpeechSynthesizing: AnyObject, Sendable {
    func setCallback(_ callback: @escaping @Sendable (SystemSpeechEvent) -> Void)
    func speak(_ utterance: AVSpeechUtterance, generation: UInt64, requestId: String)
    func stop(generation: UInt64)
}

/// Generated-audio sink. `play()` returning `false` is a failure.
/// `detach()` clears the callback and must not retain the owning session.
public protocol SpeechAudioPlaying: AnyObject, Sendable {
    func attach(callback: @escaping @Sendable (SpeechAudioPlayerEvent) -> Void)
    func detach()
    func play() -> Bool
    func stop()
}

public typealias SpeechAudioPlayerFactory = @Sendable (Data) throws -> any SpeechAudioPlaying

/// Opt-in audio-session configuration. Controllers do not configure a session
/// unless the caller injects one.
public protocol SpeechAudioSessionConfiguring: Sendable {
    func prepareForSpeechOutput() throws
}

protocol SpeechWorkScheduling: AnyObject, Sendable {
    func enqueue(_ work: @escaping @Sendable () -> Void)
}

protocol SpeechSynthesizerEngine: AnyObject, Sendable {
    func speak(_ utterance: AVSpeechUtterance)
    func stopSpeaking()
}

private struct UncheckedSpeechUtterance: @unchecked Sendable {
    let utterance: AVSpeechUtterance
}

private struct TrackedUtterance {
    let utterance: AVSpeechUtterance
    let generation: UInt64
    let requestId: String
    var cancelled: Bool
}

final class MainQueueSpeechWorkScheduler: SpeechWorkScheduling, @unchecked Sendable {
    func enqueue(_ work: @escaping @Sendable () -> Void) {
        DispatchQueue.main.async(execute: work)
    }
}

final class AVFoundationSpeechSynthesizerEngine: SpeechSynthesizerEngine, @unchecked Sendable {
    let synthesizer = AVSpeechSynthesizer()

    func speak(_ utterance: AVSpeechUtterance) {
        synthesizer.speak(utterance)
    }

    func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}

/// Production live-speech sink. Cancellation is recorded under the lock before
/// `stopSpeaking` is queued so a generation stopped during the enqueue window
/// cannot become audible. Speak/stop always hop through the scheduler; there
/// is no main-thread fast path. Utterance metadata is tracked explicitly, so
/// ordinary `AVSpeechUtterance` values still emit generation and request identity.
final class AVSpeechSynthesizerSink: NSObject, SystemSpeechSynthesizing, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    private let engine: any SpeechSynthesizerEngine
    private let scheduler: any SpeechWorkScheduling
    private let lock = NSLock()
    private var callback: (@Sendable (SystemSpeechEvent) -> Void)?
    private var speakingGeneration: UInt64?
    /// Queued speak proceeds only while this entry remains. `stop(generation:)`
    /// removes matching entries, so rapid replacements cannot revive a stale
    /// generation after a bounded cancel list would have evicted it.
    private var pending: [ObjectIdentifier: TrackedUtterance] = [:]

    convenience override init() {
        let engine = AVFoundationSpeechSynthesizerEngine()
        self.init(engine: engine, scheduler: MainQueueSpeechWorkScheduler())
        engine.synthesizer.delegate = self
    }

    init(engine: any SpeechSynthesizerEngine, scheduler: any SpeechWorkScheduling) {
        self.engine = engine
        self.scheduler = scheduler
        super.init()
    }

    func setCallback(_ callback: @escaping @Sendable (SystemSpeechEvent) -> Void) {
        lock.lock()
        self.callback = callback
        lock.unlock()
    }

    func speak(_ utterance: AVSpeechUtterance, generation: UInt64, requestId: String) {
        let boxed = UncheckedSpeechUtterance(utterance: utterance)
        let identifier = ObjectIdentifier(utterance)
        lock.lock()
        pending[identifier] = TrackedUtterance(
            utterance: utterance,
            generation: generation,
            requestId: requestId,
            cancelled: false
        )
        lock.unlock()

        scheduler.enqueue { [weak self] in
            guard let self else { return }
            self.lock.lock()
            guard let tracked = self.pending[identifier],
                  tracked.generation == generation,
                  !tracked.cancelled
            else {
                self.lock.unlock()
                return
            }
            self.speakingGeneration = tracked.generation
            self.lock.unlock()
            self.engine.speak(boxed.utterance)
        }
    }

    func stop(generation: UInt64) {
        lock.lock()
        let started = speakingGeneration == generation
        if started {
            for (identifier, tracked) in pending where tracked.generation == generation {
                var retained = tracked
                retained.cancelled = true
                pending[identifier] = retained
            }
            speakingGeneration = nil
        } else {
            pending = pending.filter { $0.value.generation != generation }
        }
        lock.unlock()

        scheduler.enqueue { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let current = self.speakingGeneration
            let startedStillTracked = self.pending.values.contains {
                $0.generation == generation && $0.cancelled
            }
            let stillLive = self.pending.values.contains {
                $0.generation == generation && !$0.cancelled
            }
            self.lock.unlock()
            guard !stillLive else { return }
            if current == nil || current == generation || startedStillTracked {
                self.engine.stopSpeaking()
            }
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        handleEngineEvent(.didStart, identifier: ObjectIdentifier(utterance))
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        handleEngineEvent(.didFinish, identifier: ObjectIdentifier(utterance))
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        handleEngineEvent(.didCancel, identifier: ObjectIdentifier(utterance))
    }

    func handleEngineEvent(_ kind: SystemSpeechEvent.Kind, identifier: ObjectIdentifier) {
        lock.lock()
        let tracked = pending[identifier]
        if kind == .didFinish || kind == .didCancel {
            pending.removeValue(forKey: identifier)
            if let tracked, speakingGeneration == tracked.generation {
                speakingGeneration = nil
            }
        }
        let callback = self.callback
        lock.unlock()

        guard let tracked else { return }
        callback?(SystemSpeechEvent(kind: kind, generation: tracked.generation, requestId: tracked.requestId))
    }

    func hasPendingGeneration(_ generation: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return pending.values.contains { $0.generation == generation }
    }

    var currentSpeakingGeneration: UInt64? {
        lock.lock()
        defer { lock.unlock() }
        return speakingGeneration
    }
}

protocol AudioPlayerScheduling: AnyObject, Sendable {
    func sync<T>(_ work: () -> T) -> T
    func async(_ work: @escaping @Sendable () -> Void)
}

protocol AudioPlayerEngine: AnyObject, Sendable {
    func setDelegate(_ delegate: AVAudioPlayerDelegate?)
    func prepareToPlay()
    func play() -> Bool
    func stop()
}

final class MainQueueAudioPlayerScheduler: AudioPlayerScheduling, @unchecked Sendable {
    func sync<T>(_ work: () -> T) -> T {
        if Thread.isMainThread {
            return work()
        }
        return DispatchQueue.main.sync(execute: work)
    }

    func async(_ work: @escaping @Sendable () -> Void) {
        DispatchQueue.main.async(execute: work)
    }
}

final class AVFoundationAudioPlayerEngine: AudioPlayerEngine, @unchecked Sendable {
    let player: AVAudioPlayer

    init(data: Data) throws {
        self.player = try AVAudioPlayer(data: data)
    }

    func setDelegate(_ delegate: AVAudioPlayerDelegate?) {
        player.delegate = delegate
    }

    func prepareToPlay() {
        player.prepareToPlay()
    }

    func play() -> Bool {
        player.play()
    }

    func stop() {
        player.stop()
    }
}

public final class AVAudioPlayerSink: NSObject, SpeechAudioPlaying, AVAudioPlayerDelegate, @unchecked Sendable {
    private let engine: any AudioPlayerEngine
    private let scheduler: any AudioPlayerScheduling
    private let lock = NSLock()
    private var callback: (@Sendable (SpeechAudioPlayerEvent) -> Void)?

    public convenience init(data: Data) throws {
        let engine = try AVFoundationAudioPlayerEngine(data: data)
        self.init(engine: engine, scheduler: MainQueueAudioPlayerScheduler())
    }

    init(engine: any AudioPlayerEngine, scheduler: any AudioPlayerScheduling) {
        self.engine = engine
        self.scheduler = scheduler
        super.init()
        scheduler.sync {
            engine.setDelegate(self)
        }
    }

    public static func make(_ data: Data) throws -> any SpeechAudioPlaying {
        try AVAudioPlayerSink(data: data)
    }

    public func attach(callback: @escaping @Sendable (SpeechAudioPlayerEvent) -> Void) {
        lock.lock()
        self.callback = callback
        lock.unlock()
    }

    public func detach() {
        lock.lock()
        callback = nil
        lock.unlock()
        scheduler.sync {
            self.engine.setDelegate(nil)
        }
    }

    public func play() -> Bool {
        scheduler.sync {
            self.engine.prepareToPlay()
            return self.engine.play()
        }
    }

    public func stop() {
        scheduler.sync {
            self.engine.stop()
            self.engine.setDelegate(nil)
        }
        lock.lock()
        callback = nil
        lock.unlock()
    }

    public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let event: SpeechAudioPlayerEvent = flag
            ? .didFinish
            : .didFail("Audio playback did not complete successfully.")
        scheduler.async { [weak self] in
            self?.emit(event)
        }
    }

    public func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        let message = error?.localizedDescription ?? "Audio decode failed."
        scheduler.async { [weak self] in
            self?.emit(.didFail(message))
        }
    }

    func handleEngineEvent(_ event: SpeechAudioPlayerEvent) {
        scheduler.async { [weak self] in
            self?.emit(event)
        }
    }

    private func emit(_ event: SpeechAudioPlayerEvent) {
        lock.lock()
        let callback = self.callback
        lock.unlock()
        callback?(event)
    }
}

#if os(iOS) || os(tvOS) || os(watchOS)
public struct AVAudioSessionSpeechConfiguration: SpeechAudioSessionConfiguring {
    public init() {}

    public func prepareForSpeechOutput() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try session.setActive(true)
    }
}
#endif
