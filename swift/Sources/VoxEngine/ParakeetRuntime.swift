import Foundation
import VoxCore

protocol ParakeetRuntime: Sendable {
    var isAvailable: Bool { get }
    func isPreloaded() async -> Bool
    func load(progress: @escaping @Sendable (ModelProgress) -> Void) async throws
    func transcribe(url: URL) async throws -> ParakeetInferenceResult
}

struct ParakeetInferenceResult: Sendable {
    let text: String
    let words: [WordTiming]
}
