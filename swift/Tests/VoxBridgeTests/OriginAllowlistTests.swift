import Foundation
import Testing
@testable import VoxBridge

struct OriginAllowlistTests {
    @Test("Allowlist merges built-in, user, and integration origins")
    func mergesOriginSources() async throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox.rootURL) }

        try sandbox.writeUserOrigins([
            "https://Hudson.ai/",
            "https://docs.hudson.ai/path"
        ])
        try sandbox.writeIntegrationOrigins(
            named: "hudson.json",
            contents: #"{"origins":["https://app.customer-one.com","https://app.customer-two.com/"]}"#
        )

        let allowlist = sandbox.makeAllowlist()
        let snapshot = await allowlist.snapshot()

        #expect(snapshot.builtinOrigins == [
            "https://uselinea.com",
            "https://www.uselinea.com"
        ])
        #expect(snapshot.userOrigins == [
            "https://docs.hudson.ai",
            "https://hudson.ai"
        ])
        #expect(snapshot.integrationOrigins == [
            "https://app.customer-one.com",
            "https://app.customer-two.com"
        ])
        #expect(await allowlist.check("https://docs.hudson.ai"))
        #expect(await allowlist.check("https://app.customer-two.com"))
    }

    @Test("Allowlist notices new integration origins after initialization")
    func reloadsDropInsWhenFilesChange() async throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox.rootURL) }

        let allowlist = sandbox.makeAllowlist()
        #expect(await allowlist.check("https://project.hudson.ai") == false)

        try sandbox.writeIntegrationOrigins(
            named: "hudson.json",
            contents: #"{"origin":"https://project.hudson.ai/"}"#
        )

        #expect(await allowlist.check("https://project.hudson.ai"))
    }

    @Test("User-managed origins can be added and removed without affecting integrations")
    func addAndRemoveOnlyTouchesUserOrigins() async throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox.rootURL) }

        try sandbox.writeIntegrationOrigins(
            named: "hudson.json",
            contents: #"["https://workspace.hudson.ai"]"#
        )

        let allowlist = sandbox.makeAllowlist()

        let added = try await allowlist.add("https://portal.hudson.ai/")
        #expect(added == "https://portal.hudson.ai")
        #expect(await allowlist.check("https://portal.hudson.ai"))
        #expect(await allowlist.check("https://workspace.hudson.ai"))

        #expect(await allowlist.remove("https://portal.hudson.ai"))
        #expect(await allowlist.check("https://portal.hudson.ai") == false)
        #expect(await allowlist.check("https://workspace.hudson.ai"))
    }

    @Test("Exact origins are normalized and matched exactly")
    func exactOriginsMatchOnlyTheConfiguredOrigin() async throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox.rootURL) }

        let allowlist = sandbox.makeAllowlist(builtinOrigins: [])
        _ = try await allowlist.add("http://localhost:3500/")

        let allowed = await allowlist.check("http://localhost:3500")
        let blocked = await allowlist.check("http://localhost:3501")

        #expect(allowed)
        #expect(!blocked)
    }

    @Test("Localhost wildcard ports match any loopback port on the same host")
    func localhostWildcardPortsMatch() async throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox.rootURL) }

        let allowlist = sandbox.makeAllowlist(builtinOrigins: [])
        _ = try await allowlist.add("http://localhost:*")

        #expect(await allowlist.check("http://localhost:3000"))
        #expect(await allowlist.check("http://localhost:3500"))
        #expect(!(await allowlist.check("http://127.0.0.1:3500")))
    }

    @Test("Wildcard ports are rejected for non-loopback hosts")
    func wildcardPortsAreRestrictedToLoopbackHosts() async throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox.rootURL) }

        let allowlist = sandbox.makeAllowlist(builtinOrigins: [])

        do {
            _ = try await allowlist.add("https://example.com:*")
            Issue.record("Expected wildcard host validation to fail")
        } catch let error as OriginAllowlistError {
            #expect(error == .wildcardHostNotAllowed)
        }
    }
}

private func makeSandbox() throws -> OriginSandbox {
    let rootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let userFileURL = rootURL.appendingPathComponent("origins.json")
    let integrationsDirectoryURL = rootURL.appendingPathComponent("origins.d", isDirectory: true)

    try FileManager.default.createDirectory(at: integrationsDirectoryURL, withIntermediateDirectories: true)

    return OriginSandbox(
        rootURL: rootURL,
        userFileURL: userFileURL,
        integrationsDirectoryURL: integrationsDirectoryURL
    )
}

private struct OriginSandbox {
    let rootURL: URL
    let userFileURL: URL
    let integrationsDirectoryURL: URL

    func makeAllowlist(builtinOrigins: [String] = OriginAllowlist.defaultOrigins) -> OriginAllowlist {
        OriginAllowlist(
            userFileURL: userFileURL,
            integrationsDirectoryURL: integrationsDirectoryURL,
            builtinOrigins: builtinOrigins
        )
    }

    func writeUserOrigins(_ origins: [String]) throws {
        let data = try JSONEncoder().encode(["origins": origins])
        try data.write(to: userFileURL, options: .atomic)
    }

    func writeIntegrationOrigins(named fileName: String, contents: String) throws {
        let url = integrationsDirectoryURL.appendingPathComponent(fileName)
        try Data(contents.utf8).write(to: url, options: .atomic)
    }
}
