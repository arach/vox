import Foundation
import Testing
@testable import VoxBridge

struct HTTPBridgeCodecTests {
    @Test("/transcribe multipart parsing preserves fields and file uploads")
    func multipartTranscribePayloadIsParsed() throws {
        let boundary = "hudson-voice"
        let audioBytes = Data([0x4F, 0x67, 0x67, 0x53, 0x01, 0x02, 0x03])
        var body = Data()

        func append(_ string: String) {
            body.append(Data(string.utf8))
        }

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"format\"\r\n\r\n")
        append("opus\r\n")
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"metadata\"\r\n\r\n")
        append("{\"surface\":\"hudson-ai\",\"workspaceId\":\"hudson-os\"}\r\n")
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"audio\"; filename=\"voice.ogg\"\r\n")
        append("Content-Type: audio/ogg;codecs=opus\r\n\r\n")
        body.append(audioBytes)
        append("\r\n")
        append("--\(boundary)--\r\n")

        let formData = try HTTPBridgeCodec.parseMultipartFormData(
            body,
            contentType: "multipart/form-data; boundary=\(boundary)"
        )

        #expect(formData.fields["format"] == "opus")
        #expect(formData.fields["metadata"] == "{\"surface\":\"hudson-ai\",\"workspaceId\":\"hudson-os\"}")
        #expect(formData.files["audio"]?.filename == "voice.ogg")
        #expect(formData.files["audio"]?.contentType == "audio/ogg;codecs=opus")
        #expect(formData.files["audio"]?.data == audioBytes)
    }

    @Test("JSON responses keep CORS headers on error responses")
    func errorResponsesIncludeOriginHeaders() throws {
        let data = HTTPBridgeCodec.responseData(
            status: 403,
            body: ["error": "Origin not allowed"],
            origin: "http://localhost:3500"
        )
        let response = try #require(String(data: data, encoding: .utf8))

        #expect(response.contains("HTTP/1.1 403 Forbidden"))
        #expect(response.contains("Access-Control-Allow-Origin: http://localhost:3500"))
        #expect(response.contains("Access-Control-Allow-Methods: GET, POST, OPTIONS"))
        #expect(response.contains("Access-Control-Allow-Headers: Content-Type"))
        #expect(response.contains("{\"error\":\"Origin not allowed\"}"))
    }

    @Test("CORS preflight advertises the bridge methods and headers")
    func corsPreflightIncludesExpectedHeaders() throws {
        let data = HTTPBridgeCodec.corsPreflightData(origin: "http://localhost:3500")
        let response = try #require(String(data: data, encoding: .utf8))

        #expect(response.contains("HTTP/1.1 204 No Content"))
        #expect(response.contains("Access-Control-Allow-Origin: http://localhost:3500"))
        #expect(response.contains("Access-Control-Allow-Methods: GET, POST, OPTIONS"))
        #expect(response.contains("Access-Control-Allow-Headers: Content-Type"))
        #expect(response.contains("Access-Control-Max-Age: 86400"))
    }

    @Test("Streaming responses advertise chunked NDJSON with CORS headers")
    func streamingResponsesIncludeExpectedHeaders() throws {
        let data = HTTPBridgeCodec.streamingResponseHead(origin: "http://localhost:3500")
        let response = try #require(String(data: data, encoding: .utf8))

        #expect(response.contains("HTTP/1.1 200 OK"))
        #expect(response.contains("Content-Type: application/x-ndjson"))
        #expect(response.contains("Transfer-Encoding: chunked"))
        #expect(response.contains("Cache-Control: no-cache"))
        #expect(response.contains("Access-Control-Allow-Origin: http://localhost:3500"))
    }

    @Test("Streaming chunks encode a newline-delimited JSON payload")
    func streamingChunksEncodeNDJSONPayload() throws {
        let data = HTTPBridgeCodec.streamingChunkData(body: [
            "event": "session.state",
            "data": [
                "sessionId": "session-1",
                "state": "recording"
            ]
        ])
        let chunk = try #require(String(data: data, encoding: .utf8))

        #expect(chunk.contains("\r\n{\"data\":"))
        #expect(chunk.contains("\"event\":\"session.state\""))
        #expect(chunk.contains("\"sessionId\":\"session-1\""))
        #expect(chunk.hasSuffix("\n\r\n"))
    }
}
