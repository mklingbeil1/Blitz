import Foundation
import Security

struct APIError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

enum Platform: String, CaseIterable, Identifiable {
    case facebook = "Facebook"
    case instagram = "Instagram"
    case tiktok = "TikTok"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .facebook: return "f.circle.fill"
        case .instagram: return "camera.circle.fill"
        case .tiktok: return "music.note"
        }
    }
}

enum JobState {
    case idle
    case uploading(Double)
    case processing(String)
    case done(String)
    case failed(String)
}

struct MetaPage: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var token: String
    var igUserID: String
    var igUsername: String
}

/// Everything secret lives in ONE Keychain item. Fields added in newer versions decode to empty
/// values, so updating never wipes saved logins.
struct Credentials: Codable {
    var fbAppID = ""
    var fbAppSecret = ""
    var ttClientKey = ""
    var ttClientSecret = ""
    var fbPageID = ""
    var fbPageName = ""
    var fbPageToken = ""
    var igUserID = ""
    var igUsername = ""
    var ttAccessToken = ""
    var ttRefreshToken = ""
    var igAppID = ""
    var igAppSecret = ""
    var igDirectToken = ""
    var igDirectUserID = ""
    var igDirectUsername = ""
    var redirectOverride = ""
    var fbPages: [MetaPage] = []
    /// Platforms (by rawValue) used in manual mode: Blitz opens the upload page instead of using the API.
    var assisted: [String] = []

    /// Where login pages send you back to: your own https page if set, else the built-in localhost listener.
    var redirectURI: String {
        let o = redirectOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        return o.isEmpty ? OAuthLoopback.redirectURI : o
    }

    init() {}

    enum CodingKeys: String, CodingKey {
        case fbAppID, fbAppSecret, ttClientKey, ttClientSecret, fbPageID, fbPageName, fbPageToken, igUserID, igUsername, ttAccessToken, ttRefreshToken, igAppID, igAppSecret, igDirectToken, igDirectUserID, igDirectUsername, redirectOverride, fbPages, assisted
    }

    init(from decoder: Decoder) throws {
        let k = try decoder.container(keyedBy: CodingKeys.self)
        fbAppID = try k.decodeIfPresent(String.self, forKey: .fbAppID) ?? ""
        fbAppSecret = try k.decodeIfPresent(String.self, forKey: .fbAppSecret) ?? ""
        ttClientKey = try k.decodeIfPresent(String.self, forKey: .ttClientKey) ?? ""
        ttClientSecret = try k.decodeIfPresent(String.self, forKey: .ttClientSecret) ?? ""
        fbPageID = try k.decodeIfPresent(String.self, forKey: .fbPageID) ?? ""
        fbPageName = try k.decodeIfPresent(String.self, forKey: .fbPageName) ?? ""
        fbPageToken = try k.decodeIfPresent(String.self, forKey: .fbPageToken) ?? ""
        igUserID = try k.decodeIfPresent(String.self, forKey: .igUserID) ?? ""
        igUsername = try k.decodeIfPresent(String.self, forKey: .igUsername) ?? ""
        ttAccessToken = try k.decodeIfPresent(String.self, forKey: .ttAccessToken) ?? ""
        ttRefreshToken = try k.decodeIfPresent(String.self, forKey: .ttRefreshToken) ?? ""
        igAppID = try k.decodeIfPresent(String.self, forKey: .igAppID) ?? ""
        igAppSecret = try k.decodeIfPresent(String.self, forKey: .igAppSecret) ?? ""
        igDirectToken = try k.decodeIfPresent(String.self, forKey: .igDirectToken) ?? ""
        igDirectUserID = try k.decodeIfPresent(String.self, forKey: .igDirectUserID) ?? ""
        igDirectUsername = try k.decodeIfPresent(String.self, forKey: .igDirectUsername) ?? ""
        redirectOverride = try k.decodeIfPresent(String.self, forKey: .redirectOverride) ?? ""
        fbPages = try k.decodeIfPresent([MetaPage].self, forKey: .fbPages) ?? []
        assisted = try k.decodeIfPresent([String].self, forKey: .assisted) ?? []
    }
}

enum Keychain {
    private static let service = "app.posteverywhere.mac"
    private static let account = "credentials"

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func save(_ c: Credentials) {
        guard let data = try? JSONEncoder().encode(c) else { return }
        SecItemDelete(baseQuery as CFDictionary)
        var add = baseQuery
        add[kSecValueData as String] = data
        SecItemAdd(add as CFDictionary, nil)
    }

    static func load() -> Credentials {
        var q = baseQuery
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let c = try? JSONDecoder().decode(Credentials.self, from: data) else { return Credentials() }
        return c
    }
}

enum AppTab: String, CaseIterable, Identifiable {
    case compose, library
    var id: String { rawValue }
    var title: String { self == .compose ? "Compose" : "Library" }
    var symbol: String { self == .compose ? "square.and.pencil" : "chart.bar.xaxis" }
}
