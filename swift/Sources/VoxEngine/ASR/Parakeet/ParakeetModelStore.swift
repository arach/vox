import Foundation
import VoxCore

struct ParakeetModelManifest: Sendable {
    let modelId: String
    let name: String
    let backend: String
    let repositoryFolderName: String
    let cacheDirectoryName: String
    let legacyCacheDirectoryNames: [String]
    let requiredModelFiles: Set<String>
    let vocabularyFile: String

    static let v3 = ParakeetModelManifest(
        modelId: "parakeet:v3",
        name: "Parakeet TDT v3",
        backend: "parakeet",
        repositoryFolderName: "FluidInference/parakeet-tdt-0.6b-v3-coreml",
        cacheDirectoryName: "parakeet-tdt-0.6b-v3",
        legacyCacheDirectoryNames: ["parakeet-tdt-0.6b-v3-coreml"],
        requiredModelFiles: [
            "Preprocessor.mlmodelc",
            "Encoder.mlmodelc",
            "Decoder.mlmodelc",
            "JointDecisionv3.mlmodelc",
        ],
        vocabularyFile: "parakeet_vocab.json"
    )

    var candidateDirectoryNames: [String] {
        [cacheDirectoryName] + legacyCacheDirectoryNames
    }
}

struct ParakeetModelStore: Sendable {
    let manifest: ParakeetModelManifest
    private let downloader: any ParakeetModelArtifactDownloader
    private let preferredModelsRootOverride: URL?

    init(
        manifest: ParakeetModelManifest = .v3,
        downloader: any ParakeetModelArtifactDownloader = VoxParakeetArtifactDownloader(),
        preferredModelsRootDirectory: URL? = nil
    ) {
        self.manifest = manifest
        self.downloader = downloader
        self.preferredModelsRootOverride = preferredModelsRootDirectory
    }

    func isInstalled(fileManager: FileManager = .default) -> Bool {
        installedDirectory(fileManager: fileManager) != nil
    }

    func preferredModelsRootDirectory(fileManager: FileManager = .default) -> URL {
        if let preferredModelsRootOverride {
            return preferredModelsRootOverride
        }

        return RuntimePaths.voxHomeURL()
            .appendingPathComponent("cache", isDirectory: true)
            .appendingPathComponent("models", isDirectory: true)
    }

    func preferredInstallDirectory(fileManager: FileManager = .default) -> URL {
        preferredModelsRootDirectory(fileManager: fileManager)
            .appendingPathComponent(manifest.cacheDirectoryName, isDirectory: true)
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
        if let preferredModelsRootOverride {
            return manifest.candidateDirectoryNames.map { directoryName in
                preferredModelsRootOverride.appendingPathComponent(directoryName, isDirectory: true)
            }
        }

        let cacheDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
        let appSupportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first

        let roots = [
            preferredModelsRootDirectory(fileManager: fileManager),
            RuntimePaths.voxHomeURL()
                .appendingPathComponent("cache", isDirectory: true)
                .appendingPathComponent("FluidAudio", isDirectory: true)
                .appendingPathComponent("Models", isDirectory: true),
            cacheDirectory?
                .appendingPathComponent("FluidAudio", isDirectory: true)
                .appendingPathComponent("Models", isDirectory: true),
            appSupportDirectory?
                .appendingPathComponent("FluidAudio", isDirectory: true)
                .appendingPathComponent("Models", isDirectory: true)
        ].compactMap { $0 }

        return roots.flatMap { root in
            manifest.candidateDirectoryNames.map { directoryName in
                root.appendingPathComponent(directoryName, isDirectory: true)
            }
        }
    }

