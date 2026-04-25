import Foundation
import VoxCore

struct ParakeetModelManifest: Sendable {
    let modelId: String
    let name: String
    let backend: String
    let cacheDirectoryName: String

    static let v3 = ParakeetModelManifest(
        modelId: "parakeet:v3",
        name: "Parakeet TDT v3",
        backend: "parakeet",
        cacheDirectoryName: "parakeet-tdt-0.6b-v3-coreml"
    )
}

struct ParakeetModelStore: Sendable {
    let manifest: ParakeetModelManifest

    init(manifest: ParakeetModelManifest = .v3) {
        self.manifest = manifest
    }

    func isInstalled(fileManager: FileManager = .default) -> Bool {
        for directory in candidateModelDirectories(fileManager: fileManager) {
            guard fileManager.fileExists(atPath: directory.path) else {
                continue
            }

            if let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: nil) {
                for case let url as URL in enumerator where url.pathExtension == "mlmodelc" {
                    return true
                }
            }
        }

        return false
    }

    func candidateModelDirectories(fileManager: FileManager = .default) -> [URL] {
        let runtimeCacheRoot = RuntimePaths.voxHomeURL().appendingPathComponent("cache", isDirectory: true)
        let cacheDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
        let appSupportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first

        let roots = [runtimeCacheRoot, cacheDirectory, appSupportDirectory].compactMap { $0 }

        return roots.map { root in
            root
                .appendingPathComponent("FluidAudio", isDirectory: true)
                .appendingPathComponent("Models", isDirectory: true)
                .appendingPathComponent(manifest.cacheDirectoryName, isDirectory: true)
        }
    }
}
