import Foundation
import Testing
@testable import VoxEngine

struct ParakeetModelStoreTests {
    @Test("Parakeet model store only reports installed when all required model files and vocabulary exist")
    func installationRequiresExpectedArtifacts() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let manifest = ParakeetModelManifest.v3
        let store = ParakeetModelStore(manifest: manifest)
        let installDirectory = tempDirectory.appendingPathComponent(manifest.cacheDirectoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: installDirectory, withIntermediateDirectories: true)

        #expect(!store.isInstalled(fileManager: .default))

        for fileName in manifest.requiredModelFiles {
            try FileManager.default.createDirectory(
                at: installDirectory.appendingPathComponent(fileName, isDirectory: true),
                withIntermediateDirectories: true
            )
        }

        #expect(!store.isInstalled(fileManager: .default))

        try Data("{\"0\":\"<unk>\",\"1\":\"hello\"}".utf8)
            .write(to: installDirectory.appendingPathComponent(manifest.vocabularyFile))

        let customStore = ParakeetModelStore(manifest: manifest)
        let installed = customStore.installedDirectory(
            fileManager: FileManager.default,
            candidateDirectories: [installDirectory]
        )

        #expect(installed == installDirectory)
    }

    @Test("Parakeet vocabulary loader supports array and dictionary JSON formats")
    func vocabularyLoaderSupportsBothKnownFormats() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let arrayURL = tempDirectory.appendingPathComponent("array-vocab.json")
        try Data("[\"<unk>\",\"hello\",\"world\"]".utf8).write(to: arrayURL)
        let arrayVocabulary = try ParakeetVocabulary.load(from: arrayURL)
        #expect(arrayVocabulary[0] == "<unk>")
        #expect(arrayVocabulary[2] == "world")

        let dictionaryURL = tempDirectory.appendingPathComponent("dict-vocab.json")
        try Data("{\"0\":\"<unk>\",\"17\":\"voice\"}".utf8).write(to: dictionaryURL)
        let dictionaryVocabulary = try ParakeetVocabulary.load(from: dictionaryURL)
        #expect(dictionaryVocabulary[0] == "<unk>")
        #expect(dictionaryVocabulary[17] == "voice")
    }
}
