import Foundation

enum HTTPBridgeCodec {
    static let headerDelimiter = Data("\r\n\r\n".utf8)

    static func responseData(status: Int, body: [String: Any], origin: String? = nil) -> Data {
        let statusText = switch status {
        case 200: "OK"
        case 400: "Bad Request"
        case 403: "Forbidden"
        case 404: "Not Found"
        case 413: "Payload Too Large"
        case 500: "Internal Server Error"
        default: "Error"
        }

        let jsonData = (try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])) ?? Data()

        var headers = "HTTP/1.1 \(status) \(statusText)\r\n"
        headers += "Content-Type: application/json\r\n"
        headers += "Content-Length: \(jsonData.count)\r\n"
        headers += "Connection: close\r\n"
        if let origin {
            headers += "Access-Control-Allow-Origin: \(origin)\r\n"
            headers += "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n"
            headers += "Access-Control-Allow-Headers: Content-Type\r\n"
        }
        headers += "\r\n"

        var responseData = headers.data(using: .utf8) ?? Data()
        responseData.append(jsonData)
        return responseData
    }

    static func corsPreflightData(origin: String?) -> Data {
        var headers = "HTTP/1.1 204 No Content\r\n"
        headers += "Connection: close\r\n"
        if let origin {
            headers += "Access-Control-Allow-Origin: \(origin)\r\n"
            headers += "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n"
            headers += "Access-Control-Allow-Headers: Content-Type\r\n"
            headers += "Access-Control-Max-Age: 86400\r\n"
        }
        headers += "\r\n"
        return headers.data(using: .utf8) ?? Data()
    }

    static func parseMultipartFormData(_ body: Data, contentType: String) throws -> MultipartFormData {
        guard let boundary = multipartBoundary(from: contentType) else {
            throw BridgeError.invalidRequest("Missing multipart boundary")
        }

        let separator = Data("\r\n--\(boundary)".utf8)
        var normalized = Data("\r\n".utf8)
        normalized.append(body)

        let segments = split(normalized, by: separator)
        var fields: [String: String] = [:]
        var files: [String: MultipartFile] = [:]

        for rawSegment in segments {
            if rawSegment.isEmpty {
                continue
            }

            var segment = rawSegment
            if segment.starts(with: Data("--".utf8)) {
                break
            }
            if segment.starts(with: Data("\r\n".utf8)) {
                segment.removeFirst(2)
            }
            if segment.isEmpty {
                continue
            }

            guard let headerRange = segment.range(of: headerDelimiter) else {
                throw BridgeError.invalidRequest("Malformed multipart part")
            }

            let partHeaderData = segment.subdata(in: segment.startIndex..<headerRange.lowerBound)
            guard let headerText = String(data: partHeaderData, encoding: .utf8) else {
                throw BridgeError.invalidRequest("Invalid multipart headers")
            }

            let headerLines = headerText.components(separatedBy: "\r\n")
            guard let disposition = headerValue("Content-Disposition", from: headerLines) else {
                throw BridgeError.invalidRequest("Missing multipart disposition")
            }

            let parameters = headerParameters(from: disposition)
            guard let name = parameters["name"], !name.isEmpty else {
                throw BridgeError.invalidRequest("Missing multipart field name")
            }

            let payload = segment.subdata(in: headerRange.upperBound..<segment.endIndex)
            if let filename = parameters["filename"], !filename.isEmpty {
                files[name] = MultipartFile(
                    filename: filename,
                    contentType: headerValue("Content-Type", from: headerLines),
                    data: payload
                )
            } else if let value = String(data: payload, encoding: .utf8) {
                fields[name] = value
            } else {
                throw BridgeError.invalidRequest("Invalid multipart field value")
            }
        }

        return MultipartFormData(fields: fields, files: files)
    }

    private static func multipartBoundary(from contentType: String) -> String? {
        for component in contentType.split(separator: ";") {
            let trimmed = component.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased().hasPrefix("boundary=") {
                var boundary = String(trimmed.dropFirst("boundary=".count))
                if boundary.hasPrefix("\""), boundary.hasSuffix("\""), boundary.count >= 2 {
                    boundary.removeFirst()
                    boundary.removeLast()
                }
                return boundary
            }
        }
        return nil
    }

    private static func split(_ data: Data, by separator: Data) -> [Data] {
        guard !separator.isEmpty else { return [data] }

        var parts: [Data] = []
        var searchStart = data.startIndex

        while let range = data.range(of: separator, options: [], in: searchStart..<data.endIndex) {
            parts.append(data.subdata(in: searchStart..<range.lowerBound))
            searchStart = range.upperBound
        }

        parts.append(data.subdata(in: searchStart..<data.endIndex))
        return parts
    }

    private static func headerParameters(from value: String) -> [String: String] {
        var parameters: [String: String] = [:]

        for component in value.split(separator: ";") {
            let trimmed = component.trimmingCharacters(in: .whitespaces)
            guard let equalsIndex = trimmed.firstIndex(of: "=") else { continue }
            let key = String(trimmed[..<equalsIndex]).lowercased()
            var parameterValue = String(trimmed[trimmed.index(after: equalsIndex)...])
            if parameterValue.hasPrefix("\""), parameterValue.hasSuffix("\""), parameterValue.count >= 2 {
                parameterValue.removeFirst()
                parameterValue.removeLast()
            }
            parameters[key] = parameterValue
        }

        return parameters
    }

    private static func headerValue(_ name: String, from lines: [String]) -> String? {
        let prefix = name.lowercased() + ":"
        for line in lines {
            if line.lowercased().hasPrefix(prefix) {
                return line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }
}
