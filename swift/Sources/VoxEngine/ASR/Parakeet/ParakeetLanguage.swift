import Foundation

enum ParakeetLanguage: String, Sendable, CaseIterable {
    case english = "en"
    case spanish = "es"
    case french = "fr"
    case german = "de"
    case italian = "it"
    case portuguese = "pt"
    case romanian = "ro"
    case polish = "pl"
    case czech = "cs"
    case slovak = "sk"
    case slovenian = "sl"
    case croatian = "hr"
    case bosnian = "bs"
    case russian = "ru"
    case ukrainian = "uk"
    case belarusian = "be"
    case bulgarian = "bg"
    case serbian = "sr"

    var script: ParakeetScript {
        switch self {
        case .english, .spanish, .french, .german, .italian, .portuguese, .romanian,
            .polish, .czech, .slovak, .slovenian, .croatian, .bosnian:
            return .latin
        case .russian, .ukrainian, .belarusian, .bulgarian, .serbian:
            return .cyrillic
        }
    }
}

enum ParakeetScript: Sendable {
    case latin
    case cyrillic
}

struct ParakeetTokenLanguageFilter: Sendable {
    private static let sentencePieceBoundary: Unicode.Scalar = "\u{2581}"

    static func matches(_ text: String, script: ParakeetScript) -> Bool {
        let cleanedText = text.replacingOccurrences(of: String(sentencePieceBoundary), with: "")
        guard !cleanedText.isEmpty else { return true }

        let chars = cleanedText.unicodeScalars
        switch script {
        case .latin:
            return chars.allSatisfy {
                ($0.value >= 0x0020 && $0.value <= 0x007F)
                    || ($0.value >= 0x00A0 && $0.value <= 0x00FF)
                    || ($0.value >= 0x0100 && $0.value <= 0x017F)
                    || ($0.value >= 0x0180 && $0.value <= 0x024F)
                    || ($0.value >= 0x0300 && $0.value <= 0x036F)
                    || ($0.value >= 0x1E00 && $0.value <= 0x1EFF)
            }
        case .cyrillic:
            return chars.allSatisfy { char in
                let value = char.value
                if value >= 0x0400 && value <= 0x04FF { return true }
                if value >= 0x0020 && value <= 0x007F {
                    if (value >= 0x41 && value <= 0x5A) || (value >= 0x61 && value <= 0x7A) {
                        return false
                    }
                    return true
                }
                return false
            }
        }
    }

    static func filterTopK(
        topKIds: [Int],
        topKLogits: [Float],
        vocabulary: [Int: String],
        preferredScript: ParakeetScript
    ) -> (tokenId: Int, probability: Float)? {
        let count = min(topKIds.count, topKLogits.count)
        guard count > 0 else { return nil }

        var bestIndex = -1
        var bestLogit: Float = -.infinity
        for index in 0..<count {
            let tokenId = topKIds[index]
            guard let tokenText = vocabulary[tokenId] else { continue }
            guard matches(tokenText, script: preferredScript) else { continue }

            let logit = topKLogits[index]
            if bestIndex < 0 || logit > bestLogit {
                bestLogit = logit
                bestIndex = index
            }
        }

        guard bestIndex >= 0 else { return nil }

        var maxLogit = -Float.infinity
        for index in 0..<count where topKLogits[index] > maxLogit {
            maxLogit = topKLogits[index]
        }
        guard maxLogit.isFinite else {
            return (topKIds[bestIndex], 0)
        }

        var sumExp: Float = 0
        for index in 0..<count {
            sumExp += expf(topKLogits[index] - maxLogit)
        }
        guard sumExp > 0 else {
            return (topKIds[bestIndex], 0)
        }

        let probability = expf(topKLogits[bestIndex] - maxLogit) / sumExp
        return (topKIds[bestIndex], max(0, min(1, probability)))
    }
}
