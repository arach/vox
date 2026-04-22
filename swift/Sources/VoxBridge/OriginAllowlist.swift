import Foundation
import VoxCore

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
        "https://uselinea.com",
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
        self.builtinOrigins = Set(builtinOrigins.compactMap(Self.normalize))
        self.userOrigins = Self.loadOrigins(from: userFileURL)
        self.integrationOrigins = Self.loadOrigins(fromDirectory: integrationsDirectoryURL)
        self.sourceSnapshot = initialSnapshot
    }

    public func check(_ origin: String) -> Bool {
        refreshFromDisk()
        guard let normalized = Self.normalize(origin) else { return false }
        return effectiveOrigins.contains(normalized)
    }

    @discardableResult
    public func add(_ origin: String) -> String? {
        refreshFromDisk()
        guard let normalized = Self.normalize(origin) else { return nil }

        let inserted = userOrigins.insert(normalized).inserted
        if inserted {
            saveUserOrigins()
        }

        return normalized
    }

    @discardableResult
    public func remove(_ origin: String) -> Bool {
        refreshFromDisk()
        guard let normalized = Self.normalize(origin) else { return false }

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

    public static func normalize(_ origin: String) -> String? {
        let trimmed = origin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        guard var components = URLComponents(string: trimmed) else { return nil }
        guard let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host?.lowercased(),
              !host.isEmpty
        else {
            return nil
        }

        guard components.user == nil, components.password == nil else { return nil }

        components.scheme = scheme
        components.host = host
        components.path = ""
        components.query = nil
        components.fragment = nil

        return components.string
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
            return Set(decoded.compactMap(normalize))
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
