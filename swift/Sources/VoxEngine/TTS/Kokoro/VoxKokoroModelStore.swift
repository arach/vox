import Foundation
import VoxCore

struct VoxKokoroModelStore: Sendable {
    let modelId: String
    let env: [String: String]

    private let requiredPaths = [
        "config.json",
        "kokoro-v1_0.safetensors",
        "voices",
    ]

    init(
        modelId: String = VoxKokoroTTS.modelID,
        env: [String: String] = VoxKokoroTTS.environment()
    ) {
        self.modelId = modelId
        self.env = env
    }

    func huggingFaceHomeURL() -> URL {
        if let override = env["HF_HOME"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return VoxKokoroTTS.huggingFaceHomeURL()
    }

    func hubCacheURL() -> URL {
        if let override = env["HF_HUB_CACHE"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return huggingFaceHomeURL().appendingPathComponent("hub", isDirectory: true)
    }

    func repositoryCacheDirectory() -> URL {
        hubCacheURL().appendingPathComponent(repositoryCacheDirectoryName(), isDirectory: true)
    }

    func isInstalled(fileManager: FileManager = .default) -> Bool {
        installedSnapshotDirectory(fileManager: fileManager) != nil
    }

    func installedSnapshotDirectory(fileManager: FileManager = .default) -> URL? {
        let snapshotsRoot = repositoryCacheDirectory().appendingPathComponent("snapshots", isDirectory: true)
        guard let snapshotNames = try? fileManager.contentsOfDirectory(atPath: snapshotsRoot.path) else {
            return nil
        }

        for snapshotName in snapshotNames.sorted() {
            let candidate = snapshotsRoot.appendingPathComponent(snapshotName, isDirectory: true)
            if hasRequiredArtifacts(at: candidate, fileManager: fileManager) {
                return candidate
            }
        }

        return nil
    }

    private func repositoryCacheDirectoryName() -> String {
        "models--" + modelId.replacingOccurrences(of: "/", with: "--")
    }

    private func hasRequiredArtifacts(at directory: URL, fileManager: FileManager) -> Bool {
        requiredPaths.allSatisfy { relativePath in
            fileManager.fileExists(atPath: directory.appendingPathComponent(relativePath).path)
        }
    }
}
