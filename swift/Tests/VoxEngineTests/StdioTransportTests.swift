import Foundation
import Testing
@testable import HudsonSpeechEngine

struct StdioTransportTests {
    @Test("fast provider responses are matched to pending calls")
    func fastProviderResponseDoesNotRacePendingRegistration() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let scriptURL = tempDirectory.appendingPathComponent("fast-provider.js")
        try """
        process.stdin.setEncoding("utf8");
        let buffer = "";
        process.stdin.on("data", (chunk) => {
          buffer += chunk;
          const lines = buffer.split("\\n");
          buffer = lines.pop() ?? "";
          for (const line of lines) {
            if (!line.trim()) continue;
            const req = JSON.parse(line);
            process.stdout.write(JSON.stringify({ jsonrpc: "2.0", id: req.id, result: { ok: true } }) + "\\n");
          }
        });
        """
        .write(to: scriptURL, atomically: true, encoding: .utf8)

        let transport = StdioTransport(
            command: ["/usr/bin/env", "bun", "run", scriptURL.path],
            callTimeoutSeconds: 1
        )

        try transport.start()
        defer { transport.stop() }

        let result = try await transport.call(method: "ping")
        #expect(result["ok"] as? Bool == true)
    }

    @Test("call timeout resumes with timeout error instead of trapping the queue")
    func callTimeoutThrowsTimeoutError() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let scriptURL = tempDirectory.appendingPathComponent("hanging-provider.js")
        try """
        process.stdin.setEncoding("utf8");
        process.stdin.on("data", () => {
          // Intentionally ignore requests so the transport timeout path runs.
        });
        setInterval(() => {}, 1000);
        """
        .write(to: scriptURL, atomically: true, encoding: .utf8)

        let transport = StdioTransport(
            command: ["/usr/bin/env", "bun", "run", scriptURL.path],
            callTimeoutSeconds: 0.1
        )

        try transport.start()
        defer { transport.stop() }

        do {
            _ = try await transport.call(method: "hang")
            Issue.record("Expected call(method:) to time out")
        } catch let error as StdioTransportError {
            switch error {
            case .timeout(let method):
                #expect(method == "hang")
            default:
                Issue.record("Expected timeout error, got \(error.localizedDescription)")
            }
        }
    }
}
