import Foundation
import Testing
import VoxCore

struct SpeechHistoryRecorderTests {
    @Test("Speech history recorder appends, filters, gets, and deletes records")
    func recorderRoundTrip() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("vox-history-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let recorder = SpeechHistoryRecorder(fileURL: directory.appendingPathComponent("history.jsonl"))
        let metrics = TranscriptionMetrics(
            traceId: "trace-history",
            audioDurationMs: 1200,
            inputBytes: 4096,
            wasPreloaded: true,
            fileCheckMs: 1,
            modelCheckMs: 2,
            modelLoadMs: 0,
            audioLoadMs: 3,
            audioPrepareMs: 4,
            inferenceMs: 80,
            totalMs: 90
        )
        let output = TranscriptionOutput(
            modelId: "parakeet:v3",
            text: "hello history",
            elapsedMs: 90,
            metrics: metrics,
            words: [WordTiming(word: "hello", start: 0, end: 0.4, confidence: 0.98)]
        )
        let record = SpeechHistoryRecord.transcription(
            source: .file,
            route: "transcribe.file",
            clientId: "test-client",
            modelId: output.modelId,
            output: output,
            completedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )

        try await recorder.append(record)

        let listed = try await recorder.list(filter: SpeechHistoryListFilter(clientId: "test-client"))
        #expect(listed.count == 1)
        #expect(listed[0].id == record.id)
        #expect(listed[0].text == "hello history")
        #expect(listed[0].words?.first?.word == "hello")
        #expect(listed[0].metrics?.traceId == "trace-history")

        let fetched = try await recorder.get(id: record.id)
        #expect(fetched?.route == "transcribe.file")
        #expect(fetched?.source == .file)

        let deleted = try await recorder.delete(id: record.id)
        #expect(deleted)
        #expect(try await recorder.list().isEmpty)
    }
}
