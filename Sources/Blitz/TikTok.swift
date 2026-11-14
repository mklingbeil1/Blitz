import Foundation

/// TikTok Content Posting API (Direct Post, FILE_UPLOAD, chunked).
enum TikTok {
    static let scopes = "user.info.basic,user.info.stats,video.list,video.publish,video.upload"
    private static let host = "https://open.tiktokapis.com"

    // MARK: Auth

    static func connect(_ c: Credentials, authorize: Authorizer) async throws -> Credentials {
        guard !c.ttClientKey.isEmpty, !c.ttClientSecret.isEmpty else {
            throw APIError("Add your TikTok Client Key and Client Secret in Settings first.")
        }
        let verifier = Util.random(64)
        let state = Util.random(24)
        let authURL = Util.url("https://www.tiktok.com/v2/auth/authorize/", [
            "client_key": c.ttClientKey,
            "scope": scopes,
            "response_type": "code",
            "redirect_uri": c.redirectURI,
            "state": state,
            "code_challenge": Util.sha256Hex(verifier),
            "code_challenge_method": "S256"
        ])
        let code = try await authorize(authURL, state)

        let token = try await tokenRequest([
            "client_key": c.ttClientKey,
            "client_secret": c.ttClientSecret,
            "code": code,
            "grant_type": "authorization_code",
            "redirect_uri": c.redirectURI,
            "code_verifier": verifier
        ])
        var out = c
        out.ttAccessToken = token.access
        out.ttRefreshToken = token.refresh
        return out
    }

    /// Access tokens last 24h, so we refresh right before every upload.
    static func refresh(_ c: Credentials) async throws -> Credentials {
        guard !c.ttRefreshToken.isEmpty else { throw APIError("TikTok isn't connected.") }
        let token = try await tokenRequest([
            "client_key": c.ttClientKey,
            "client_secret": c.ttClientSecret,
            "grant_type": "refresh_token",
            "refresh_token": c.ttRefreshToken
        ])
        var out = c
        out.ttAccessToken = token.access
        out.ttRefreshToken = token.refresh.isEmpty ? c.ttRefreshToken : token.refresh
        return out
    }

    private static func tokenRequest(_ form: [String: String]) async throws -> (access: String, refresh: String) {
        let r = try await HTTP.request(URL(string: "\(host)/v2/oauth/token/")!, method: "POST",
                                       headers: ["Cache-Control": "no-cache"], form: form)
        if let e = r["error"] as? String, !e.isEmpty {
            throw APIError("TikTok login failed: \(r["error_description"] as? String ?? e)")
        }
        guard let access = r["access_token"] as? String else { throw APIError("TikTok didn't return an access token.") }
        return (access, r["refresh_token"] as? String ?? "")
    }

    // MARK: API calls

    static func call(_ path: String, token: String, json: [String: Any] = [:]) async throws -> [String: Any] {
        let out = try await HTTP.request(URL(string: "\(host)\(path)")!, method: "POST",
                                         headers: ["Authorization": "Bearer \(token)"], json: json)
        if let e = out["error"] as? [String: Any], let code = e["code"] as? String, code != "ok" {
            throw APIError("TikTok: \(code) – \(e["message"] as? String ?? "")")
        }
        return out["data"] as? [String: Any] ?? [:]
    }

    static func privacyOptions(_ c: Credentials) async throws -> [String] {
        let d = try await call("/v2/post/publish/creator_info/query/", token: c.ttAccessToken)
        return d["privacy_level_options"] as? [String] ?? []
    }

    static func post(file: URL, size: Int64, title: String, privacy: String, c: Credentials,
                     progress: @escaping (Double) -> Void,
                     status: @escaping (String) -> Void) async throws -> String {
        // Chunking rules: 5–64 MB chunks; files < 5 MB go up as a single chunk;
        // the final chunk may be larger (it absorbs the remainder).
        let chunk = min(size, 10_000_000)
        let count = max(1, Int(size / chunk))

        let initData = try await call("/v2/post/publish/video/init/", token: c.ttAccessToken, json: [
            "post_info": [
                "title": String(title.prefix(2200)),
                "privacy_level": privacy,
                "disable_duet": false,
                "disable_comment": false,
                "disable_stitch": false
            ],
            "source_info": [
                "source": "FILE_UPLOAD",
                "video_size": size,
                "chunk_size": chunk,
                "total_chunk_count": count
            ]
        ])
        guard let publishID = initData["publish_id"] as? String,
              let uploadURL = (initData["upload_url"] as? String).flatMap(URL.init(string:)) else {
            throw APIError("TikTok didn't return an upload URL.")
        }

        let mime = file.pathExtension.lowercased() == "mov" ? "video/quicktime" : "video/mp4"
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }

        for i in 0..<count {
            let start = Int64(i) * chunk
            let end = (i == count - 1) ? size - 1 : start + chunk - 1
            try handle.seek(toOffset: UInt64(start))
            guard let data = try handle.read(upToCount: Int(end - start + 1)), !data.isEmpty else {
                throw APIError("Couldn't read the video file.")
            }
            var req = URLRequest(url: uploadURL)
            req.httpMethod = "PUT"
            req.timeoutInterval = 600
            req.setValue(mime, forHTTPHeaderField: "Content-Type")
            req.setValue("bytes \(start)-\(end)/\(size)", forHTTPHeaderField: "Content-Range")
            let (d, r) = try await URLSession.shared.upload(for: req, from: data)
            _ = try HTTP.parse(d, r)
            progress(Double(end + 1) / Double(size))
        }

        // Poll until TikTok is done
        status("Processing…")
        for _ in 0..<60 {
            let s = try await call("/v2/post/publish/status/fetch/", token: c.ttAccessToken,
                                   json: ["publish_id": publishID])
            switch s["status"] as? String ?? "" {
            case "PUBLISH_COMPLETE": return privacy == "SELF_ONLY" ? "Posted (only you can see it)" : "Published"
            case "SEND_TO_USER_INBOX": return "Sent to your TikTok inbox"
            case "FAILED": throw APIError("TikTok failed: \(s["fail_reason"] as? String ?? "unknown reason")")
            default: try await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
        return "Uploaded – TikTok is still processing it"
    }
}
