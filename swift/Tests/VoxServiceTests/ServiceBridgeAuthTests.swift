import Darwin
import Foundation
import Testing
@testable import VoxService

struct ServiceBridgeAuthTests {
    @Test("ServiceBridge requires auth token when configured")
    func serviceBridgeRequiresAuthToken() async throws {
        let port = try availableLoopbackPort()
        let bridge = ServiceBridge(
            port: port,
            serviceName: "AuthTest",
            bindAddress: "127.0.0.1",
            authToken: "secret-token"
        )
        bridge.handle("ping") { _, reply in
            reply(["ok": true], nil)
        }

        try bridge.start()
        defer { bridge.stop() }

        let rejected = try await callBridge(port: port, method: "ping", params: [:])
        #expect(rejected["error"] as? String == "Unauthorized")

        let accepted = try await callBridge(port: port, method: "ping", params: [
            "authToken": "secret-token"
        ])
        let result = accepted["result"] as? [String: Any]
        #expect(result?["ok"] as? Bool == true)
    }
}

private func callBridge(
    port: UInt16,
    method: String,
    params: [String: Any]
) async throws -> [String: Any] {
    let url = URL(string: "ws://127.0.0.1:\(port)")!
    let socket = URLSession.shared.webSocketTask(with: url)
    socket.resume()
    defer { socket.cancel(with: .normalClosure, reason: nil) }

    let id = UUID().uuidString
    let payload = try JSONSerialization.data(withJSONObject: [
        "id": id,
        "method": method,
        "params": params
    ])
    let text = String(decoding: payload, as: UTF8.self)
    try await socket.send(.string(text))

    let message = try await socket.receive()
    guard case .string(let raw) = message,
          let data = raw.data(using: .utf8),
          let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          decoded["id"] as? String == id else {
        throw NSError(domain: "ServiceBridgeAuthTests", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Bridge returned an invalid response."
        ])
    }
    return decoded
}

private func availableLoopbackPort() throws -> UInt16 {
    let descriptor = socket(AF_INET, SOCK_STREAM, 0)
    guard descriptor >= 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    defer { close(descriptor) }

    var yes: Int32 = 1
    setsockopt(descriptor, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = 0
    address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

    let bindResult = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
            Darwin.bind(descriptor, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
    guard bindResult == 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }

    var resolved = address
    var length = socklen_t(MemoryLayout<sockaddr_in>.size)
    let nameResult = withUnsafeMutablePointer(to: &resolved) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
            getsockname(descriptor, sockaddrPointer, &length)
        }
    }
    guard nameResult == 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }

    return UInt16(bigEndian: resolved.sin_port)
}
