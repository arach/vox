import Foundation

struct ResponseEngineAvailability: Sendable, Equatable {
    let preferredEngineName: String
    let message: String
}

struct ResponseEngineReply: Sendable, Equatable {
    let text: String
    let elapsedMs: Int
    let engineName: String
    let statusMessage: String
}

enum ResponseEngineService {
    static func availability() async -> ResponseEngineAvailability {
        let appleAvailability = AppleIntelligenceService.availability()
        let qwenAvailability = await QwenFallbackService.shared.availability()

        if appleAvailability.isAvailable {
            let message = qwenAvailability.isAvailable
                ? "Apple Intelligence ready. \(QwenFallbackService.displayName) is available as fallback."
                : appleAvailability.message
            return ResponseEngineAvailability(
                preferredEngineName: "Apple Intelligence",
                message: message
            )
        }

        if qwenAvailability.isAvailable {
            return ResponseEngineAvailability(
                preferredEngineName: QwenFallbackService.displayName,
                message: "\(appleAvailability.message) \(qwenAvailability.message)"
            )
        }

        return ResponseEngineAvailability(
            preferredEngineName: "No reply engine",
            message: "\(appleAvailability.message) \(qwenAvailability.message)"
        )
    }

    static func generateReply(for transcript: String) async throws -> ResponseEngineReply {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ResponseEngineError.emptyInput
        }

        let appleAvailability = AppleIntelligenceService.availability()
        if appleAvailability.isAvailable {
            do {
                let reply = try await AppleIntelligenceService.generateReply(for: trimmed)
                return ResponseEngineReply(
                    text: reply.text,
                    elapsedMs: reply.elapsedMs,
                    engineName: "Apple Intelligence",
                    statusMessage: "Reply generated with Apple Intelligence."
                )
            } catch {
                let qwenAvailability = await QwenFallbackService.shared.availability()
                guard qwenAvailability.isAvailable else {
                    throw error
                }

                let fallback = try await QwenFallbackService.shared.generateReply(for: trimmed)
                return ResponseEngineReply(
                    text: fallback.text,
                    elapsedMs: fallback.elapsedMs,
                    engineName: QwenFallbackService.displayName,
                    statusMessage: "Apple Intelligence missed this turn, so \(QwenFallbackService.displayName) answered locally."
                )
            }
        }

        let qwenAvailability = await QwenFallbackService.shared.availability()
        guard qwenAvailability.isAvailable else {
            throw ResponseEngineError.unavailable("\(appleAvailability.message) \(qwenAvailability.message)")
        }

        let reply = try await QwenFallbackService.shared.generateReply(for: trimmed)
        return ResponseEngineReply(
            text: reply.text,
            elapsedMs: reply.elapsedMs,
            engineName: QwenFallbackService.displayName,
            statusMessage: "\(appleAvailability.message) Reply generated with \(QwenFallbackService.displayName)."
        )
    }
}

enum ResponseEngineError: LocalizedError {
    case emptyInput
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "Record a short turn first."
        case .unavailable(let message):
            return message
        }
    }
}
