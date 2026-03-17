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
        return 42137
    }

    return UInt16(arguments[index + 1]) ?? 42137
}

func loadEngine() -> EngineManager {
    let configURL = RuntimePaths.providersConfigURL()
    guard FileManager.default.fileExists(atPath: configURL.path) else {
        log.info("No providers.json found, using default ParakeetProvider")
        return EngineManager()
    }

    do {
        let config = try ProvidersConfig.load(from: configURL)
        log.info("Loaded \(config.providers.count) provider(s) from providers.json")
        let registry = ProviderRegistry(config: config)
        return EngineManager(provider: registry)
    } catch {
        log.error("Failed to parse providers.json: \(error.localizedDescription) — falling back to default")
        return EngineManager()
    }
}

let port = parsePort()
let engine = loadEngine()
let service = VoxRuntimeService(port: port, engine: engine)

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
