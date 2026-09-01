import Foundation

enum RemoteTTSSupport {
    static let maximumVendorMessageLength = 240

    static func firstNonEmpty(_ values: String?...) -> String? {
        firstNonEmpty(Array(values))
    }

    static func firstNonEmpty(_ values: [String?]) -> String? {
        for value in values {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }

    /// Per-request non-empty secrets win. If `env` contains any of `keys`
    /// (even empty or whitespace), process fallback is suppressed so a host
    /// can fence ambient secrets. Process env is used only when `env` is nil
    /// or omits every listed key.
    static func resolveSecret(
        lentValues: [String?],
        env: [String: String]?,
        processEnv: [String: String],
        keys: [String]
    ) -> String? {
        if let lent = firstNonEmpty(lentValues) {
            return lent
        }
        if let env, keys.contains(where: { env[$0] != nil }) {
            return firstNonEmpty(keys.map { env[$0] })
        }
        return firstNonEmpty(keys.map { processEnv[$0] })
    }

    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        if let urlError = error as? URLError, urlError.code == .cancelled {
            return true
        }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }

    static func mapCancellation(_ error: Error) throws -> Never {
        if isCancellation(error) {
            throw CancellationError()
        }
        throw error
    }

    static func data(for request: URLRequest, session: URLSession) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            try mapCancellation(error)
        }
    }

    static let minimumExactRedactionLength = 8

    static func sanitizeVendorMessage(
        from data: Data,
        vendor: String,
        sensitiveValues: [String] = []
    ) -> String {
        let extracted = extractVendorMessage(from: data) ?? "HTTP error"
        let withoutPrompt = redactExactSensitiveValues(extracted, sensitiveValues: sensitiveValues)
        return sanitize("\(vendor): \(withoutPrompt)")
    }

    static func redactExactSensitiveValues(
        _ message: String,
        sensitiveValues: [String]
    ) -> String {
        let values = Array(Set(
            sensitiveValues
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )).sorted { $0.count > $1.count }

        var result = message
        for value in values {
            if isSafeToReplaceExactly(value) {
                result = result.replacingOccurrences(
                    of: value,
                    with: "[redacted]",
                    options: .caseInsensitive
                )
                continue
            }
            if result.localizedCaseInsensitiveContains(value) {
                return "request failed"
            }
        }
        return result
    }

    static func isSafeToReplaceExactly(_ value: String) -> Bool {
        value.count >= minimumExactRedactionLength
            || (value.count >= 2 && value.contains(where: \.isWhitespace))
    }

    static func extractVendorMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) else {
            return clippedPlainText(from: data)
        }
        if let json = object as? [String: Any] {
            if let detail = stringValue(json["detail"]) { return detail }
            if let message = stringValue(json["message"]) { return message }
            if let error = stringValue(json["error"]) { return error }
            if let error = json["error"] as? [String: Any], let message = stringValue(error["message"]) {
                return message
            }
        }
        return clippedPlainText(from: data)
    }

    static func sanitize(_ message: String) -> String {
        var result = redactSecrets(message)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if result.count > maximumVendorMessageLength {
            result = String(result.prefix(maximumVendorMessageLength)) + "…"
        }
        return result
    }

    private static func stringValue(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func clippedPlainText(from data: Data) -> String? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.hasPrefix("{") || trimmed.hasPrefix("<") {
            return nil
        }
        return String(trimmed.prefix(120))
    }

    private static func redactSecrets(_ text: String) -> String {
        var result = text
        let patterns = [
            #"Bearer\s+\S+"#,
            #"nvapi-[A-Za-z0-9._-]+"#,
            #"sk-[A-Za-z0-9._-]+"#,
            #"gsk_[A-Za-z0-9._-]+"#,
            #"AIza[A-Za-z0-9_\-]+"#,
            #"(NV_API_KEY|NVIDIA_API_KEY|GROQ_API_KEY|GEMINI_API_KEY|GOOGLE_API_KEY|GOOGLE_GENAI_API_KEY|OPENAI_API_KEY)\s*[:=]\s*\S+"#
        ]
        for pattern in patterns {
            result = result.replacingOccurrences(
                of: pattern,
                with: "[redacted]",
                options: .regularExpression
            )
        }
        return result
    }
}
