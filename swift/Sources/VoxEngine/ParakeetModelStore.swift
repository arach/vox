import Foundation
import VoxCore

struct ParakeetModelManifest: Sendable {
    let modelId: String
    let name: String
    let backend: String
    let repositoryFolderName: String
    let cacheDirectoryName: String
    let requiredModelFiles: Set<String>
    let vocabularyFile: String

    static let v3 = ParakeetModelManifest(
        modelId: "parakeet:v3",
        name: "Parakeet TDT v3",
        backend: "parakeet",
        repositoryFolderName: "FluidInference/parakeet-tdt-0.6b-v3-coreml",
        cacheDirectoryName: "parakeet-tdt-0.6b-v3-coreml",
        requiredModelFiles: [
            "Preprocessor.mlmodelc",
            "Encoder.mlmodelc",
            "Decoder.mlmodelc",
            "JointDecisionv3.mlmodelc",
        ],
        vocabularyFile: "parakeet_vocab.json"
    )
}

struct ParakeetModelStore: Sendable {
    let manifest: ParakeetModelManifest

    init(manifest: ParakeetModelManifest = .v3) {
        self.manifest = manifest
    }

    func isInstalled(fileManager: FileManager = .default) -> Bool {
        installedDirectory(fileManager: fileManager) != nil
    }

    func installedDirectory(fileManager: FileManager = .default) -> URL? {
        installedDirectory(
            fileManager: fileManager,
            candidateDirectories: candidateModelDirectories(fileManager: fileManager)
        )
    }

    func installedDirectory(fileManager: FileManager = .default, candidateDirectories: [URL]) -> URL? {
        candidateDirectories.first { directory in
            hasRequiredArtifacts(at: directory, fileManager: fileManager)
        }
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

    func loadVocabulary(fileManager: FileManager = .default) throws -> [Int: String] {
        guard let directory = installedDirectory(fileManager: fileManager) else {
            throw NSError(domain: "VoxEngine", code: 101, userInfo: [
                NSLocalizedDescriptionKey: "Parakeet vocabulary is unavailable because the model is not installed."
            ])
        }

        let vocabularyURL = directory.appendingPathComponent(manifest.vocabularyFile)
        return try ParakeetVocabulary.load(from: vocabularyURL)
    }

    private func hasRequiredArtifacts(at directory: URL, fileManager: FileManager) -> Bool {
        guard fileManager.fileExists(atPath: directory.path) else {
            return false
        }

        let requiredModelsPresent = manifest.requiredModelFiles.allSatisfy { fileName in
            fileManager.fileExists(atPath: directory.appendingPathComponent(fileName).path)
        }
        guard requiredModelsPresent else {
            return false
        }

        return fileManager.fileExists(atPath: directory.appendingPathComponent(manifest.vocabularyFile).path)
    }
}
