import Dispatch
import Foundation
import VoxCore
import VoxEngine
import VoxService

#if canImport(Darwin)
import Darwin
#endif

let log = VoxLog.daemon

func parsePort() -> UInt16 {
    let arguments = CommandLine.arguments
    guard let index = arguments.firstIndex(of: "--port"), arguments.indices.contains(index + 1) else {
        return VoxDefaults.resolvedDaemonPort()
    }

    return UInt16(arguments[index + 1]) ?? VoxDefaults.resolvedDaemonPort()
}

func defaultASRConfig() -> ProvidersConfig {
    return ProvidersConfig(providers: [
        ProviderEntry(
            id: "parakeet",
            kind: .asr,
            builtin: true,
            models: ["parakeet:v3"]
        )
    ])
}

func defaultTTSConfig() -> ProvidersConfig {
    if let command = bundledTTSCommand() {
        return ProvidersConfig(providers: [
            ProviderEntry(
                id: "voxttsd",
                kind: .tts,
                command: command,
                models: [AVSpeechSynthesizerProvider.modelID] + OpenAITTSProvider.supportedModelIDs
            )
        ])
    }

    log.warning("voxttsd not found next to voxd; using in-process TTS providers")
    return ProvidersConfig(providers: [
        ProviderEntry(
            id: "avspeech",
            kind: .tts,
            builtin: true,
            models: [AVSpeechSynthesizerProvider.modelID]
        ),
        ProviderEntry(
            id: "openai-tts",
            kind: .tts,
            builtin: true,
            models: OpenAITTSProvider.supportedModelIDs
        )
    ])
}

func bundledTTSCommand() -> [String]? {
    let executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
    let executableName = "voxttsd"
    let siblingURL = executableURL.deletingLastPathComponent().appendingPathComponent(executableName)
    if FileManager.default.isExecutableFile(atPath: siblingURL.path) {
        return [siblingURL.path]
    }

    guard let resolvedPath = Bundle.main.path(forResource: executableName, ofType: nil),
          FileManager.default.isExecutableFile(atPath: resolvedPath) else {
        return nil
    }
    return [resolvedPath]
}

func loadEngines() -> (EngineManager, TTSEngineManager) {
    let configURL = RuntimePaths.providersConfigURL()
    guard FileManager.default.fileExists(atPath: configURL.path) else {
        log.info("No providers.json found, using default Vox ASR and TTS providers")
        return (
            EngineManager(provider: ProviderRegistry(config: defaultASRConfig())),
            TTSEngineManager(provider: TTSProviderRegistry(config: defaultTTSConfig()))
        )
    }

    do {
        let config = try ProvidersConfig.load(from: configURL)
        log.info("Loaded \(config.providers.count) provider(s) from providers.json")
        let asrConfig = config.providers.contains(where: { $0.resolvedKind == .asr })
            ? config
            : defaultASRConfig()
        let ttsConfig = config.providers.contains(where: { $0.resolvedKind == .tts })
            ? config
            : defaultTTSConfig()

        return (
            EngineManager(provider: ProviderRegistry(config: asrConfig)),
            TTSEngineManager(provider: TTSProviderRegistry(config: ttsConfig))
        )
    } catch {
        log.error("Failed to parse providers.json: \(error.localizedDescription) — falling back to default")
        return (
            EngineManager(provider: ProviderRegistry(config: defaultASRConfig())),
            TTSEngineManager(provider: TTSProviderRegistry(config: defaultTTSConfig()))
        )
    }
}

let port = parsePort()
let host = VoxDefaults.resolvedHost()
let (engine, ttsEngine) = loadEngines()
let service = VoxRuntimeService(port: port, bindAddress: host, engine: engine, ttsEngine: ttsEngine)

do {
    try service.start()
} catch {
    fputs("Failed to start Vox daemon: \(error.localizedDescription)\n", stderr)
    exit(1)
}

let signals: [Int32] = [SIGTERM, SIGINT]
var sources: [DispatchSourceSignal] = []
for signalNumber in signals {
    signal(signalNumber, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
    source.setEventHandler {
        service.stop()
        exit(0)
    }
    source.resume()
    sources.append(source)
}

RunLoop.main.run()
