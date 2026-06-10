import Foundation

struct HTTPRequest: Sendable {
    let method: String
    let path: String
    let query: [String: String]
    let headers: [String: String]
    let body: Data

    static func headerEndRange(in data: Data) -> Range<Data.Index>? {
        data.range(of: Data("\r\n\r\n".utf8))
    }

    static func contentLength(fromHeaderData data: Data) -> Int {
        guard let text = String(data: data, encoding: .utf8) else { return 0 }
        for line in text.split(separator: "\r\n").dropFirst() {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length" {
                return Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0
            }
        }
        return 0
    }

    static func parse(_ data: Data) -> HTTPRequest? {
        guard let headerEnd = headerEndRange(in: data) else { return nil }
        let headerData = data[data.startIndex..<headerEnd.lowerBound]
        guard let headerText = String(data: headerData, encoding: .utf8) else { return nil }

        let lines = headerText.split(separator: "\r\n", omittingEmptySubsequences: false)
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        let method = String(parts[0]).uppercased()
        let target = String(parts[1])

        var path = target
        var query: [String: String] = [:]
        if let questionMark = target.firstIndex(of: "?") {
            path = String(target[target.startIndex..<questionMark])
            let queryString = String(target[target.index(after: questionMark)...])
            for pair in queryString.split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1)
                guard let key = String(kv[0]).removingPercentEncoding else { continue }
                let value = kv.count == 2 ? (String(kv[1]).removingPercentEncoding ?? "") : ""
                query[key] = value
            }
        }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            let kv = line.split(separator: ":", maxSplits: 1)
            guard kv.count == 2 else { continue }
            headers[kv[0].trimmingCharacters(in: .whitespaces).lowercased()] =
                kv[1].trimmingCharacters(in: .whitespaces)
        }

        let body = Data(data[headerEnd.upperBound...])
        return HTTPRequest(method: method, path: path, query: query, headers: headers, body: body)
    }
}

struct HTTPResponse: Sendable {
    let status: Int
    let body: Data
    var contentType = "application/json"

    static func json(_ status: Int, _ object: some Encodable) -> HTTPResponse {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let body = (try? encoder.encode(object)) ?? Data("{}".utf8)
        return HTTPResponse(status: status, body: body)
    }

    static func error(_ status: Int, _ message: String) -> HTTPResponse {
        .json(status, ["error": message])
    }

    var statusText: String {
        switch status {
        case 200: return "OK"
        case 202: return "Accepted"
        case 401: return "Unauthorized"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        default: return "Internal Server Error"
        }
    }

    func serialize() -> Data {
        var head = "HTTP/1.1 \(status) \(statusText)\r\n"
        head += "Content-Type: \(contentType)\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Connection: close\r\n\r\n"
        return Data(head.utf8) + body
    }
}
