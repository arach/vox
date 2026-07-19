import Foundation

public enum VoxModelDownloadPolicy: String, Codable, CaseIterable, Sendable {
    case never
    case onFirstUse = "on_first_use"
    case eager

    public var warmsAtServiceStart: Bool {
        self == .eager
    }

    public var warmsOnFirstUse: Bool {
        self != .never
    }
}

public struct VoxSpeechPreferences: Codable, Sendable, Equatable {
    public var preferredTranscriptionModelId: String?
    public var preferredSynthesisModelId: String?
    public var preferredSynthesisVoiceId: String?
    public var preferredInputDeviceId: String?
    public var modelDownloadPolicy: VoxModelDownloadPolicy

    public init(
        preferredTranscriptionModelId: String? = nil,
        preferredSynthesisModelId: String? = nil,
        preferredSynthesisVoiceId: String? = nil,
        preferredInputDeviceId: String? = nil,
        modelDownloadPolicy: VoxModelDownloadPolicy = .onFirstUse
    ) {
        self.preferredTranscriptionModelId = preferredTranscriptionModelId
        self.preferredSynthesisModelId = preferredSynthesisModelId
        self.preferredSynthesisVoiceId = preferredSynthesisVoiceId
        self.preferredInputDeviceId = preferredInputDeviceId
        self.modelDownloadPolicy = modelDownloadPolicy
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            preferredTranscriptionModelId: try values.decodeIfPresent(
                String.self,
                forKey: .preferredTranscriptionModelId
            ),
            preferredSynthesisModelId: try values.decodeIfPresent(String.self, forKey: .preferredSynthesisModelId),
            preferredSynthesisVoiceId: try values.decodeIfPresent(String.self, forKey: .preferredSynthesisVoiceId),
            preferredInputDeviceId: try values.decodeIfPresent(String.self, forKey: .preferredInputDeviceId),
            modelDownloadPolicy: try values.decodeIfPresent(
                VoxModelDownloadPolicy.self,
                forKey: .modelDownloadPolicy
            ) ?? .onFirstUse
        )
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
