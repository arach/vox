import Foundation
import Testing
@testable import VoxBridge

struct OriginAllowlistTests {
    @Test("Exact origins are normalized and matched exactly")
    func exactOriginsMatchOnlyTheConfiguredOrigin() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("origins.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let allowlist = OriginAllowlist(fileURL: fileURL, defaults: [], loadFromDisk: false)
        _ = try await allowlist.add("http://localhost:3500/")

        let allowed = await allowlist.check("http://localhost:3500")
        let blocked = await allowlist.check("http://localhost:3501")

        #expect(allowed)
        #expect(!blocked)
    }

    @Test("Localhost wildcard ports match any loopback port on the same host")
    func localhostWildcardPortsMatch() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("origins.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let allowlist = OriginAllowlist(fileURL: fileURL, defaults: [], loadFromDisk: false)
        _ = try await allowlist.add("http://localhost:*")

        #expect(await allowlist.check("http://localhost:3000"))
        #expect(await allowlist.check("http://localhost:3500"))
        #expect(!(await allowlist.check("http://127.0.0.1:3500")))
    }

    @Test("Wildcard ports are rejected for non-loopback hosts")
    func wildcardPortsAreRestrictedToLoopbackHosts() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("origins.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let allowlist = OriginAllowlist(fileURL: fileURL, defaults: [], loadFromDisk: false)

        do {
            _ = try await allowlist.add("https://example.com:*")
            Issue.record("Expected wildcard host validation to fail")
        } catch let error as OriginAllowlistError {
            #expect(error == .wildcardHostNotAllowed)
        }
    }
}
