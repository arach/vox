import Foundation

public struct VoxSpeechPreferences: Codable, Sendable, Equatable {
    public var preferredTranscriptionModelId: String?
    public var preferredSynthesisModelId: String?
    public var preferredSynthesisVoiceId: String?

    public init(
        preferredTranscriptionModelId: String? = nil,
        preferredSynthesisModelId: String? = nil,
        preferredSynthesisVoiceId: String? = nil
    ) {
        self.preferredTranscriptionModelId = preferredTranscriptionModelId
        self.preferredSynthesisModelId = preferredSynthesisModelId
        self.preferredSynthesisVoiceId = preferredSynthesisVoiceId
    }
}

public struct VoxPreferences: Codable, Sendable, Equatable {
    public var speech: VoxSpeechPreferences

    public init(speech: VoxSpeechPreferences = VoxSpeechPreferences()) {
        self.speech = speech
    }

    public static func load(from url: URL = RuntimePaths.preferencesFileURL()) throws -> VoxPreferences {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return VoxPreferences()
        }

        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(VoxPreferences.self, from: data)
    }

    public func save(to url: URL = RuntimePaths.preferencesFileURL()) throws {
        try RuntimePaths.ensureDirectories()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: url, options: .atomic)
    }
}
