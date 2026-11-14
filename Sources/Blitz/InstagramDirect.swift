import Foundation

/// "Instagram API with Instagram Login": lets Business / Creator accounts connect directly,
/// without a Facebook Page. Uses its own app ID/secret (shown in the Meta app under Instagram → API setup).
enum InstagramDirect {
    static let graph = "https://graph.instagram.com/\(Meta.version)"
    static let scopes = "instagram_business_basic,instagram_business_content_publish,instagram_business_manage_insights"

    private static func idString(_ v: Any?) -> String? {
        if let s = v as? String { return s }
        if let i = v as? Int { return String(i) }
        return nil
    }

    static func connect(_ c: Credentials, authorize: Authorizer) async throws -> Credentials {
        guard !c.igAppID.isEmpty, !c.igAppSecret.isEmpty else {
            throw APIError("Add your Instagram App ID and App Secret first.")
        }
        let state = Util.random(24)
        let authURL = Util.url("https://www.instagram.com/oauth/authorize", [
            "client_id": c.igAppID,
            "redirect_uri": c.redirectURI,
            "response_type": "code",
            "scope": scopes,
            "state": state,
            "force_reauth": "true"      // always show the login screen so you can pick the right account
        ])
        var code = try await authorize(authURL, state)
        if code.hasSuffix("#_") { code = String(code.dropLast(2)) }

        let short = try await HTTP.request(URL(string: "https://api.instagram.com/oauth/access_token")!, method: "POST", form: [
            "client_id": c.igAppID,
            "client_secret": c.igAppSecret,
            "grant_type": "authorization_code",
            "redirect_uri": c.redirectURI,
            "code": code
        ])
        let row = (short["data"] as? [[String: Any]])?.first ?? short
        guard let shortToken = row["access_token"] as? String else {
            throw APIError("Instagram didn't return an access token.")
        }

        // Long-lived token (60 days, refreshed automatically each time you post)
        let long = try await HTTP.request(Util.url("https://graph.instagram.com/access_token", [
            "grant_type": "ig_exchange_token",
            "client_secret": c.igAppSecret,
            "access_token": shortToken
        ]))
        let token = long["access_token"] as? String ?? shortToken

        let me = try await HTTP.request(Util.url("\(graph)/me", [
            "fields": "user_id,username",
            "access_token": token
        ]))
        var out = c
        out.igDirectToken = token
        out.igDirectUserID = idString(me["user_id"]) ?? idString(me["id"]) ?? idString(row["user_id"]) ?? ""
        out.igDirectUsername = me["username"] as? String ?? ""
        guard !out.igDirectUserID.isEmpty else {
            throw APIError("Couldn't read your Instagram account. It must be a Business or Creator account.")
        }
        return out
    }

    /// Returns a fresh token, or nil if it's too early to refresh (needs ≥ 24 h old) or it failed.
    static func refreshedToken(_ token: String) async -> String? {
        guard !token.isEmpty,
              let r = try? await HTTP.request(Util.url("https://graph.instagram.com/refresh_access_token", [
                  "grant_type": "ig_refresh_token",
                  "access_token": token
              ])) else { return nil }
        return r["access_token"] as? String
    }
}
