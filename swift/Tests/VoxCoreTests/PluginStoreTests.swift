import Foundation
import Testing
@testable import VoxCore

struct PluginStoreTests {
    @Test("Plugin command validator allows node and rejects shells")
    func commandValidatorAllowlist() throws {
        try PluginCommandValidator.validate(["node", "/tmp/provider.mjs"])
        try PluginCommandValidator.validate(["npx", "-y", "@voxd/plugin-mlx-vlm"])

        #expect(throws: PluginCommandError.self) {
            try PluginCommandValidator.validate(["bash", "-c", "rm -rf /"])
        }
        #expect(throws: PluginCommandError.self) {
            try PluginCommandValidator.validate(["node", "foo; bar"])
        }
    }

    @Test("Plugin identifier validator rejects traversal and path separators")
    func identifierValidatorRejectsTraversal() throws {
        for id in ["../escape", "nested/plugin", "nested\\plugin", "a..b", ".hidden", "Uppercase"] {
            #expect(throws: PluginIdentifierError.self) {
                try PluginIdentifierValidator.validate(id)
            }
        }

        for id in ["mlx-vlm", "mlx_vlm.v2", "plugin-2"] {
            try PluginIdentifierValidator.validate(id)
        }
    }

    @Test("Plugin store rejects traversal ids before filesystem access")
    func storeRejectsTraversalIDs() throws {
        let plugin = ProviderEntry(
            id: "../escape",
            kind: .asr,
            command: ["node", "/tmp/provider.mjs"],
            models: []
        )
        #expect(throws: PluginIdentifierError.self) {
            try PluginStore.install(plugin)
        }
        #expect(throws: PluginIdentifierError.self) {
            try PluginStore.remove(id: "../escape")
        }
        #expect(!PluginStore.isInstalled(id: "../escape"))
    }

    @Test("Plugin store writes provider.json and merges without replacing existing ids")
    func installRoundTripAndMerge() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        setenv("VOX_HOME", directory.path, 1)
        defer {
            unsetenv("VOX_HOME")
            try? FileManager.default.removeItem(at: directory)
        }

        let plugin = ProviderEntry(
            id: "mlx-vlm",
            kind: .asr,
            command: ["node", "/tmp/mlx-vlm.mjs"],
            models: ["gemma-4-e2b-it"]
        )
        try PluginStore.install(plugin)
        #expect(PluginStore.isInstalled(id: "mlx-vlm"))

        let loaded = PluginStore.loadInstalled()
        #expect(loaded.map(\.id) == ["mlx-vlm"])
        #expect(loaded.first?.models == ["gemma-4-e2b-it"])

        let merged = ProvidersConfig(providers: [
            ProviderEntry(id: "parakeet", kind: .asr, builtin: true, models: ["parakeet:v3"])
        ]).merging(loaded)
        #expect(merged.providers.map(\.id) == ["parakeet", "mlx-vlm"])

        try PluginStore.remove(id: "mlx-vlm")
        #expect(!PluginStore.isInstalled(id: "mlx-vlm"))
    }
}
