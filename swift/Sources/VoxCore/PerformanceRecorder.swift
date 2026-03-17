import Foundation

public actor PerformanceRecorder {
    private let encoder: JSONEncoder

    public init() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
    }

    public func record(_ sample: PerformanceSample) async {
        do {
            try RuntimePaths.ensureDirectories()
            let url = RuntimePaths.performanceLogURL()
            let data = try encoder.encode(sample) + Data([0x0a])

            if FileManager.default.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } else {
                try data.write(to: url, options: .atomic)
            }
        } catch {
            VoxLog.core.error("Failed to write performance sample: \(error.localizedDescription, privacy: .public)")
        }
    }
}
