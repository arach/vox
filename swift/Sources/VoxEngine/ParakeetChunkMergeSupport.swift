import Foundation
import VoxCore

struct ParakeetChunkToken: Sendable, Equatable {
    let token: Int
    let timestamp: Int
    let confidence: Float
    let duration: Int
}

struct ParakeetSequenceMatch {
    let leftStartIndex: Int
    let rightStartIndex: Int
    let length: Int
}

struct ParakeetSequenceMatcher<Element> {
    static func findLongestCommonSubsequence(
        left: [Element],
        right: [Element],
        matcher: (Element, Element) -> Bool
    ) -> [ParakeetSequenceMatch] {
        let leftCount = left.count
        let rightCount = right.count
        var dp = Array(repeating: Array(repeating: 0, count: rightCount + 1), count: leftCount + 1)

        for i in 1...leftCount {
            for j in 1...rightCount {
                if matcher(left[i - 1], right[j - 1]) {
                    dp[i][j] = dp[i - 1][j - 1] + 1
                } else {
                    dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
                }
            }
        }

        var matches: [ParakeetSequenceMatch] = []
        var i = leftCount
        var j = rightCount

        while i > 0 && j > 0 {
            if matcher(left[i - 1], right[j - 1]) {
                matches.append(
                    ParakeetSequenceMatch(
                        leftStartIndex: i - 1,
                        rightStartIndex: j - 1,
                        length: 1
                    )
                )
                i -= 1
                j -= 1
            } else if dp[i - 1][j] > dp[i][j - 1] {
                i -= 1
            } else {
                j -= 1
            }
        }

        return matches.reversed()
    }

    static func findContiguousMatches(
        left: [Element],
        right: [Element],
        matcher: (Element, Element) -> Bool
    ) -> [ParakeetSequenceMatch] {
        var best: [ParakeetSequenceMatch] = []

        for i in 0..<left.count {
            for j in 0..<right.count where matcher(left[i], right[j]) {
                var current: [ParakeetSequenceMatch] = []
                var k = i
                var l = j

                while k < left.count && l < right.count && matcher(left[k], right[l]) {
                    current.append(
                        ParakeetSequenceMatch(
                            leftStartIndex: k,
                            rightStartIndex: l,
                            length: 1
                        )
                    )
                    k += 1
                    l += 1
                }

                if current.count > best.count {
                    best = current
                }
            }
        }

        return best
    }
}

struct ParakeetChunkMerger {
    private struct IndexedToken {
        let index: Int
        let token: ParakeetChunkToken
        let start: Double
        let end: Double
    }

    let overlapSeconds: Double

    init(overlapSeconds: Double = 2.0) {
        self.overlapSeconds = overlapSeconds
    }

