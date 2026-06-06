import Foundation
import VoxCore

enum ParakeetTextProcessing {
    static func convertTokensToText(_ tokenIds: [Int], vocabulary: [Int: String]) -> String {
        guard !tokenIds.isEmpty else { return "" }

        let tokens = tokenIds.compactMap { vocabulary[$0] }.filter { !$0.isEmpty }
        return tokens.joined()
            .replacingOccurrences(of: "▁", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    static func createWordTimings(
        tokenIds: [Int],
        timestamps: [Int],
        confidences: [Float],
        tokenDurations: [Int],
        vocabulary: [Int: String]
    ) -> [WordTiming] {
        guard !tokenIds.isEmpty,
              !timestamps.isEmpty,
              tokenIds.count == timestamps.count,
              confidences.count == tokenIds.count else {
            return []
        }

        let combined = zip(
            zip(zip(tokenIds, timestamps), confidences),
            tokenDurations.isEmpty ? Array(repeating: 0, count: tokenIds.count) : tokenDurations
        ).map { (tokenId: $0.0.0.0, timestamp: $0.0.0.1, confidence: $0.0.1, duration: $0.1) }
            .sorted { $0.timestamp < $1.timestamp }

        return combined.compactMap { item in
            let rawToken = vocabulary[item.tokenId] ?? "token_\(item.tokenId)"
            let normalized = rawToken
                .replacingOccurrences(of: "▁", with: " ")
                .trimmingCharacters(in: .whitespaces)
            guard !normalized.isEmpty else { return nil }

            let startTime = Double(item.timestamp) * ParakeetConstants.secondsPerEncoderFrame
            let durationInSeconds = item.duration > 0
                ? Double(item.duration) * ParakeetConstants.secondsPerEncoderFrame
                : ParakeetConstants.secondsPerEncoderFrame
            let endTime = max(startTime + durationInSeconds, startTime + 0.001)

            return WordTiming(
                word: normalized,
                start: startTime,
                end: endTime,
                confidence: item.confidence
            )
        }
    }
}
