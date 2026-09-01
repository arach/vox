import AVFoundation
import Foundation
import Testing
@testable import VoxAppleSpeech

struct SpeechOutputRateTests {
    @Test("piecewise speed mapping hits min, default, and max")
    func piecewiseSpeedMappingHitsBoundaries() {
        let minimum: Float = 0.10
        let defaultRate: Float = 0.50
        let maximum: Float = 1.00

        #expect(SpeechOutputRate.map(speed: 0.25, minimum: minimum, defaultRate: defaultRate, maximum: maximum) == minimum)
        #expect(SpeechOutputRate.map(speed: 1.0, minimum: minimum, defaultRate: defaultRate, maximum: maximum) == defaultRate)
        #expect(SpeechOutputRate.map(speed: 4.0, minimum: minimum, defaultRate: defaultRate, maximum: maximum) == maximum)
        #expect(SpeechOutputRate.map(speed: 0.1, minimum: minimum, defaultRate: defaultRate, maximum: maximum) == minimum)
        #expect(SpeechOutputRate.map(speed: 8.0, minimum: minimum, defaultRate: defaultRate, maximum: maximum) == maximum)

        let slowMid = SpeechOutputRate.map(speed: 0.625, minimum: minimum, defaultRate: defaultRate, maximum: maximum)
        #expect(abs(slowMid - 0.30) < 0.0001)
        let fastMid = SpeechOutputRate.map(speed: 2.5, minimum: minimum, defaultRate: defaultRate, maximum: maximum)
        #expect(abs(fastMid - 0.75) < 0.0001)
    }
}

struct SystemVoiceResolverTests {
    @Test("preferred languages are BCP-47 and fall back to en-US")
    func preferredLanguagesAreBCP47AndFallBackToEnUS() {
        #expect(SystemVoiceResolver.languageCandidates(preferredLanguages: ["fr_CA", "en_GB"]) == [
            "fr-CA",
            "en-GB",
            "en-US"
        ])
        #expect(SystemVoiceResolver.languageCandidates(preferredLanguages: ["en-US"]) == ["en-US"])
    }

    @Test("default voice uses the first preferred language before en-US")
    func defaultVoiceUsesFirstPreferredLanguageBeforeEnUS() throws {
        let voices = [
            SystemVoiceDescriptor(identifier: "en", language: "en-US"),
            SystemVoiceDescriptor(identifier: "fr", language: "fr-FR")
        ]
        let picked = try SystemVoiceResolver.resolve(
            voiceId: nil,
            voices: voices,
            preferredLanguages: ["fr-FR"]
        )
        #expect(picked.identifier == "fr")
    }

    @Test("missing preferred language falls back to en-US then first voice")
    func missingPreferredLanguageFallsBack() throws {
        let voices = [
            SystemVoiceDescriptor(identifier: "de", language: "de-DE"),
            SystemVoiceDescriptor(identifier: "en", language: "en-US")
        ]
        let english = try SystemVoiceResolver.resolve(
            voiceId: nil,
            voices: voices,
            preferredLanguages: ["zz-ZZ"]
        )
        #expect(english.identifier == "en")

        let onlyGerman = [
            SystemVoiceDescriptor(identifier: "de", language: "de-DE")
        ]
        let first = try SystemVoiceResolver.resolve(
            voiceId: nil,
            voices: onlyGerman,
            preferredLanguages: ["zz-ZZ"]
        )
        #expect(first.identifier == "de")
    }
}

struct AVAudioPlayerSinkTests {
    @Test("player play and stop run on the injected scheduler")
    func playerPlayAndStopRunOnInjectedScheduler() {
        let engine = RecordingAudioPlayerEngine()
        let scheduler = RecordingAudioPlayerScheduler()
        let sink = AVAudioPlayerSink(engine: engine, scheduler: scheduler)

        #expect(sink.play())
        sink.stop()
        sink.handleEngineEvent(.didFinish)

        #expect(engine.prepareCount == 1)
        #expect(engine.playCount == 1)
        #expect(engine.stopCount == 1)
        #expect(scheduler.syncCount >= 2)
        #expect(scheduler.asyncCount == 1)
    }

    @Test("main-queue play uses the inline Thread.isMainThread fast path")
    @MainActor
    func mainQueuePlayUsesInlineFastPath() {
        #expect(Thread.isMainThread)
        let engine = RecordingAudioPlayerEngine()
        let sink = AVAudioPlayerSink(engine: engine, scheduler: MainQueueAudioPlayerScheduler())
        let started = sink.play()
        sink.stop()
        #expect(started)
        #expect(engine.playCount == 1)
        #expect(engine.stopCount == 1)
    }

    @Test("background play returns a Bool without deadlocking the main queue")
    func backgroundPlayReturnsWithoutDeadlocking() {
        let engine = RecordingAudioPlayerEngine()
        let sink = AVAudioPlayerSink(engine: engine, scheduler: MainQueueAudioPlayerScheduler())
        let gate = DispatchSemaphore(value: 0)
        let started = LockedFlag()
        DispatchQueue.global(qos: .userInitiated).async {
            started.set(sink.play())
            sink.stop()
            gate.signal()
        }
        #expect(gate.wait(timeout: .now() + 2) == .success)
        #expect(started.value)
        #expect(engine.playCount == 1)
    }
}

private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = false

    var value: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func set(_ value: Bool) {
        lock.lock()
        stored = value
        lock.unlock()
    }
}

private final class RecordingAudioPlayerEngine: AudioPlayerEngine, @unchecked Sendable {
    private let lock = NSLock()
    private var prepares = 0
    private var plays = 0
    private var stops = 0

    var prepareCount: Int {
        lock.lock(); defer { lock.unlock() }
        return prepares
    }

    var playCount: Int {
        lock.lock(); defer { lock.unlock() }
        return plays
    }

    var stopCount: Int {
        lock.lock(); defer { lock.unlock() }
        return stops
    }

    func setDelegate(_ delegate: AVAudioPlayerDelegate?) {}

    func prepareToPlay() {
        lock.lock()
        prepares += 1
        lock.unlock()
    }

    func play() -> Bool {
        lock.lock()
        plays += 1
        lock.unlock()
        return true
    }

    func stop() {
        lock.lock()
        stops += 1
        lock.unlock()
    }
}

private final class RecordingAudioPlayerScheduler: AudioPlayerScheduling, @unchecked Sendable {
    private let lock = NSLock()
    private var syncs = 0
    private var asyncs = 0

    var syncCount: Int {
        lock.lock(); defer { lock.unlock() }
        return syncs
    }

    var asyncCount: Int {
        lock.lock(); defer { lock.unlock() }
        return asyncs
    }

    func sync<T>(_ work: () -> T) -> T {
        lock.lock()
        syncs += 1
        lock.unlock()
        return work()
    }

    func async(_ work: @escaping @Sendable () -> Void) {
        lock.lock()
        asyncs += 1
        lock.unlock()
        work()
    }
}
