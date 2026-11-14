import Foundation

/// Where an Instagram request goes: either via a Facebook Page (graph.facebook.com + page token)
/// or via Instagram direct login (graph.instagram.com + Instagram token).
struct IGTarget {
    let base: String
    let userID: String
    let token: String
    let username: String
}

/// Facebook Page Reels + Instagram Reels via the Meta Graph API.
enum Meta {
    /// Graph API versions expire ~2 years after release. Bump this if calls start failing with a version error.
    static let version = "v23.0"
    static let graph = "https://graph.facebook.com/\(version)"

    static let scopes = [
        "pages_show_list", "pages_read_engagement", "pages_manage_posts", "publish_video", "read_insights",
        "instagram_basic", "instagram_content_publish", "instagram_manage_insights", "business_management"
    ].joined(separator: ",")

    // MARK: Connect

    static func connect(_ c: Credentials, authorize: Authorizer) async throws -> Credentials {
        guard !c.fbAppID.isEmpty, !c.fbAppSecret.isEmpty else {
            throw APIError("Add your Meta App ID and App Secret in Settings first.")
        }
        var out = c
        let state = Util.random(24)

        let authURL = Util.url("https://www.facebook.com/\(version)/dialog/oauth", [
            "client_id": c.fbAppID,
            "redirect_uri": c.redirectURI,
            "state": state,
            "scope": scopes,
            "response_type": "code"
        ])
        let code = try await authorize(authURL, state)

        let short = try await HTTP.request(Util.url("\(graph)/oauth/access_token", [
            "client_id": c.fbAppID,
            "redirect_uri": c.redirectURI,
            "client_secret": c.fbAppSecret,
            "code": code
        ]))
        guard let shortToken = short["access_token"] as? String else {
            throw APIError("Facebook didn't return an access token.")
        }

        // Long-lived user token -> page tokens derived from it never expire.
        let long = try await HTTP.request(Util.url("\(graph)/oauth/access_token", [
            "grant_type": "fb_exchange_token",
            "client_id": c.fbAppID,
            "client_secret": c.fbAppSecret,
            "fb_exchange_token": shortToken
        ]))
        let userToken = (long["access_token"] as? String) ?? shortToken

        let accounts = try await HTTP.request(Util.url("\(graph)/me/accounts", [
            "fields": "id,name,access_token,instagram_business_account{id,username}",
            "limit": "50",
            "access_token": userToken
        ]))
        let pages = accounts["data"] as? [[String: Any]] ?? []
        let parsed: [MetaPage] = pages.compactMap { pg in
            guard let id = pg["id"] as? String, let token = pg["access_token"] as? String else { return nil }
            let ig = pg["instagram_business_account"] as? [String: Any]
            return MetaPage(id: id, name: pg["name"] as? String ?? id, token: token,
                            igUserID: ig?["id"] as? String ?? "", igUsername: ig?["username"] as? String ?? "")
        }
        guard !parsed.isEmpty else {
            throw APIError("No Facebook Pages found for this login. Facebook only lets apps post to Pages you manage. For a personal profile, turn on Manual mode below.")
        }
        out.fbPages = parsed
        // Keep the previously chosen Page if it's still there, else prefer one with Instagram linked.
        let chosen = parsed.first(where: { $0.id == c.fbPageID })
            ?? parsed.first(where: { !$0.igUserID.isEmpty })
            ?? parsed[0]
        out.fbPageID = chosen.id
        out.fbPageName = chosen.name
        out.fbPageToken = chosen.token
        out.igUserID = chosen.igUserID
        out.igUsername = chosen.igUsername
        return out
    }

    // MARK: Facebook Reel

    static func postFacebookReel(file: URL, size: Int64, caption: String, c: Credentials,
                                 progress: @escaping (Double) -> Void) async throws -> String {
        let endpoint = URL(string: "\(graph)/\(c.fbPageID)/video_reels")!

        // 1) start
        let start = try await HTTP.request(endpoint, method: "POST", form: [
            "upload_phase": "start",
            "access_token": c.fbPageToken
        ])
        guard let videoID = start["video_id"] as? String,
              let uploadURL = (start["upload_url"] as? String).flatMap(URL.init(string:)) else {
            throw APIError("Facebook didn't return an upload URL.")
        }

        // 2) upload bytes
        _ = try await HTTP.upload(uploadURL, headers: [
            "Authorization": "OAuth \(c.fbPageToken)",
            "offset": "0",
            "file_size": "\(size)"
        ], file: file, progress: progress)

        // 3) publish
        _ = try await HTTP.request(endpoint, method: "POST", form: [
            "upload_phase": "finish",
            "video_id": videoID,
            "video_state": "PUBLISHED",
            "description": caption,
            "access_token": c.fbPageToken
        ])
        return "Published to \(c.fbPageName)"
    }

    // MARK: Instagram Reel

    static func postInstagramReel(file: URL, size: Int64, caption: String, target t: IGTarget,
                                  progress: @escaping (Double) -> Void,
                                  status: @escaping (String) -> Void) async throws -> String {
        // 1) create resumable container
        let create = try await HTTP.request(URL(string: "\(t.base)/\(t.userID)/media")!, method: "POST", form: [
            "media_type": "REELS",
            "upload_type": "resumable",
            "caption": caption,
            "share_to_feed": "true",
            "access_token": t.token
        ])
        guard let containerID = create["id"] as? String,
              let uri = (create["uri"] as? String).flatMap({ URL(string: $0) }) else {
            throw APIError("Instagram didn't return an upload URL.")
        }

        // 2) upload bytes
        _ = try await HTTP.upload(uri, headers: [
            "Authorization": "OAuth \(t.token)",
            "offset": "0",
            "file_size": "\(size)"
        ], file: file, progress: progress)

        // 3) wait until Instagram finished processing
        status("Processing…")
        var finished = false
        for _ in 0..<120 {
            let s = try await HTTP.request(Util.url("\(t.base)/\(containerID)", [
                "fields": "status_code,status",
                "access_token": t.token
            ]))
            let code = s["status_code"] as? String ?? ""
            if code == "FINISHED" { finished = true; break }
            if code == "ERROR" || code == "EXPIRED" {
                throw APIError("Instagram rejected the video: \(s["status"] as? String ?? code)")
            }
            try await Task.sleep(nanoseconds: 5_000_000_000)
        }
        guard finished else { throw APIError("Instagram took too long to process the video.") }

        // 4) publish
        status("Publishing…")
        _ = try await HTTP.request(URL(string: "\(t.base)/\(t.userID)/media_publish")!, method: "POST", form: [
            "creation_id": containerID,
            "access_token": t.token
        ])
        return "Published to @\(t.username)"
    }
}