    func merge(_ left: [ParakeetChunkToken], _ right: [ParakeetChunkToken]) -> [ParakeetChunkToken] {
        if left.isEmpty { return right }
        if right.isEmpty { return left }

        let frameDuration = ParakeetConstants.secondsPerEncoderFrame
        let halfOverlapWindow = overlapSeconds / 2

        func startTime(of token: ParakeetChunkToken) -> Double {
            Double(token.timestamp) * frameDuration
        }

        func endTime(of token: ParakeetChunkToken) -> Double {
            startTime(of: token) + frameDuration
        }

        let leftEndTime = endTime(of: left.last!)
        let rightStartTime = startTime(of: right.first!)

        if leftEndTime <= rightStartTime {
            return left + right
        }

        let overlapLeft: [IndexedToken] = left.enumerated().compactMap { offset, token in
            let start = startTime(of: token)
            let end = start + frameDuration
            guard end > rightStartTime - overlapSeconds else { return nil }
            return IndexedToken(index: offset, token: token, start: start, end: end)
        }

        let overlapRight: [IndexedToken] = right.enumerated().compactMap { offset, token in
            let start = startTime(of: token)
            guard start < leftEndTime + overlapSeconds else { return nil }
            return IndexedToken(index: offset, token: token, start: start, end: start + frameDuration)
        }

        guard overlapLeft.count >= 2 && overlapRight.count >= 2 else {
            return mergeByMidpoint(
                left: left,
                right: right,
                leftEndTime: leftEndTime,
                rightStartTime: rightStartTime,
                frameDuration: frameDuration
            )
        }

        let minimumPairs = max(overlapLeft.count / 2, 1)
        let timeTolerantMatcher: (IndexedToken, IndexedToken) -> Bool = { leftToken, rightToken in
            guard leftToken.token.token == rightToken.token.token else { return false }
            let timeDifference = abs(leftToken.start - rightToken.start)
            return timeDifference < halfOverlapWindow
        }

        let contiguousMatches = ParakeetSequenceMatcher.findContiguousMatches(
            left: overlapLeft,
            right: overlapRight,
            matcher: timeTolerantMatcher
        )
        let contiguousPairs = contiguousMatches.map { ($0.leftStartIndex, $0.rightStartIndex) }
        if contiguousPairs.count >= minimumPairs {
            return mergeUsingMatches(
                matches: contiguousPairs,
                overlapLeft: overlapLeft,
                overlapRight: overlapRight,
                left: left,
                right: right
            )
        }

        let lcsMatches = ParakeetSequenceMatcher.findLongestCommonSubsequence(
            left: overlapLeft,
            right: overlapRight,
            matcher: timeTolerantMatcher
        )
        guard !lcsMatches.isEmpty else {
            return mergeByMidpoint(
                left: left,
                right: right,
                leftEndTime: leftEndTime,
                rightStartTime: rightStartTime,
                frameDuration: frameDuration
            )
        }

        let lcsPairs = lcsMatches.map { ($0.leftStartIndex, $0.rightStartIndex) }
        return mergeUsingMatches(
            matches: lcsPairs,
            overlapLeft: overlapLeft,
            overlapRight: overlapRight,
            left: left,
            right: right
        )
    }

    private func mergeUsingMatches(
        matches: [(Int, Int)],
        overlapLeft: [IndexedToken],
        overlapRight: [IndexedToken],
        left: [ParakeetChunkToken],
        right: [ParakeetChunkToken]
    ) -> [ParakeetChunkToken] {
        let leftIndices = matches.map { overlapLeft[$0.0].index }
        let rightIndices = matches.map { overlapRight[$0.1].index }

        var result: [ParakeetChunkToken] = []

        if let firstLeft = leftIndices.first, firstLeft > 0 {
            result.append(contentsOf: left[..<firstLeft])
        }

        for idx in 0..<matches.count {
            let leftIndex = leftIndices[idx]
            let rightIndex = rightIndices[idx]
            result.append(left[leftIndex])

            guard idx < matches.count - 1 else { continue }

            let nextLeftIndex = leftIndices[idx + 1]
            let nextRightIndex = rightIndices[idx + 1]
            let gapLeft = nextLeftIndex > leftIndex + 1 ? Array(left[(leftIndex + 1)..<nextLeftIndex]) : []
            let gapRight = nextRightIndex > rightIndex + 1 ? Array(right[(rightIndex + 1)..<nextRightIndex]) : []

            if gapRight.count > gapLeft.count {
                result.append(contentsOf: gapRight)
            } else {
                result.append(contentsOf: gapLeft)
            }
        }

        if let lastRight = rightIndices.last, lastRight + 1 < right.count {
            result.append(contentsOf: right[(lastRight + 1)...])
        }

        return result
    }

    private func mergeByMidpoint(
        left: [ParakeetChunkToken],
        right: [ParakeetChunkToken],
        leftEndTime: Double,
        rightStartTime: Double,
        frameDuration: Double
    ) -> [ParakeetChunkToken] {
        let cutoff = (leftEndTime + rightStartTime) / 2
        let trimmedLeft = left.filter { Double($0.timestamp) * frameDuration < cutoff }
        let trimmedRight = right.filter { Double($0.timestamp) * frameDuration >= cutoff }
        return trimmedLeft + trimmedRight
    }
}
