import Foundation
import Darwin

struct QwenFallbackAvailability: Sendable, Equatable {
    enum State: String, Sendable, Equatable {
        case unavailable
        case cold
        case warming
        case ready
    }

    let state: State
    let isAvailable: Bool
    let message: String
}

struct QwenFallbackReply: Sendable, Equatable {
    let text: String
    let elapsedMs: Int
}

actor QwenFallbackService {
    static let shared = QwenFallbackService()

    static let modelId = "Qwen/Qwen3-0.6B-MLX-4bit"
    static let displayName = "Qwen3 0.6B"

    private static let host = "127.0.0.1"
    private static let preferredPort = 8197
    private static let systemPrompt = """
    You are a warm, concise on-device voice assistant inside a minimal macOS demo.
    The demo records a short voice turn, transcribes it locally with Vox, generates a reply on device, and speaks the answer back out loud.
    Reply in one or two short sentences.
    Keep it helpful, conversational, and natural.
    Do not use markdown or bullet points.
    """

    private let session: URLSession
    private let port: Int
    private var serverProcess: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var lastStartupFailure: String?

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 180
        configuration.timeoutIntervalForResource = 600
        session = URLSession(configuration: configuration)
        port = Self.allocatePort(preferred: Self.preferredPort)
    }

    deinit {
        serverProcess?.terminate()
    }

    func availability() async -> QwenFallbackAvailability {
        guard canUseUV() else {
            return QwenFallbackAvailability(
                state: .unavailable,
                isAvailable: false,
                message: "Install uv to enable the local Qwen fallback."
            )
        }

        if await isServerReady() {
            lastStartupFailure = nil
            return QwenFallbackAvailability(
                state: .ready,
                isAvailable: true,
                message: "\(Self.displayName) ready."
            )
        }

        if let serverProcess, serverProcess.isRunning {
            return QwenFallbackAvailability(
                state: .warming,
                isAvailable: true,
                message: "\(Self.displayName) is warming up in the background."
            )
        }

        if let lastStartupFailure, !lastStartupFailure.isEmpty {
            return QwenFallbackAvailability(
                state: .cold,
                isAvailable: true,
                message: "\(Self.displayName) can retry. Last startup failed: \(lastStartupFailure)"
            )
        }

        return QwenFallbackAvailability(
            state: .cold,
            isAvailable: true,
            message: "\(Self.displayName) is available as the local fallback."
        )
    }

    func warmupIfNeeded() async throws -> QwenFallbackAvailability {
        try await ensureServerRunning()
        return await availability()
    }

    func generateReply(for transcript: String) async throws -> QwenFallbackReply {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw QwenFallbackError.emptyInput
        }

        try await ensureServerRunning()

        let startedAt = Date()
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/chat/completions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(ChatCompletionRequest(
            model: Self.modelId,
            messages: [
                ChatMessage(role: "system", content: Self.systemPrompt),
                ChatMessage(role: "user", content: trimmed),
            ],
            temperature: 0.7,
            maxTokens: 120,
            stream: false
        ))

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw QwenFallbackError.invalidResponse("Missing HTTP response.")
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw QwenFallbackError.serverFailure(body)
        }

        let completion = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        let text = normalize(completion.choices.first?.message.content ?? "")
        guard !text.isEmpty else {
            throw QwenFallbackError.emptyOutput
        }

        return QwenFallbackReply(
            text: text,
            elapsedMs: Int(Date().timeIntervalSince(startedAt) * 1000)
        )
    }

    private func ensureServerRunning() async throws {
        var attempts = 0
        var lastError: Error?

        while attempts < 2 {
            attempts += 1
            do {
                try await ensureServerRunningOnce()
                lastStartupFailure = nil
                return
            } catch {
                lastError = error
                lastStartupFailure = error.localizedDescription
                clearStoppedProcess()
            }
        }

        throw lastError ?? QwenFallbackError.startupTimedOut
    }

    private func ensureServerRunningOnce() async throws {
        if await isServerReady() {
            return
        }

        clearStoppedProcess()

        if let serverProcess, serverProcess.isRunning {
            try await waitUntilReady()
            return
        }

        try startServer()
        try await waitUntilReady()
    }

    private func startServer() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "uv",
            "run",
            "--with", "mlx-lm",
            "mlx_lm.server",
            "--model", Self.modelId,
            "--host", Self.host,
            "--port", String(port),
            "--chat-template-args", #"{"enable_thinking":false}"#,
            "--temp", "0.7",
            "--top-p", "0.8",
            "--top-k", "20",
            "--max-tokens", "120",
            "--log-level", "ERROR",
        ]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        drain(stdoutPipe)
        drain(stderrPipe)

        try process.run()
        serverProcess = process
        self.stdoutPipe = stdoutPipe
        self.stderrPipe = stderrPipe
    }

    private func waitUntilReady() async throws {
        for _ in 0..<240 {
            if await isServerReady() {
                lastStartupFailure = nil
                return
            }

            if let serverProcess, !serverProcess.isRunning {
                throw QwenFallbackError.serverExited
            }

            try await Task.sleep(for: .seconds(1))
        }

        throw QwenFallbackError.startupTimedOut
    }

    private func isServerReady() async -> Bool {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/models"))
        request.timeoutInterval = 2

        do {
            let (_, response) = try await session.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    private func canUseUV() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["uv", "--version"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func drain(_ pipe: Pipe) {
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
            }
        }
    }

    private func clearStoppedProcess() {
        guard let serverProcess, !serverProcess.isRunning else { return }
        self.serverProcess = nil
        stdoutPipe = nil
        stderrPipe = nil
    }

    private var baseURL: URL {
        URL(string: "http://\(Self.host):\(port)")!
    }

    private static func allocatePort(preferred: Int) -> Int {
        if canBind(port: preferred) {
            return preferred
        }

        for candidate in (preferred + 1)...(preferred + 40) {
            if canBind(port: candidate) {
                return candidate
            }
        }

        return preferred
    }

    private static func canBind(port: Int) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        var reuse: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(UInt16(port).bigEndian)
        address.sin_addr = in_addr(s_addr: inet_addr(Self.host))

        return withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                bind(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
    }

    private func normalize(_ text: String) -> String {
        let withoutThinking = text.replacingOccurrences(
            of: "<think>[\\s\\S]*?</think>",
            with: "",
            options: .regularExpression
        )
        let collapsed = withoutThinking.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )
        let trimmed = collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(240))
    }
}

private struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let temperature: Double
    let maxTokens: Int
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case maxTokens = "max_tokens"
        case stream
    }
}

private struct ChatMessage: Codable {
    let role: String
    let content: String
}

private struct ChatCompletionResponse: Decodable {
    let choices: [ChatChoice]
}

private struct ChatChoice: Decodable {
    let message: ChatMessage
}

enum QwenFallbackError: LocalizedError {
    case emptyInput
    case emptyOutput
    case invalidResponse(String)
    case serverFailure(String)
    case serverExited
    case startupTimedOut

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "Record a short turn first."
        case .emptyOutput:
            return "Qwen returned an empty reply."
        case .invalidResponse(let message):
            return message
        case .serverFailure(let message):
            return "Qwen fallback failed: \(message)"
        case .serverExited:
            return "The local Qwen fallback stopped before it became ready."
        case .startupTimedOut:
            return "Timed out while starting the local Qwen fallback."
        }
    }
}
