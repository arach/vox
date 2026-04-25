import Foundation
import Testing
@testable import VoxEngine

struct StdioTransportTests {
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
