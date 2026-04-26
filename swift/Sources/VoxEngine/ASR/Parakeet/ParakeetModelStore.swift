import Foundation
#if canImport(FluidAudio)
import FluidAudio
#endif
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
        downloader: any ParakeetModelArtifactDownloader = FluidAudioParakeetArtifactDownloader(),
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
            .appendingPathComponent("FluidAudio", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
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

struct FluidAudioParakeetArtifactDownloader: ParakeetModelArtifactDownloader {
    func download(
        manifest: ParakeetModelManifest,
        to modelsRootDirectory: URL,
        progress: @escaping @Sendable (ModelProgress) -> Void
    ) async throws {
        #if canImport(FluidAudio)
        try await DownloadUtils.downloadRepo(
            manifest.fluidAudioRepository,
            to: modelsRootDirectory
        ) { update in
            progress(Self.modelProgress(for: manifest, update: update))
        }
        #else
        throw NSError(domain: "VoxEngine", code: 105, userInfo: [
            NSLocalizedDescriptionKey: "FluidAudio is unavailable in this build."
        ])
        #endif
    }

    #if canImport(FluidAudio)
    private static func modelProgress(
        for manifest: ParakeetModelManifest,
        update: DownloadUtils.DownloadProgress
    ) -> ModelProgress {
        let status: String
        switch update.phase {
        case .listing:
            status = "listing"
        case .downloading(let completedFiles, let totalFiles):
            if totalFiles > 0 {
                status = "downloading \(completedFiles)/\(totalFiles)"
            } else {
                status = "downloading"
            }
        case .compiling(let modelName):
            status = "compiling \(modelName)"
        }

        let scaledProgress = min(max((update.fractionCompleted * 0.7) + 0.1, 0.1), 0.75)
        return ModelProgress(modelId: manifest.modelId, progress: scaledProgress, status: status)
    }
    #endif
}

#if canImport(FluidAudio)
private extension ParakeetModelManifest {
    var fluidAudioRepository: Repo {
        guard let repository = Repo(rawValue: repositoryFolderName) else {
            preconditionFailure("Unsupported FluidAudio repository: \(repositoryFolderName)")
        }
        return repository
    }
}
#endif
