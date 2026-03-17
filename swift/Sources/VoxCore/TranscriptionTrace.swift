import Foundation
import os.signpost

public struct TranscriptionTraceStep: Sendable, Equatable {
    public let name: String
    public let startMs: Int
    public let durationMs: Int
    public let metadata: String?
}

public final class TranscriptionTrace: @unchecked Sendable {
    public let traceId: String

    private static let signpostLog = OSLog(subsystem: "dev.vox.performance", category: "Transcription")
    private let startNs: UInt64
    private var steps: [TranscriptionTraceStep] = []
    private var currentStepName: String?
    private var currentStepStartNs: UInt64 = 0
    private var currentSignpostID: OSSignpostID?

    public init(traceId: String? = nil) {
        self.traceId = traceId ?? String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8)).lowercased()
        self.startNs = DispatchTime.now().uptimeNanoseconds
    }

    deinit {
        if let signpostID = currentSignpostID, let currentStepName {
            os_signpost(.end, log: Self.signpostLog, name: "vox.transcription.step", signpostID: signpostID,
                        "%{public}s (abandoned)", currentStepName)
        }
    }

    public func begin(_ name: String) {
        if currentStepName != nil {
            _ = end("auto-closed")
        }

        currentStepName = name
        currentStepStartNs = DispatchTime.now().uptimeNanoseconds

        let signpostID = OSSignpostID(log: Self.signpostLog)
        currentSignpostID = signpostID
        os_signpost(.begin, log: Self.signpostLog, name: "vox.transcription.step", signpostID: signpostID,
                    "trace=%{public}s step=%{public}s", traceId, name)
    }

    @discardableResult
    public func end(_ metadata: String? = nil) -> Int {
        guard let currentStepName, currentStepStartNs > 0 else { return 0 }

        let now = DispatchTime.now().uptimeNanoseconds
        let durationMs = Self.nsToMs(now - currentStepStartNs)
        let startMs = Self.nsToMs(currentStepStartNs - startNs)
        steps.append(TranscriptionTraceStep(
            name: currentStepName,
            startMs: startMs,
            durationMs: durationMs,
            metadata: metadata
        ))

        if let signpostID = currentSignpostID {
            if let metadata {
                os_signpost(.end, log: Self.signpostLog, name: "vox.transcription.step", signpostID: signpostID,
                            "%{public}s: %{public}s (%dms)", currentStepName, metadata, durationMs)
            } else {
                os_signpost(.end, log: Self.signpostLog, name: "vox.transcription.step", signpostID: signpostID,
                            "%{public}s (%dms)", currentStepName, durationMs)
            }
            currentSignpostID = nil
        }

        self.currentStepName = nil
        self.currentStepStartNs = 0
        return durationMs
    }

    public func durationMs(for name: String) -> Int {
        steps.first(where: { $0.name == name })?.durationMs ?? 0
    }

    public var elapsedMs: Int {
        Self.nsToMs(DispatchTime.now().uptimeNanoseconds - startNs)
    }

    public var summary: String {
        let parts = steps.map { step in
            if let metadata = step.metadata, !metadata.isEmpty {
                return "\(step.name)=\(step.durationMs)ms(\(metadata))"
            }
            return "\(step.name)=\(step.durationMs)ms"
        }
        return "[\(traceId)] \(elapsedMs)ms total: \(parts.joined(separator: ", "))"
    }

    private static func nsToMs(_ ns: UInt64) -> Int {
        Int(ns / 1_000_000)
    }
}
