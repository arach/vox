import Foundation
import VoxCore
import VoxEngine

/// How a synthesis model should be delivered on an Apple audible surface.
///
/// This is a route/model capability for playback. It does not add `speak()` to
/// `TTSProvider`, which stays generation-only.
public enum SpeechOutputDelivery: String, Sendable, Codable, Equatable {
    /// Live `AVSpeechSynthesizer.speak()`. Do not `write()`-then-play.
    case liveSystem
    /// Provider-generated audio bytes played through a local audio sink.
    case generatedAudio
}

/// Physical playback path used by one controller instance.
public enum SpeechAudioOutputKind: String, Sendable, Codable, Equatable {
    case systemSynthesizer
    case generatedAudioPlayer
}

public struct SpeechAudioOutputRoute: Sendable, Equatable {
    public var kind: SpeechAudioOutputKind

    public init(kind: SpeechAudioOutputKind) {
        self.kind = kind
    }
}

/// Synthesis identity is reported separately from the physical audio-output route.
///
/// `backend` is `TTSModelInfo.backend` when known. It is not a provider id.
/// Requested model/voice stay on the request fields; actual model/voice are
/// filled in after resolve or generation.
public struct SpeechSynthesisIdentity: Sendable, Equatable {
    public var requestedModelId: String
    public var modelId: String
    public var requestedVoiceId: String?
    public var voiceId: String?
    public var backend: String?
    public var delivery: SpeechOutputDelivery

    public init(
        requestedModelId: String,
        modelId: String? = nil,
        requestedVoiceId: String? = nil,
        voiceId: String? = nil,
        backend: String? = nil,
        delivery: SpeechOutputDelivery
    ) {
        self.requestedModelId = requestedModelId
        self.modelId = modelId ?? requestedModelId
        self.requestedVoiceId = requestedVoiceId
        self.voiceId = voiceId
        self.backend = backend
        self.delivery = delivery
    }
}

public struct SpeechOutputRouteCapability: Sendable, Equatable {
    public var modelId: String
    public var backend: String?
    public var delivery: SpeechOutputDelivery
    public var audioOutput: SpeechAudioOutputRoute

    public init(
        modelId: String,
        backend: String? = nil,
        delivery: SpeechOutputDelivery,
        audioOutput: SpeechAudioOutputRoute
    ) {
        self.modelId = modelId
        self.backend = backend
        self.delivery = delivery
        self.audioOutput = audioOutput
    }
}

public enum SpeechOutputPhase: String, Sendable, Codable, Equatable {
    case resolving
    case generating
    case starting
    case playing
    case finished
    case cancelled
    case failed
}

public struct SpeechOutputEvent: Sendable, Equatable {
    public var requestId: String
    public var generation: UInt64
    public var phase: SpeechOutputPhase
    public var synthesis: SpeechSynthesisIdentity
    public var audioOutput: SpeechAudioOutputRoute
    public var error: String?

    public init(
        requestId: String,
        generation: UInt64,
        phase: SpeechOutputPhase,
        synthesis: SpeechSynthesisIdentity,
        audioOutput: SpeechAudioOutputRoute,
        error: String? = nil
    ) {
        self.requestId = requestId
        self.generation = generation
        self.phase = phase
        self.synthesis = synthesis
        self.audioOutput = audioOutput
        self.error = error
    }
}

public enum SpeechOutputError: Error, Sendable, Equatable, LocalizedError {
    case missingText
    case unsupportedVoice(String)
    case noSystemVoices
    case audioSessionFailed(String)
    case playerFailedToStart
    case playerFailed(String)
    case playerFactoryFailed(String)
    case generationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingText:
            return "Missing text"
        case .unsupportedVoice(let voiceId):
            return "Unsupported voice: \(voiceId)"
        case .noSystemVoices:
            return "No system speech voices are available."
        case .audioSessionFailed(let message):
            return message
        case .playerFailedToStart:
            return "Audio player failed to start."
        case .playerFailed(let message):
            return message
        case .playerFactoryFailed(let message):
            return message
        case .generationFailed(let message):
            return message
        }
    }
}

public enum SpeechOutputCapabilities {
    public static func delivery(forModelId modelId: String, backend: String? = nil) -> SpeechOutputDelivery {
        if modelId == TTSDefaults.localModelId {
            return .liveSystem
        }
        if backend?.lowercased() == "avspeech" {
            return .liveSystem
        }
        return .generatedAudio
    }

    public static func audioOutput(for delivery: SpeechOutputDelivery) -> SpeechAudioOutputRoute {
        switch delivery {
        case .liveSystem:
            return SpeechAudioOutputRoute(kind: .systemSynthesizer)
        case .generatedAudio:
            return SpeechAudioOutputRoute(kind: .generatedAudioPlayer)
        }
    }

    public static func capability(forModelId modelId: String, backend: String? = nil) -> SpeechOutputRouteCapability {
        let delivery = delivery(forModelId: modelId, backend: backend)
        return SpeechOutputRouteCapability(
            modelId: modelId,
            backend: backend,
            delivery: delivery,
            audioOutput: audioOutput(for: delivery)
        )
    }

    public static func capability(for model: TTSModelInfo) -> SpeechOutputRouteCapability {
        capability(forModelId: model.id, backend: model.backend)
    }
}
