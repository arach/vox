import Foundation
import VoxCore

public enum TTSProviderFamily: String, Sendable, CaseIterable {
    case openai
    case elevenlabs
    case minimax
    case nvidia
    case groq
    case gemini
    case avspeech
    case mlxAudio

    public init?(providerId: String) {
        switch providerId.lowercased() {
        case "openai", "openai-tts":
            self = .openai
        case "elevenlabs", "elevenlabs-tts", "eleven-labs", "eleven-labs-tts":
            self = .elevenlabs
        case "minimax", "minimax-tts":
            self = .minimax
        case "nvidia", "nvidia-tts", "magpie", "magpie-tts", "nvidia-magpie":
            self = .nvidia
        case "groq", "groq-tts":
            self = .groq
        case "gemini", "gemini-tts", "google-tts", "google-gemini-tts":
            self = .gemini
        case "avspeech", "avspeechsynthesizer", "apple-tts", "system-tts":
            self = .avspeech
        case "mlx-audio", "mlx_audio", "mlx-audio-tts", "mlx_audio_tts":
            self = .mlxAudio
        default:
            return nil
        }
    }

    public var canonicalProviderId: String {
        switch self {
        case .openai:
            return "openai-tts"
        case .elevenlabs:
            return "elevenlabs"
        case .minimax:
            return "minimax"
        case .nvidia:
            return "nvidia"
        case .groq:
            return "groq"
        case .gemini:
            return "gemini"
        case .avspeech:
            return "avspeech"
        case .mlxAudio:
            return "mlx-audio"
        }
    }
}
