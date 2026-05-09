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

public struct OriginAllowlistSnapshot: Sendable, Equatable {
    public let builtinOrigins: [String]
    public let userOrigins: [String]
    public let integrationOrigins: [String]

    public var effectiveOrigins: [String] {
        Array(Set(builtinOrigins).union(userOrigins).union(integrationOrigins)).sorted()
    }

    public init(
        builtinOrigins: [String],
        userOrigins: [String],
        integrationOrigins: [String]
    ) {
        self.builtinOrigins = builtinOrigins
        self.userOrigins = userOrigins
        self.integrationOrigins = integrationOrigins
    }
}

public actor OriginAllowlist {
    public static let defaultOrigins = [
        "http://127.0.0.1:*",
        "http://localhost:*",
        "https://hudsonkit.com",
        "https://uselinea.com",
        "https://www.hudsonkit.com",
        "https://www.uselinea.com"
    ]

    private let builtinOrigins: Set<String>
    private var userOrigins: Set<String>
    private var integrationOrigins: Set<String>
    private let userFileURL: URL
    private let integrationsDirectoryURL: URL
    private var sourceSnapshot: SourceSnapshot?

    public init(
        userFileURL: URL = RuntimePaths.bridgeOriginsFileURL(),
        integrationsDirectoryURL: URL = RuntimePaths.bridgeOriginsDirectoryURL(),
        builtinOrigins: [String] = OriginAllowlist.defaultOrigins
    ) {
        let initialSnapshot = SourceSnapshot.capture(
            userFileURL: userFileURL,
            integrationsDirectoryURL: integrationsDirectoryURL
        )

        self.userFileURL = userFileURL
        self.integrationsDirectoryURL = integrationsDirectoryURL
        self.builtinOrigins = Set(builtinOrigins.compactMap { try? Self.normalize($0) })
        self.userOrigins = Self.loadOrigins(from: userFileURL)
        self.integrationOrigins = Self.loadOrigins(fromDirectory: integrationsDirectoryURL)
        self.sourceSnapshot = initialSnapshot
    }

    public func check(_ origin: String) -> Bool {
        refreshFromDisk()
        guard let candidate = Self.parseOrigin(origin) else { return false }
        return effectiveOrigins.contains { entry in
            guard let rule = Self.parseRule(entry) else { return false }
            return rule.matches(candidate)
        }
    }

    @discardableResult
    public func add(_ origin: String) throws -> String {
        refreshFromDisk()
        let normalized = try Self.normalize(origin)

        let inserted = userOrigins.insert(normalized).inserted
        if inserted {
            saveUserOrigins()
        }

        return normalized
    }

    @discardableResult
    public func remove(_ origin: String) -> Bool {
        refreshFromDisk()
        guard let normalized = try? Self.normalize(origin) else { return false }

        let removed = userOrigins.remove(normalized) != nil
        if removed {
            saveUserOrigins()
        }

        return removed
    }

    public func list() -> [String] {
        snapshot().effectiveOrigins
    }

    public func snapshot() -> OriginAllowlistSnapshot {
        refreshFromDisk()
        return OriginAllowlistSnapshot(
            builtinOrigins: Array(builtinOrigins).sorted(),
            userOrigins: Array(userOrigins).sorted(),
            integrationOrigins: Array(integrationOrigins).sorted()
        )
    }

    private var effectiveOrigins: Set<String> {
        builtinOrigins.union(userOrigins).union(integrationOrigins)
    }

    private func refreshFromDisk(force: Bool = false) {
        let currentSnapshot = SourceSnapshot.capture(
            userFileURL: userFileURL,
            integrationsDirectoryURL: integrationsDirectoryURL
        )

        guard force || currentSnapshot != sourceSnapshot else { return }

        sourceSnapshot = currentSnapshot
        userOrigins = Self.loadOrigins(from: userFileURL)
        integrationOrigins = Self.loadOrigins(fromDirectory: integrationsDirectoryURL)
    }

    private func saveUserOrigins() {
        do {
            try RuntimePaths.ensureDirectories()
            let file = OriginsFile(origins: Array(userOrigins).sorted())
            let data = try JSONEncoder().encode(file)
            try data.write(to: userFileURL, options: .atomic)
            sourceSnapshot = SourceSnapshot.capture(
                userFileURL: userFileURL,
                integrationsDirectoryURL: integrationsDirectoryURL
            )
        } catch {
            // Best effort.
        }
    }

    private static func loadOrigins(from fileURL: URL) -> Set<String> {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = decodeOrigins(from: data)
            return Set(decoded.compactMap { try? normalize($0) })
        } catch {
            return []
        }
    }

    private static func loadOrigins(fromDirectory directoryURL: URL) -> Set<String> {
        guard FileManager.default.fileExists(atPath: directoryURL.path) else { return [] }

        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return urls.reduce(into: Set<String>()) { collected, url in
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true
            else {
                return
            }

            collected.formUnion(loadOrigins(from: url))
        }
    }

    private static func decodeOrigins(from data: Data) -> [String] {
        if let file = try? JSONDecoder().decode(OriginsFile.self, from: data) {
            return file.origins
        }

        if let file = try? JSONDecoder().decode(SingleOriginFile.self, from: data) {
            return [file.origin]
        }

        if let array = try? JSONDecoder().decode([String].self, from: data) {
            return array
        }

        return []
    }
}

private struct OriginsFile: Codable {
    let origins: [String]
}

private struct SingleOriginFile: Codable {
    let origin: String
}

private struct SourceSnapshot: Equatable {
    let userFile: FileFingerprint?
    let integrationFiles: [FileFingerprint]

    static func capture(userFileURL: URL, integrationsDirectoryURL: URL) -> Self {
        let userFile = FileFingerprint(url: userFileURL)
        let integrationFiles = integrationFingerprints(in: integrationsDirectoryURL)
        return Self(userFile: userFile, integrationFiles: integrationFiles)
    }

    private static func integrationFingerprints(in directoryURL: URL) -> [FileFingerprint] {
        guard FileManager.default.fileExists(atPath: directoryURL.path) else { return [] }

        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true
            else {
                return nil
            }

            return FileFingerprint(url: url)
        }
        .sorted { $0.path < $1.path }
    }
}

private struct FileFingerprint: Equatable {
    let path: String
    let modifiedAt: Date?
    let size: UInt64?

    init?(url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes?[.size] as? NSNumber)?.uint64Value
        let modifiedAt = attributes?[.modificationDate] as? Date

        self.path = url.path
        self.modifiedAt = modifiedAt
        self.size = size
    }
}

// MARK: - Origin parsing and wildcard matching

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

extension OriginAllowlist {
    public static func normalize(_ raw: String) throws -> String {
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

    fileprivate static func parseRule(_ raw: String) -> OriginRule? {
        if raw.hasSuffix(":*") {
            let base = String(raw.dropLast(2))
            guard let parsed = parseOrigin(base), isLoopbackHost(parsed.host) else { return nil }
            return OriginRule(scheme: parsed.scheme, host: parsed.host, port: nil, wildcardPort: true)
        }

        guard let parsed = parseOrigin(raw) else { return nil }
        return OriginRule(scheme: parsed.scheme, host: parsed.host, port: parsed.port, wildcardPort: false)
    }

    fileprivate static func parseOrigin(_ raw: String) -> ParsedOrigin? {
        guard let components = URLComponents(string: raw) else { return nil }
        guard let scheme = components.scheme?.lowercased(), let host = components.host?.lowercased() else { return nil }
        guard components.user == nil, components.password == nil else { return nil }
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
