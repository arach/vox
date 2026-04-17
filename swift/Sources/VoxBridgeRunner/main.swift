import Dispatch
import Foundation
import VoxBridge

#if canImport(Darwin)
import Darwin
#endif

func parsePort() -> UInt16 {
    let arguments = CommandLine.arguments
    guard let index = arguments.firstIndex(of: "--port"), arguments.indices.contains(index + 1) else {
        return HTTPBridgeServer.defaultPort
    }

    return UInt16(arguments[index + 1]) ?? HTTPBridgeServer.defaultPort
}

let port = parsePort()
let proxy = DaemonProxy()
let allowlist = OriginAllowlist()
let bridge = HTTPBridgeServer(port: port, proxy: proxy, allowlist: allowlist)

bridge.start()
Task {
    try? await proxy.connect()
}

let signals: [Int32] = [SIGTERM, SIGINT]
var sources: [DispatchSourceSignal] = []
for signalNumber in signals {
    signal(signalNumber, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
    source.setEventHandler {
        bridge.stop()
        Task {
            await proxy.disconnect()
            exit(0)
        }
    }
    source.resume()
    sources.append(source)
}

RunLoop.main.run()
