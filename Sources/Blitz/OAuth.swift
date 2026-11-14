import Foundation
import Network

// MARK: - OAuth via a tiny localhost server (no URL scheme / Info.plist needed)

/// Opens `url` for the user, returns the authorization code. `String` is the expected `state`.
typealias Authorizer = (URL, String) async throws -> String

enum OAuthError: LocalizedError {
    case timeout, cancelled, denied(String), stateMismatch
    var errorDescription: String? {
        switch self {
        case .timeout: return "Login timed out. Try connecting again."
        case .cancelled: return "Login cancelled."
        case .denied(let why): return "Login was denied: \(why)"
        case .stateMismatch: return "Login response didn't match the request (state mismatch)."
        }
    }
}

final class OAuthLoopback: @unchecked Sendable {
    static let port: UInt16 = 8765
    static var redirectURI: String { "http://localhost:\(port)/callback" }

    /// How the login page is shown. Mac: the default browser. iPhone: an in-app browser sheet (set at launch).
    static var opener: (URL, OAuthLoopback) -> Void = { url, _ in Native.open(url) }
    /// Called when a login finishes, so the iPhone can close its in-app browser sheet.
    static var closer: () -> Void = {}

    private let expectedState: String
    private let queue = DispatchQueue(label: "oauth.loopback")
    private var listener: NWListener?
    private var continuation: CheckedContinuation<String, Error>?

    init(expectedState: String) { self.expectedState = expectedState }

    /// Starts the listener, opens `url` in the default browser, returns the authorization code.
    /// Finishes when the browser hits localhost, OR `complete(pasted:)` / `cancel()` is called.
    func run(open url: URL) async throws -> String {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            queue.async { [self] in
                continuation = cont
                startListener(open: url)
            }
        }
    }

    func cancel() {
        queue.async { [self] in finish(.failure(OAuthError.cancelled)) }
    }

    /// Manual fallback: the user pastes the full address they landed on (or just the code).
    @discardableResult
    func complete(pasted: String) -> Bool {
        let s = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        var items: [String: String] = [:]
        if let comps = URLComponents(string: s), let q = comps.queryItems, !q.isEmpty {
            for i in q { items[i.name] = i.value ?? "" }
        } else if !s.isEmpty, !s.contains("/"), !s.contains("?") {
            items["code"] = s
            items["state"] = expectedState
        }
        guard items["code"] != nil || items["error"] != nil else { return false }
        queue.async { [self] in _ = process(items) }
        return true
    }

    // MARK: internals

    private func startListener(open url: URL) {
        do {
            let params = NWParameters.tcp
            params.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: Self.port)!)
            let l = try NWListener(using: params)
            listener = l
            l.newConnectionHandler = { [weak self] conn in self?.handle(conn) }
            l.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    DispatchQueue.main.async { [weak self] in if let self { Self.opener(url, self) } }
                case .failed(let e):
                    self?.finish(.failure(e))
                default: break
                }
            }
            l.start(queue: queue)
            queue.asyncAfter(deadline: .now() + 300) { [weak self] in self?.finish(.failure(OAuthError.timeout)) }
        } catch {
            finish(.failure(error))
        }
    }

    private func handle(_ conn: NWConnection) {
        conn.start(queue: queue)
        conn.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            guard let self else { conn.cancel(); return }
            guard let data, let text = String(data: data, encoding: .utf8),
                  let line = text.components(separatedBy: "\r\n").first else { conn.cancel(); return }
            let parts = line.split(separator: " ")
            guard parts.count >= 2,
                  let comps = URLComponents(string: "http://localhost" + String(parts[1])),
                  comps.path == "/callback" else {
                self.reply(conn, status: "404 Not Found", html: "Not found")
                return
            }
            var items: [String: String] = [:]
            for q in comps.queryItems ?? [] { items[q.name] = q.value ?? "" }
            let r = self.process(items)
            self.reply(conn, html: Self.page(r.title, r.message))
        }
    }

    /// Validates the callback parameters and finishes the flow.
    private func process(_ items: [String: String]) -> (title: String, message: String) {
        if let err = items["error"] ?? items["error_reason"] {
            finish(.failure(OAuthError.denied(items["error_description"] ?? err)))
            return ("Login failed", err)
        }
        if items["state"] != expectedState {
            finish(.failure(OAuthError.stateMismatch))
            return ("Login failed", "State mismatch.")
        }
        if let code = items["code"] {
            finish(.success(code))
            return ("You're connected ✓", "You can close this tab and go back to Blitz.")
        }
        return ("Login failed", "No code in the response.")
    }

    private func reply(_ conn: NWConnection, status: String = "200 OK", html: String) {
        let body = Data(html.utf8)
        let head = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        conn.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in conn.cancel() })
    }

    private func finish(_ result: Result<String, Error>) {
        guard let c = continuation else { return }
        continuation = nil
        listener?.cancel()
        listener = nil
        c.resume(with: result)
        DispatchQueue.main.async { Self.closer() }
    }

    private static func page(_ title: String, _ message: String) -> String {
        """
        <html><head><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'></head>
        <body style='margin:0;height:100vh;display:flex;align-items:center;justify-content:center;
        background:linear-gradient(135deg,#1b1740,#3a1b4d);color:white;font-family:-apple-system,sans-serif;text-align:center'>
        <div><h1 style='font-weight:700'>\(title)</h1><p style='opacity:.7'>\(message)</p></div></body></html>
        """
    }
}
