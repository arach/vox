import Foundation

enum ResponseEnginePreference: String, CaseIterable, Identifiable, Sendable {
    case automatic
    case appleIntelligence
    case qwen

    var id: String { rawValue }

    var label: String {
        switch self {
        case .automatic:
            return "Auto"
        case .appleIntelligence:
            return "Apple"
        case .qwen:
            return "Qwen"
        }
    }
}

struct ResponseEngineAvailability: Sendable, Equatable {
    let preferredEngineName: String
    let message: String
    let apple: AppleIntelligenceAvailability
    let qwen: QwenFallbackAvailability
}

struct ResponseEngineReply: Sendable, Equatable {
    let text: String
    let elapsedMs: Int
    let engineName: String
    let statusMessage: String
}

enum ResponseEngineService {
    static func availability(
        preference: ResponseEnginePreference = .automatic
    ) async -> ResponseEngineAvailability {
        let appleAvailability = AppleIntelligenceService.availability()
        let qwenAvailability = await QwenFallbackService.shared.availability()

        switch preference {
        case .appleIntelligence:
            if appleAvailability.isAvailable {
                return ResponseEngineAvailability(
                    preferredEngineName: "Apple Intelligence",
                    message: qwenAvailability.isAvailable
                        ? "Apple Intelligence selected. \(QwenFallbackService.displayName) is available if you switch."
                        : "Apple Intelligence selected. \(appleAvailability.message)",
                    apple: appleAvailability,
                    qwen: qwenAvailability
                )
            }

            return ResponseEngineAvailability(
                preferredEngineName: "Apple Intelligence unavailable",
                message: "\(appleAvailability.message) Switch to Auto or Qwen.",
                apple: appleAvailability,
                qwen: qwenAvailability
            )

        case .qwen:
            if qwenAvailability.isAvailable {
                return ResponseEngineAvailability(
                    preferredEngineName: QwenFallbackService.displayName,
                    message: "\(QwenFallbackService.displayName) selected. \(qwenAvailability.message)",
                    apple: appleAvailability,
                    qwen: qwenAvailability
                )
            }

            return ResponseEngineAvailability(
                preferredEngineName: "\(QwenFallbackService.displayName) unavailable",
                message: "\(qwenAvailability.message) Switch to Auto or Apple.",
                apple: appleAvailability,
                qwen: qwenAvailability
            )

        case .automatic:
            break
        }

        if appleAvailability.isAvailable {
            let message = qwenAvailability.isAvailable
                ? "Apple Intelligence ready. \(QwenFallbackService.displayName) is available as fallback."
                : appleAvailability.message
            return ResponseEngineAvailability(
                preferredEngineName: "Apple Intelligence",
                message: message,
                apple: appleAvailability,
                qwen: qwenAvailability
            )
        }

        if qwenAvailability.isAvailable {
            return ResponseEngineAvailability(
                preferredEngineName: QwenFallbackService.displayName,
                message: "\(appleAvailability.message) \(qwenAvailability.message)",
                apple: appleAvailability,
                qwen: qwenAvailability
            )
        }

        return ResponseEngineAvailability(
            preferredEngineName: "No reply engine",
            message: "\(appleAvailability.message) \(qwenAvailability.message)",
            apple: appleAvailability,
            qwen: qwenAvailability
        )
    }

    static func generateReply(
        for transcript: String,
        preference: ResponseEnginePreference = .automatic
    ) async throws -> ResponseEngineReply {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ResponseEngineError.emptyInput
        }

        let appleAvailability = AppleIntelligenceService.availability()
        let qwenAvailability = await QwenFallbackService.shared.availability()

        switch preference {
        case .appleIntelligence:
            guard appleAvailability.isAvailable else {
                throw ResponseEngineError.unavailable("\(appleAvailability.message) Switch to Auto or Qwen.")
            }

            let reply = try await AppleIntelligenceService.generateReply(for: trimmed)
            return ResponseEngineReply(
                text: reply.text,
                elapsedMs: reply.elapsedMs,
                engineName: "Apple Intelligence",
                statusMessage: "Reply generated with Apple Intelligence."
            )

        case .qwen:
            guard qwenAvailability.isAvailable else {
                throw ResponseEngineError.unavailable("\(qwenAvailability.message) Switch to Auto or Apple.")
            }

            let reply = try await QwenFallbackService.shared.generateReply(for: trimmed)
            return ResponseEngineReply(
                text: reply.text,
                elapsedMs: reply.elapsedMs,
                engineName: QwenFallbackService.displayName,
                statusMessage: "Reply generated with \(QwenFallbackService.displayName)."
            )

        case .automatic:
            break
        }

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
