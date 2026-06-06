import Foundation
import VoxCore

public struct AnnotationInputTranscription: Sendable, Equatable {
    public let text: String
    public let words: [WordTiming]

    public init(text: String, words: [WordTiming]) {
        self.text = text
        self.words = words
    }
}

public struct AnnotationRequest: Sendable, Equatable {
    public let url: URL
    public let modelId: String
    public let transcription: AnnotationInputTranscription?

    public init(
        url: URL,
        modelId: String,
        transcription: AnnotationInputTranscription? = nil
    ) {
        self.url = url
        self.modelId = modelId
        self.transcription = transcription
    }
}

public enum AnnotationProviderError: LocalizedError {
    case unavailable(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable(let message):
            return message
        }
    }
}

public protocol AnnotationProvider: Sendable {
    func annotate(request: AnnotationRequest) async throws -> AnnotationOutput
}

public struct UnavailableAnnotationProvider: AnnotationProvider {
    private let message: String

    public init(
        message: String = "Speaker annotation is not configured in this build yet."
    ) {
        self.message = message
    }

    public func annotate(request: AnnotationRequest) async throws -> AnnotationOutput {
        throw AnnotationProviderError.unavailable(message)
    }
}

public actor AnnotationManager {
    private let provider: any AnnotationProvider

    public init(provider: any AnnotationProvider = UnavailableAnnotationProvider()) {
        self.provider = provider
    }

    public func annotate(request: AnnotationRequest) async throws -> AnnotationOutput {
        try await provider.annotate(request: request)
    }
}
