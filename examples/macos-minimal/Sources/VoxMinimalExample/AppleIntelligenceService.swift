import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

struct AppleIntelligenceAvailability: Sendable, Equatable {
    let isAvailable: Bool
    let message: String
}

struct AppleIntelligenceReply: Sendable, Equatable {
    let text: String
    let elapsedMs: Int
}

enum AppleIntelligenceService {
    static func availability() -> AppleIntelligenceAvailability {
        #if canImport(FoundationModels)
        guard #available(macOS 26.0, *) else {
            return AppleIntelligenceAvailability(
                isAvailable: false,
                message: "Apple Intelligence requires macOS 26+."
            )
        }

        switch SystemLanguageModel.default.availability {
        case .available:
            return AppleIntelligenceAvailability(
                isAvailable: true,
                message: "Apple Intelligence ready."
            )
        case .unavailable(let reason):
            return AppleIntelligenceAvailability(
                isAvailable: false,
                message: "Apple Intelligence unavailable: \(String(describing: reason))."
            )
        @unknown default:
            return AppleIntelligenceAvailability(
                isAvailable: false,
                message: "Apple Intelligence availability is unknown."
            )
        }
        #else
        return AppleIntelligenceAvailability(
            isAvailable: false,
            message: "FoundationModels is not available in this build."
        )
        #endif
    }

    static func generateReply(for transcript: String) async throws -> AppleIntelligenceReply {
        #if canImport(FoundationModels)
        guard #available(macOS 26.0, *) else {
            throw AppleIntelligenceError.unavailable("Apple Intelligence requires macOS 26+.")
        }

        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AppleIntelligenceError.emptyInput
        }

        guard case .available = SystemLanguageModel.default.availability else {
            throw AppleIntelligenceError.unavailable(availability().message)
        }

        let startedAt = Date()
        let session = LanguageModelSession(instructions: systemPrompt)
        let response = try await session.respond(
            to: trimmed,
            options: FoundationModels.GenerationOptions(temperature: 0.35)
        )
        let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1000)
        let text = normalize(response.content)
        return AppleIntelligenceReply(text: text, elapsedMs: elapsedMs)
        #else
        throw AppleIntelligenceError.unavailable("FoundationModels is not available in this build.")
        #endif
    }

    private static let systemPrompt = """
    You are a warm, concise on-device voice assistant inside a minimal macOS demo.
    The demo records a short voice turn, transcribes it locally with Vox, generates a reply on device, and speaks the answer back out loud.
    Reply in one or two short sentences.
    Keep it helpful, conversational, and natural.
    Do not use markdown or bullet points.
    """

    private static func normalize(_ text: String) -> String {
        let collapsed = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        let trimmed = collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(240))
    }
}

enum AppleIntelligenceError: LocalizedError {
    case unavailable(String)
    case emptyInput

    var errorDescription: String? {
        switch self {
        case .unavailable(let message):
            return message
        case .emptyInput:
            return "Record a short turn first."
        }
    }
}
