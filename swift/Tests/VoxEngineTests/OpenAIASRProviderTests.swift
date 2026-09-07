import Foundation
import Testing
import VoxCore
@testable import HudsonSpeechEngine

struct OpenAIASRProviderTests {
    @Test("OpenAI ASR builds a multipart transcription body")
    func multipartBodyContainsModelAndFile() {
        let body = OpenAIASRProvider.multipartBody(
            boundary: "test-boundary",
            modelId: "gpt-transcribe",
            fileName: "clip.wav",
            fileData: Data("RIFF".utf8)
        )
        let text = String(decoding: body, as: UTF8.self)
        #expect(text.contains("name=\"model\""))
        #expect(text.contains("gpt-transcribe"))
        #expect(text.contains("filename=\"clip.wav\""))
        #expect(text.contains("RIFF"))
    }

    @Test("OpenAI ASR transcribes through the audio transcriptions route")
    func transcribesUsingCatalogModelId() async throws {
        MockURLProtocol.handler = { request in
            #expect(request.url?.lastPathComponent == "transcriptions")
            #expect(request.httpMethod == "POST")
            let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
            #expect(body.contains("gpt-transcribe"))
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(#"{"text":"hello from openai"}"#.utf8))
        }
        defer { MockURLProtocol.handler = nil }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let catalog = SpeechModelCatalog(
            version: 1,
            updatedAt: "2026-08-29",
            models: [
                SpeechModelCatalogEntry(
                    id: "gpt-transcribe",
                    family: SpeechModelFamily.openaiTranscribe,
                    name: "GPT Transcribe"
                )
            ]
        )
        let store = ModelCatalogStore(
            bundledCatalog: catalog,
            cachedCatalog: catalog,
            transport: StaticCatalogTransport(data: Data()),
            cacheURL: FileManager.default.temporaryDirectory.appendingPathComponent("unused-openai.json")
        )
        let provider = OpenAIASRProvider(
            env: ["OPENAI_API_KEY": "sk-test"],
            session: session,
            catalogStore: store
        )

        let audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).wav")
        try Data("RIFF".utf8).write(to: audioURL)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let output = try await provider.transcribe(url: audioURL, modelId: "gpt-transcribe")
        #expect(output.modelId == "gpt-transcribe")
        #expect(output.text == "hello from openai")
    }
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "test", code: 1))
            return
        }
        do {
            var request = self.request
            if request.httpBody == nil, let stream = request.httpBodyStream {
                request.httpBody = Data(reading: stream)
            }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private struct StaticCatalogTransport: CatalogTransport {
    let data: Data

    func fetch(from url: URL) async throws -> Data {
        _ = url
        return data
    }
}

private extension Data {
    init(reading stream: InputStream) {
        self.init()
        stream.open()
        defer { stream.close() }
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read > 0 {
                append(buffer, count: read)
            } else {
                break
            }
        }
    }
}
