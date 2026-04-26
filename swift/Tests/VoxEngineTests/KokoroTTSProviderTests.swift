import Foundation
import Testing
@testable import VoxEngine

struct KokoroTTSProviderTests {
    @Test("Kokoro preflight recognizes uv on PATH")
    func kokoroPreflightRecognizesUvOnPath() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let binDirectory = tempDirectory.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: binDirectory, withIntermediateDirectories: true)

        let uvPath = binDirectory.appendingPathComponent("uv")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: uvPath)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: uvPath.path)

        let preflight = VoxKokoroPreflight(
            env: [
                "VOX_MLX_AUDIO_USE_UV": "1",
                "HF_HOME": tempDirectory.path,
                "PATH": binDirectory.path,
            ],
            processEnv: [:]
        )

        #expect(preflight.prerequisiteCheck.status == "ok")
        #expect(preflight.prerequisiteCheck.detail.contains("uv ready"))
    }

    @Test("Kokoro preflight warns when uv is missing")
    func kokoroPreflightWarnsWhenUvMissing() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let preflight = VoxKokoroPreflight(
            env: [
                "VOX_MLX_AUDIO_USE_UV": "1",
                "HF_HOME": tempDirectory.path,
                "PATH": tempDirectory.path,
            ],
            processEnv: [:]
        )

        #expect(preflight.prerequisiteCheck.status == "warning")
        #expect(preflight.prerequisiteCheck.detail.contains("Install uv"))
        #expect(preflight.modelCheck.status == "warning")
        #expect(preflight.modelCheck.detail.contains("not cached yet"))
    }

    @Test("Kokoro model store recognizes installed snapshots in the Vox HF cache layout")
    func kokoroModelStoreRecognizesInstalledSnapshots() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let store = VoxKokoroModelStore(env: [
            "HF_HOME": tempDirectory.path
        ])

        let snapshotDirectory = store.repositoryCacheDirectory()
            .appendingPathComponent("snapshots", isDirectory: true)
            .appendingPathComponent("test-revision", isDirectory: true)

        try FileManager.default.createDirectory(
            at: snapshotDirectory.appendingPathComponent("voices", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data("{}".utf8).write(to: snapshotDirectory.appendingPathComponent("config.json"))
        try Data("weights".utf8).write(to: snapshotDirectory.appendingPathComponent("kokoro-v1_0.safetensors"))

        #expect(store.isInstalled())
        #expect(store.installedSnapshotDirectory() == snapshotDirectory)
    }

    @Test("Kokoro provider entry carries the Vox HF cache env")
    func kokoroProviderEntryCarriesOwnedCacheEnvironment() throws {
        let entry = VoxKokoroTTS.providerEntry()
        let env = try #require(entry.env)

        #expect(env["HF_HOME"]?.hasSuffix("/.vox/cache/huggingface") == true)
        #expect(env["HF_HUB_CACHE"]?.hasSuffix("/.vox/cache/huggingface/hub") == true)
        #expect(env["VOX_PROVIDER_BACKEND"] == VoxKokoroTTS.backendID)
    }
}
