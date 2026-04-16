import Foundation
import VoxCore

public enum OriginAllowlistError: LocalizedError, Equatable {
    case empty
    case invalidOrigin
    case wildcardHostNotAllowed

    public var errorDescription: String? {
        switch self {
        case .empty:
            "Enter an origin."
        case .invalidOrigin:
            "Enter a full origin like https://app.example.com or http://localhost:3500."
        case .wildcardHostNotAllowed:
            "Wildcard ports are only supported for localhost, 127.0.0.1, and ::1."
        }
    }
}

public actor OriginAllowlist {
    public static let defaultOrigins: Set<String> = ["https://uselinea.com", "https://www.uselinea.com"]
    private var origins: Set<String>
    private let fileURL: URL

    public init(
        fileURL: URL? = nil,
        defaults: Set<String> = OriginAllowlist.defaultOrigins,
        loadFromDisk: Bool = true
    ) {
        let resolvedFileURL = fileURL ?? RuntimePaths.voxHomeURL().appendingPathComponent("origins.json")
        self.fileURL = resolvedFileURL
        if loadFromDisk {
            self.origins = defaults.union(Self.loadOrigins(from: resolvedFileURL))
        } else {
            self.origins = defaults
        }
    }

    public func check(_ origin: String) -> Bool {
        guard let candidate = Self.parseOrigin(origin) else { return false }
        return origins.contains { entry in
            guard let rule = Self.parseRule(entry) else { return false }
            return rule.matches(candidate)
        }
    }

    @discardableResult
    public func add(_ origin: String) throws -> String {
        let normalized = try Self.normalize(origin)
        origins.insert(normalized)
        Task { saveToDisk() }
        return normalized
    }

    public func remove(_ origin: String) {
        guard let normalized = try? Self.normalize(origin) else { return }
        origins.remove(normalized)
        Task { saveToDisk() }
    }

    public func list() -> [String] {
        Array(origins).sorted()
    }

    private static func loadOrigins(from fileURL: URL) -> Set<String> {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try JSONDecoder().decode(OriginsFile.self, from: data)
            var loaded = Set<String>()
            for origin in decoded.origins {
                if let normalized = try? Self.normalize(origin) {
                    loaded.insert(normalized)
                }
            }
            return loaded
        } catch {
            // Keep defaults if file is malformed
            return []
        }
    }

    private func saveToDisk() {
        do {
            try RuntimePaths.ensureDirectories()
            let file = OriginsFile(origins: Array(origins).sorted())
            let data = try JSONEncoder().encode(file)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Best effort
        }
    }
}

private struct OriginsFile: Codable {
    let origins: [String]
}

private struct ParsedOrigin: Equatable {
    let scheme: String
    let host: String
    let port: Int?
}

private struct OriginRule {
    let scheme: String
    let host: String
    let port: Int?
    let wildcardPort: Bool

    func matches(_ origin: ParsedOrigin) -> Bool {
        guard scheme == origin.scheme, host == origin.host else { return false }
        return wildcardPort || port == origin.port
    }
}

private extension OriginAllowlist {
    static func normalize(_ raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw OriginAllowlistError.empty }

        if trimmed.hasSuffix(":*") {
            let base = String(trimmed.dropLast(2))
            guard let parsed = parseOrigin(base) else {
                throw OriginAllowlistError.invalidOrigin
            }
            guard isLoopbackHost(parsed.host) else {
                throw OriginAllowlistError.wildcardHostNotAllowed
            }
            return "\(parsed.scheme)://\(formatHost(parsed.host)):*"
        }

        guard let parsed = parseOrigin(trimmed) else {
            throw OriginAllowlistError.invalidOrigin
        }

        let host = formatHost(parsed.host)
        if let port = parsed.port {
            return "\(parsed.scheme)://\(host):\(port)"
        }
        return "\(parsed.scheme)://\(host)"
    }

    static func parseRule(_ raw: String) -> OriginRule? {
        if raw.hasSuffix(":*") {
            let base = String(raw.dropLast(2))
            guard let parsed = parseOrigin(base), isLoopbackHost(parsed.host) else { return nil }
            return OriginRule(scheme: parsed.scheme, host: parsed.host, port: nil, wildcardPort: true)
        }

        guard let parsed = parseOrigin(raw) else { return nil }
        return OriginRule(scheme: parsed.scheme, host: parsed.host, port: parsed.port, wildcardPort: false)
    }

    static func parseOrigin(_ raw: String) -> ParsedOrigin? {
        guard let components = URLComponents(string: raw) else { return nil }
        guard let scheme = components.scheme?.lowercased(), let host = components.host?.lowercased() else { return nil }
        guard components.user == nil, components.password == nil else { return nil }
        guard components.query == nil, components.fragment == nil else { return nil }
        guard components.path.isEmpty || components.path == "/" else { return nil }
        guard ["http", "https"].contains(scheme) else { return nil }
        return ParsedOrigin(scheme: scheme, host: host, port: components.port)
    }

    static func isLoopbackHost(_ host: String) -> Bool {
        host == "localhost" || host == "127.0.0.1" || host == "::1"
    }

    static func formatHost(_ host: String) -> String {
        host.contains(":") ? "[\(host)]" : host
    }
}
