import Foundation

public struct ProvidersConfig: Codable, Sendable {
    public let providers: [ProviderEntry]

    public init(providers: [ProviderEntry]) {
        self.providers = providers
    }

    public static func load(from url: URL) throws -> ProvidersConfig {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ProvidersConfig.self, from: data)
    }
}

public struct ProviderEntry: Codable, Sendable {
    public let id: String
    public let builtin: Bool?
    public let command: [String]?
    public let models: [String]?
    public let env: [String: String]?

    public init(
        id: String,
        builtin: Bool? = nil,
        command: [String]? = nil,
        models: [String]? = nil,
        env: [String: String]? = nil
    ) {
        self.id = id
        self.builtin = builtin
        self.command = command
        self.models = models
        self.env = env
    }

    public var isBuiltin: Bool {
        builtin == true
    }

    public var isExternal: Bool {
        command != nil && !command!.isEmpty
    }
}