    func ensureInstalled(
        fileManager: FileManager = .default,
        progress: @escaping @Sendable (ModelProgress) -> Void
    ) async throws -> URL {
        if let installed = installedDirectory(fileManager: fileManager) {
            progress(ModelProgress(modelId: manifest.modelId, progress: 0.8, status: "installed"))
            return installed
        }

        let modelsRoot = preferredModelsRootDirectory(fileManager: fileManager)
        try fileManager.createDirectory(at: modelsRoot, withIntermediateDirectories: true)

        progress(ModelProgress(modelId: manifest.modelId, progress: 0.05, status: "starting"))
        try await downloader.download(manifest: manifest, to: modelsRoot, progress: progress)

        let preferredInstall = preferredInstallDirectory(fileManager: fileManager)
        let candidateDirectories = [preferredInstall] + candidateModelDirectories(fileManager: fileManager)
        if let installed = installedDirectory(
            fileManager: fileManager,
            candidateDirectories: candidateDirectories
        ) {
            progress(ModelProgress(modelId: manifest.modelId, progress: 0.8, status: "installed"))
            return installed
        }

        throw NSError(domain: "VoxEngine", code: 104, userInfo: [
            NSLocalizedDescriptionKey:
                "Parakeet model download completed, but the expected model artifacts were not found."
        ])
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

protocol ParakeetModelArtifactDownloader: Sendable {
    func download(
        manifest: ParakeetModelManifest,
        to modelsRootDirectory: URL,
        progress: @escaping @Sendable (ModelProgress) -> Void
    ) async throws
}

struct VoxParakeetArtifactDownloader: ParakeetModelArtifactDownloader {
    private let log = VoxLog.engine

    func download(
        manifest: ParakeetModelManifest,
        to modelsRootDirectory: URL,
        progress: @escaping @Sendable (ModelProgress) -> Void
    ) async throws {
        log.info("Downloading \(manifest.cacheDirectoryName) from model registry")

        let installDirectory = modelsRootDirectory.appendingPathComponent(
            manifest.cacheDirectoryName,
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: installDirectory, withIntermediateDirectories: true)

        let requiredDirectoryPrefixes = manifest.requiredModelFiles.map { "\($0)/" }
        let metadataFiles: Set<String> = [manifest.vocabularyFile, "config.json"]
        var filesToDownload: [(path: String, size: Int)] = []

        func shouldProcessDirectory(_ itemPath: String) -> Bool {
            requiredDirectoryPrefixes.contains { prefix in
                itemPath == String(prefix.dropLast())
                    || itemPath.hasPrefix(prefix)
                    || prefix.hasPrefix(itemPath + "/")
            }
        }

        func shouldIncludeFile(_ itemPath: String) -> Bool {
            metadataFiles.contains(itemPath)
                || requiredDirectoryPrefixes.contains { itemPath.hasPrefix($0) }
        }

        func listDirectory(path: String) async throws {
            let items = try await VoxModelHub.listDirectory(
                repoPath: manifest.repositoryFolderName,
                path: path
            )
            for item in items {
                guard let itemPath = item["path"] as? String,
                      let itemType = item["type"] as? String else {
                    continue
                }

                if itemType == "directory" {
                    if shouldProcessDirectory(itemPath) {
                        try await listDirectory(path: itemPath)
                    }
                } else if itemType == "file", shouldIncludeFile(itemPath) {
                    let fileSize = item["size"] as? Int ?? -1
                    filesToDownload.append((path: itemPath, size: fileSize))
                }
            }
        }

        progress(ModelProgress(modelId: manifest.modelId, progress: 0.1, status: "listing"))
        try await listDirectory(path: "")
        filesToDownload.sort { $0.path < $1.path }

        for (index, file) in filesToDownload.enumerated() {
            let destinationURL = installDirectory.appendingPathComponent(file.path)
            try await VoxModelHub.downloadFile(
                repoPath: manifest.repositoryFolderName,
                remotePath: file.path,
                to: destinationURL
            )

            let fraction = filesToDownload.isEmpty ? 1.0 : Double(index + 1) / Double(filesToDownload.count)
            let scaledProgress = min(max((fraction * 0.7) + 0.1, 0.1), 0.8)
            progress(
                ModelProgress(
                    modelId: manifest.modelId,
                    progress: scaledProgress,
                    status: "downloading \(index + 1)/\(filesToDownload.count)"
                )
            )
        }

        for requiredModel in manifest.requiredModelFiles {
            let modelPath = installDirectory.appendingPathComponent(requiredModel)
            guard FileManager.default.fileExists(atPath: modelPath.path) else {
                throw VoxModelHubError.modelNotFound(path: requiredModel)
            }
        }

        let vocabularyPath = installDirectory.appendingPathComponent(manifest.vocabularyFile)
        guard FileManager.default.fileExists(atPath: vocabularyPath.path) else {
            throw VoxModelHubError.modelNotFound(path: manifest.vocabularyFile)
        }

        log.info("Downloaded all required artifacts for \(manifest.cacheDirectoryName)")
    }
}
