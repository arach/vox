@preconcurrency import CoreML
import Foundation
#if canImport(FluidAudio)
import FluidAudio
#endif

struct ParakeetModelURLs: Sendable {
    let preprocessor: URL
    let encoder: URL
    let decoder: URL
    let joint: URL
    let vocabulary: URL
}

struct ParakeetLoadedModels: Sendable {
    let preprocessor: MLModel
    let encoder: MLModel
    let decoder: MLModel
    let joint: MLModel
    let configuration: MLModelConfiguration
    let vocabulary: [Int: String]
}

struct ParakeetModelLoader: Sendable {
    let manifest: ParakeetModelManifest

    init(manifest: ParakeetModelManifest = .v3) {
        self.manifest = manifest
    }

    func modelURLs(in directory: URL) -> ParakeetModelURLs {
        ParakeetModelURLs(
            preprocessor: directory.appendingPathComponent("Preprocessor.mlmodelc", isDirectory: true),
            encoder: directory.appendingPathComponent("Encoder.mlmodelc", isDirectory: true),
            decoder: directory.appendingPathComponent("Decoder.mlmodelc", isDirectory: true),
            joint: directory.appendingPathComponent("JointDecisionv3.mlmodelc", isDirectory: true),
            vocabulary: directory.appendingPathComponent(manifest.vocabularyFile)
        )
    }

    func loadModels(from directory: URL) throws -> ParakeetLoadedModels {
        let urls = modelURLs(in: directory)
        let preprocessor = try MLModel(
            contentsOf: urls.preprocessor,
            configuration: modelConfiguration(computeUnits: .cpuOnly)
        )
        let encoder = try MLModel(
            contentsOf: urls.encoder,
            configuration: modelConfiguration(computeUnits: .cpuAndNeuralEngine)
        )
        let decoder = try MLModel(
            contentsOf: urls.decoder,
            configuration: modelConfiguration(computeUnits: .cpuAndNeuralEngine)
        )
        let joint = try MLModel(
            contentsOf: urls.joint,
            configuration: modelConfiguration(computeUnits: .cpuAndNeuralEngine)
        )
        let vocabulary = try ParakeetVocabulary.load(from: urls.vocabulary)
        let configuration = modelConfiguration(computeUnits: .cpuAndNeuralEngine)

        return ParakeetLoadedModels(
            preprocessor: preprocessor,
            encoder: encoder,
            decoder: decoder,
            joint: joint,
            configuration: configuration,
            vocabulary: vocabulary
        )
    }

    private func modelConfiguration(computeUnits: MLComputeUnits) -> MLModelConfiguration {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = computeUnits
        configuration.allowLowPrecisionAccumulationOnGPU = true
        return configuration
    }
}

#if canImport(FluidAudio)
extension ParakeetLoadedModels {
    func asrModels(version: AsrModelVersion = .v3) -> AsrModels {
        AsrModels(
            encoder: encoder,
            preprocessor: preprocessor,
            decoder: decoder,
            joint: joint,
            configuration: configuration,
            vocabulary: vocabulary,
            version: version
        )
    }
}
#endif
