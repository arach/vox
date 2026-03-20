import Foundation
import VoxCore

public actor OriginAllowlist {
    private var origins: Set<String>
    private let fileURL: URL

    public init() {
        self.fileURL = RuntimePaths.voxHomeURL().appendingPathComponent("origins.json")
        self.origins = ["https://uselinea.com", "https://www.uselinea.com"]
        Task { await self.loadFromDisk() }
    }

    public func check(_ origin: String) -> Bool {
        origins.contains(origin)
    }

    public func add(_ origin: String) {
        origins.insert(origin)
        Task { await saveToDisk() }
    }

    public func remove(_ origin: String) {
        origins.remove(origin)
        Task { await saveToDisk() }
    }

    public func list() -> [String] {
        Array(origins).sorted()
    }

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try JSONDecoder().decode(OriginsFile.self, from: data)
            for origin in decoded.origins {
                origins.insert(origin)
            }
        } catch {
            // Keep defaults if file is malformed
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
