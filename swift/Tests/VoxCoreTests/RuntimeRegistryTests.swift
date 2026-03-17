import Foundation
import Testing
@testable import VoxCore

struct RuntimeRegistryTests {
    @Test("Runtime registry writes and reads runtime metadata")
    func runtimeRegistryRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        setenv("VOX_HOME", directory.path, 1)
        defer {
            unsetenv("VOX_HOME")
            try? FileManager.default.removeItem(at: directory)
        }

        let runtime = RuntimeInfo(
            version: "0.1.0",
            serviceName: "Vox",
            port: 42137,
            pid: 99,
            startedAt: Date(timeIntervalSince1970: 0)
        )

        try RuntimeRegistry.write(runtime)
        let loaded = try RuntimeRegistry.read()
        #expect(loaded == runtime)

        try RuntimeRegistry.remove()
        #expect(try RuntimeRegistry.read() == nil)
    }
}
