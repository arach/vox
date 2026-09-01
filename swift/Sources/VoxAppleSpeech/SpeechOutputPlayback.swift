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
public protocol SpeechAudioPlaying: AnyObject, Sendable {
    func attach(callback: @escaping @Sendable (SpeechAudioPlayerEvent) -> Void)
    func play() -> Bool
    func stop()
}

public typealias SpeechAudioPlayerFactory = @Sendable (Data) throws -> any SpeechAudioPlaying

/// Opt-in audio-session configuration. Controllers do not configure a session
/// unless the caller injects one.
public protocol SpeechAudioSessionConfiguring: Sendable {
    func prepareForSpeechOutput() throws
}

private struct UncheckedSpeechUtterance: @unchecked Sendable {
    let utterance: AVSpeechUtterance

    init(_ utterance: AVSpeechUtterance) {
        self.utterance = utterance
    }
}

final class SpeechOutputUtterance: AVSpeechUtterance, @unchecked Sendable {
    let requestId: String
    let generation: UInt64

    init(text: String, requestId: String, generation: UInt64) {
        self.requestId = requestId
        self.generation = generation
        super.init(string: text)
    }

    required init?(coder: NSCoder) {
        nil
    }
}

public final class AVSpeechSynthesizerSink: NSObject, SystemSpeechSynthesizing, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    private let synthesizer = AVSpeechSynthesizer()
    private let lock = NSLock()
    private var callback: (@Sendable (SystemSpeechEvent) -> Void)?
    private var cancelledGenerations: [UInt64] = []
    private var speakingGeneration: UInt64?

    public override init() {
        super.init()
        synthesizer.delegate = self
    }

    public func setCallback(_ callback: @escaping @Sendable (SystemSpeechEvent) -> Void) {
        lock.lock()
        self.callback = callback
        lock.unlock()
    }

    public func speak(_ utterance: AVSpeechUtterance, generation: UInt64, requestId: String) {
        let boxed = UncheckedSpeechUtterance(utterance)
        runOnSynthesizerQueue {
            guard !self.isCancelled(generation) else { return }
            self.speakingGeneration = generation
            self.synthesizer.speak(boxed.utterance)
        }
    }

    public func stop(generation: UInt64) {
        runOnSynthesizerQueue {
            self.markCancelled(generation)
            if self.speakingGeneration == nil || self.speakingGeneration == generation {
                self.speakingGeneration = nil
                self.synthesizer.stopSpeaking(at: .immediate)
            }
        }
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        emit(.didStart, from: utterance)
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        emit(.didFinish, from: utterance)
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        emit(.didCancel, from: utterance)
    }

    private func emit(_ kind: SystemSpeechEvent.Kind, from utterance: AVSpeechUtterance) {
        guard let tracked = utterance as? SpeechOutputUtterance else { return }
        let callback = lockedCallback()
        callback?(SystemSpeechEvent(kind: kind, generation: tracked.generation, requestId: tracked.requestId))
    }

    private func lockedCallback() -> (@Sendable (SystemSpeechEvent) -> Void)? {
        lock.lock()
        defer { lock.unlock() }
        return callback
    }

    private func isCancelled(_ generation: UInt64) -> Bool {
        cancelledGenerations.contains(generation)
    }

    private func markCancelled(_ generation: UInt64) {
        cancelledGenerations.append(generation)
        if cancelledGenerations.count > 32 {
            cancelledGenerations.removeFirst(cancelledGenerations.count - 32)
        }
    }

    private func runOnSynthesizerQueue(_ work: @escaping @Sendable () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }
}

public final class AVAudioPlayerSink: NSObject, SpeechAudioPlaying, AVAudioPlayerDelegate, @unchecked Sendable {
    private let player: AVAudioPlayer
    private let lock = NSLock()
    private var callback: (@Sendable (SpeechAudioPlayerEvent) -> Void)?

    public init(data: Data) throws {
        self.player = try AVAudioPlayer(data: data)
        super.init()
        self.player.delegate = self
    }

    public static func make(_ data: Data) throws -> any SpeechAudioPlaying {
        try AVAudioPlayerSink(data: data)
    }

    public func attach(callback: @escaping @Sendable (SpeechAudioPlayerEvent) -> Void) {
        lock.lock()
        self.callback = callback
        lock.unlock()
    }

    public func play() -> Bool {
        player.prepareToPlay()
        return player.play()
    }

    public func stop() {
        player.stop()
    }

    public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        if flag {
            emit(.didFinish)
        } else {
            emit(.didFail("Audio playback did not complete successfully."))
        }
    }

    public func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        emit(.didFail(error?.localizedDescription ?? "Audio decode failed."))
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
