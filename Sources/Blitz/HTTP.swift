import Foundation
import CryptoKit

// MARK: - Small helpers

enum Util {
    static func random(_ n: Int) -> String {
        let chars = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return String((0..<n).map { _ in chars.randomElement()! })
    }

    /// TikTok wants the PKCE challenge as HEX of SHA-256 (not base64url like most providers).
    static func sha256Hex(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func url(_ base: String, _ query: [String: String]) -> URL {
        var c = URLComponents(string: base)!
        c.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        return c.url!
    }
}

private let formAllowed: CharacterSet = {
    var s = CharacterSet.alphanumerics
    s.insert(charactersIn: "-._~")
    return s
}()

extension String {
    var formEncoded: String { addingPercentEncoding(withAllowedCharacters: formAllowed) ?? self }
}

// MARK: - HTTP
enum HTTP {
    static func request(_ url: URL,
                        method: String = "GET",
                        headers: [String: String] = [:],
                        form: [String: String]? = nil,
                        json: [String: Any]? = nil) async throws -> [String: Any] {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 60
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        if let form {
            req.httpBody = form.map { "\($0.key.formEncoded)=\($0.value.formEncoded)" }
                .joined(separator: "&").data(using: .utf8)
            req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        }
        if let json {
            req.httpBody = try JSONSerialization.data(withJSONObject: json)
            req.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        return try parse(data, resp)
    }

    /// Streams a file from disk as the request body and reports progress 0...1.
    static func upload(_ url: URL,
                       method: String = "POST",
                       headers: [String: String],
                       file: URL,
                       progress: @escaping (Double) -> Void) async throws -> [String: Any] {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 3600
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        let (data, resp) = try await URLSession.shared.upload(for: req, fromFile: file,
                                                              delegate: ProgressDelegate(progress))
        return try parse(data, resp)
    }

    static func parse(_ data: Data, _ resp: URLResponse) throws -> [String: Any] {
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (200..<300).contains(status) else {
            var msg = String(data: data, encoding: .utf8) ?? "no response body"
            if let e = obj["error"] as? [String: Any], let m = e["message"] as? String { msg = m }
            throw APIError("HTTP \(status): \(msg.prefix(400))")
        }
        return obj
    }
}

final class ProgressDelegate: NSObject, URLSessionTaskDelegate {
    private let onProgress: (Double) -> Void
    init(_ onProgress: @escaping (Double) -> Void) { self.onProgress = onProgress }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didSendBodyData bytesSent: Int64, totalBytesSent: Int64,
                    totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0 else { return }
        onProgress(Double(totalBytesSent) / Double(totalBytesExpectedToSend))
    }
}
