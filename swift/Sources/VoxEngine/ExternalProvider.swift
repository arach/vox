import Foundation
import VoxCore

public actor ExternalProvider: ASRProvider {
    private let log = VoxLog.engine
    private let providerId: String
    private let command: [String]
    private let env: [String: String]?
    private var transport: StdioTransport?

    private var crashCount: Int = 0
    private var lastStableTime: Date = Date()
    private let maxCrashRestarts = 5
    private let stabilityWindow: TimeInterval = 60

    public init(id: String, command: [String], env: [String: String]? = nil) {
        self.providerId = id
        self.command = command
        self.env = env
    }

    public func models() async -> [ASRModelInfo] {
        do {
            let transport = try ensureRunning()
            let result = try await transport.call(method: "models")
            guard let models = result["models"] as? [[String: Any]] else {
                return []
            }
            return models.compactMap { parseModelInfo($0) }
        } catch {
            log.error("Provider \(self.providerId) models() failed: \(error.localizedDescription)")
            return []
        }
    }

    public func install(
        modelId: String,
        progress: @escaping @Sendable (ModelProgress) -> Void
    ) async throws -> ASRModelInfo {
        let transport = try ensureRunning()
        transport.setProgressHandler { params in
            if let modelId = params["modelId"] as? String,
               let prog = params["progress"] as? Double,
               let status = params["status"] as? String {
                progress(ModelProgress(modelId: modelId, progress: prog, status: status))
            }
        }
        defer { transport.clearProgressHandler() }

        let result = try await transport.call(method: "install", params: ["modelId": modelId])
        guard let model = result["model"] as? [String: Any],
              let info = parseModelInfo(model) else {
            throw ExternalProviderError.invalidResponse("install")
        }
        return info
    }

    public func preload(
        modelId: String,
        progress: @escaping @Sendable (ModelProgress) -> Void
    ) async throws -> ASRModelInfo {
        let transport = try ensureRunning()
        transport.setProgressHandler { params in
            if let modelId = params["modelId"] as? String,
               let prog = params["progress"] as? Double,
               let status = params["status"] as? String {
                progress(ModelProgress(modelId: modelId, progress: prog, status: status))
            }
        }
        defer { transport.clearProgressHandler() }

        let result = try await transport.call(method: "preload", params: ["modelId": modelId])
        guard let model = result["model"] as? [String: Any],
              let info = parseModelInfo(model) else {
            throw ExternalProviderError.invalidResponse("preload")
        }
        return info
    }

    public func transcribe(url: URL, modelId: String) async throws -> TranscriptionOutput {
        let transport = try ensureRunning()
        let result = try await transport.call(method: "transcribe", params: [
            "path": url.path,
            "modelId": modelId
        ])

        guard let text = result["text"] as? String else {
            throw ExternalProviderError.invalidResponse("transcribe")
        }

        let responseModelId = (result["modelId"] as? String) ?? modelId
        let elapsedMs = (result["elapsedMs"] as? Int) ?? 0
        let metricsDict = result["metrics"] as? [String: Any]

        let traceId = (metricsDict?["traceId"] as? String)
            ?? String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8)).lowercased()

        let metrics = TranscriptionMetrics(
            traceId: traceId,
            audioDurationMs: (metricsDict?["audioDurationMs"] as? Int) ?? 0,
            inputBytes: (metricsDict?["inputBytes"] as? Int) ?? 0,
            wasPreloaded: (metricsDict?["wasPreloaded"] as? Bool) ?? false,
            fileCheckMs: (metricsDict?["fileCheckMs"] as? Int) ?? 0,
            modelCheckMs: (metricsDict?["modelCheckMs"] as? Int) ?? 0,
            modelLoadMs: (metricsDict?["modelLoadMs"] as? Int) ?? 0,
            audioLoadMs: (metricsDict?["audioLoadMs"] as? Int) ?? 0,
            audioPrepareMs: (metricsDict?["audioPrepareMs"] as? Int) ?? 0,
            inferenceMs: (metricsDict?["inferenceMs"] as? Int) ?? 0,
            totalMs: (metricsDict?["totalMs"] as? Int) ?? elapsedMs
        )

        return TranscriptionOutput(
            modelId: responseModelId,
            text: text,
            elapsedMs: elapsedMs,
            metrics: metrics
        )
    }

    // MARK: - Process Management

    private func ensureRunning() throws -> StdioTransport {
        if let transport, transport.processIsRunning {
            if Date().timeIntervalSince(lastStableTime) > stabilityWindow {
                crashCount = 0
            }
            lastStableTime = Date()
            return transport
        }

        guard crashCount < maxCrashRestarts else {
            let stderr = transport?.lastStderrOutput ?? ""
            throw ExternalProviderError.tooManyCrashes(providerId: providerId, stderr: stderr)
        }

        crashCount += 1
        log.info("Starting provider \(self.providerId) (attempt \(self.crashCount)/\(self.maxCrashRestarts))")

        let newTransport = StdioTransport(command: command, env: env)
        try newTransport.start()
        self.transport = newTransport
        lastStableTime = Date()
        return newTransport
    }

    // MARK: - Parsing

    private func parseModelInfo(_ dict: [String: Any]) -> ASRModelInfo? {
        guard let id = dict["id"] as? String,
              let name = dict["name"] as? String else {
            return nil
        }
        return ASRModelInfo(
            id: id,
            name: name,
            backend: (dict["backend"] as? String) ?? providerId,
            installed: (dict["installed"] as? Bool) ?? true,
            preloaded: (dict["preloaded"] as? Bool) ?? false,
            available: (dict["available"] as? Bool) ?? true
        )
    }
}

public enum ExternalProviderError: Error, LocalizedError {
    case invalidResponse(String)
    case tooManyCrashes(providerId: String, stderr: String)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse(let method):
            return "Invalid response from external provider for \(method)"
        case .tooManyCrashes(let id, let stderr):
            let detail = stderr.isEmpty ? "" : " — \(stderr.suffix(200))"
            return "Provider '\(id)' crashed too many times\(detail)"
        }
    }
}
