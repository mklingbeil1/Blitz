import Foundation

struct LibraryVideo: Identifiable {
    let id: String
    let rawID: String
    let platform: Platform
    var caption = ""
    var date: Date?
    var views: Int?
    var likes: Int?
    var comments: Int?
    var shares: Int?
    var url: URL?
    var thumbnail: URL?
}

struct LibraryState {
    var loading = false
    var error: String?
    var videos: [LibraryVideo] = []
    var truncated = false
    var totalCount: Int?
    var loadedAt: Date?

    var count: Int { totalCount ?? videos.count }
    var totalViews: Int { videos.compactMap(\.views).reduce(0, +) }
    /// Videos were found but none returned a view count (usually: permission missing, reconnect needed).
    var viewsMissing: Bool { !videos.isEmpty && videos.allSatisfy { $0.views == nil } }
}

extension Int {
    var compact: String { formatted(.number.notation(.compactName)) }
}

enum JSON {
    static func int(_ v: Any?) -> Int? {
        if let i = v as? Int { return i }
        if let d = v as? Double { return Int(d) }
        if let s = v as? String { return Int(s) }
        return nil
    }
    static func str(_ v: Any?) -> String? { v as? String }
    static func url(_ v: Any?) -> URL? { (v as? String).flatMap { URL(string: $0) } }
}

// MARK: - Meta (Facebook + Instagram)

extension Meta {
    private static let metaDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        return f
    }()

    /// Insight responses come as {data:[{values:[{value:N}]}]} or {data:[{total_value:{value:N}}]}.
    private static func insightValue(_ r: [String: Any]) -> Int? {
        guard let first = (r["data"] as? [[String: Any]])?.first else { return nil }
        if let vals = first["values"] as? [[String: Any]], let v = JSON.int(vals.last?["value"]) { return v }
        if let tv = first["total_value"] as? [String: Any], let v = JSON.int(tv["value"]) { return v }
        return nil
    }

    /// Tries each metric name in turn (Meta renames these every year or so).
    private static func insight(_ id: String, metrics: [String], edge: String, token: String, base: String) async -> Int? {
        for metric in metrics {
            if let r = try? await HTTP.request(Util.url("\(base)/\(id)/\(edge)",
                                                        ["metric": metric, "access_token": token])),
               let v = insightValue(r) { return v }
        }
        return nil
    }

    /// Fetches view counts for videos that don't have one yet, 8 at a time.
    private static func fillViews(_ list: inout [LibraryVideo], limit: Int = 40,
                                  fetch: @escaping @Sendable (String) async -> Int?) async {
        let idx = Array(list.indices.filter { list[$0].views == nil }.prefix(limit))
        for start in stride(from: 0, to: idx.count, by: 8) {
            let slice = Array(idx[start..<min(start + 8, idx.count)])
            let ids = slice.map { list[$0].rawID }
            let results = await withTaskGroup(of: (Int, Int?).self) { group -> [(Int, Int?)] in
                for (k, i) in slice.enumerated() {
                    let id = ids[k]
                    group.addTask { (i, await fetch(id)) }
                }
                var out: [(Int, Int?)] = []
                for await r in group { out.append(r) }
                return out
            }
            for (i, v) in results { list[i].views = v }
        }
    }

    static func facebookLibrary(_ c: Credentials) async throws -> (videos: [LibraryVideo], truncated: Bool) {
        let fieldSets = [
            "id,description,created_time,permalink_url,picture,views",
            "id,description,created_time,permalink_url,picture",
            "id,description,created_time,permalink_url"
        ]
        var byID: [String: LibraryVideo] = [:]
        var truncated = false
        var anySuccess = false
        var firstError: Error?

        for edge in ["video_reels", "videos"] {
            for fields in fieldSets {
                do {
                    var next: URL? = Util.url("\(graph)/\(c.fbPageID)/\(edge)",
                                              ["fields": fields, "limit": "50", "access_token": c.fbPageToken])
                    var pages = 0
                    while let u = next, pages < 3 {
                        let r = try await HTTP.request(u)
                        for v in r["data"] as? [[String: Any]] ?? [] {
                            guard let id = JSON.str(v["id"]) else { continue }
                            var link = JSON.str(v["permalink_url"]) ?? ""
                            if link.hasPrefix("/") { link = "https://www.facebook.com" + link }
                            var item = LibraryVideo(
                                id: "fb:\(id)", rawID: id, platform: .facebook,
                                caption: JSON.str(v["description"]) ?? "",
                                date: metaDate.date(from: JSON.str(v["created_time"]) ?? ""),
                                views: JSON.int(v["views"]),
                                url: URL(string: link),
                                thumbnail: JSON.url(v["picture"]))
                            if let old = byID[id] {
                                if item.views == nil { item.views = old.views }
                                if item.thumbnail == nil { item.thumbnail = old.thumbnail }
                                if item.caption.isEmpty { item.caption = old.caption }
                                if item.url == nil { item.url = old.url }
                            }
                            byID[id] = item
                        }
                        next = ((r["paging"] as? [String: Any])?["next"] as? String).flatMap { URL(string: $0) }
                        pages += 1
                    }
                    if next != nil { truncated = true }
                    anySuccess = true
                    break
                } catch {
                    if firstError == nil { firstError = error }
                }
            }
        }
        if !anySuccess, let e = firstError { throw e }

        var list = byID.values.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        let token = c.fbPageToken
        await fillViews(&list) { id in
            await insight(id, metrics: ["blue_reels_play_count", "total_video_views"], edge: "video_insights", token: token, base: graph)
        }
        return (list, truncated)
    }

    static func instagramLibrary(_ t: IGTarget) async throws -> (videos: [LibraryVideo], truncated: Bool) {
        var list: [LibraryVideo] = []
        var next: URL? = Util.url("\(t.base)/\(t.userID)/media", [
            "fields": "id,caption,media_type,media_product_type,timestamp,permalink,thumbnail_url,like_count,comments_count",
            "limit": "50",
            "access_token": t.token
        ])
        var pages = 0
        while let u = next, pages < 3 {
            let r = try await HTTP.request(u)
            for m in r["data"] as? [[String: Any]] ?? [] {
                guard JSON.str(m["media_type"]) == "VIDEO", let id = JSON.str(m["id"]) else { continue }
                list.append(LibraryVideo(
                    id: "ig:\(id)", rawID: id, platform: .instagram,
                    caption: JSON.str(m["caption"]) ?? "",
                    date: metaDate.date(from: JSON.str(m["timestamp"]) ?? ""),
                    likes: JSON.int(m["like_count"]),
                    comments: JSON.int(m["comments_count"]),
                    url: JSON.url(m["permalink"]),
                    thumbnail: JSON.url(m["thumbnail_url"])))
            }
            next = ((r["paging"] as? [String: Any])?["next"] as? String).flatMap { URL(string: $0) }
            pages += 1
        }
        let truncated = next != nil
        let token = t.token
        let base = t.base
        await fillViews(&list) { id in
            await insight(id, metrics: ["views", "plays"], edge: "insights", token: token, base: base)
        }
        return (list, truncated)
    }
}

// MARK: - TikTok

extension TikTok {
    static func library(_ c: Credentials) async throws -> (videos: [LibraryVideo], total: Int?, truncated: Bool) {
        // Total public videos (needs the user.info.stats scope; optional)
        var total: Int?
        if let r = try? await HTTP.request(URL(string: "https://open.tiktokapis.com/v2/user/info/?fields=display_name,video_count")!,
                                           headers: ["Authorization": "Bearer \(c.ttAccessToken)"]),
           let d = r["data"] as? [String: Any],
           let u = d["user"] as? [String: Any] {
            total = JSON.int(u["video_count"])
        }

        let fields = "id,title,video_description,create_time,cover_image_url,share_url,duration,like_count,comment_count,share_count,view_count"
        var out: [LibraryVideo] = []
        var cursor: Int?
        var more = false
        for _ in 0..<5 {
            var body: [String: Any] = ["max_count": 20]
            if let cursor { body["cursor"] = cursor }
            let d = try await call("/v2/video/list/?fields=\(fields)", token: c.ttAccessToken, json: body)
            for v in d["videos"] as? [[String: Any]] ?? [] {
                guard let id = JSON.str(v["id"]) else { continue }
                let title = JSON.str(v["title"]) ?? JSON.str(v["video_description"]) ?? ""
                out.append(LibraryVideo(
                    id: "tt:\(id)", rawID: id, platform: .tiktok,
                    caption: title,
                    date: JSON.int(v["create_time"]).map { Date(timeIntervalSince1970: TimeInterval($0)) },
                    views: JSON.int(v["view_count"]),
                    likes: JSON.int(v["like_count"]),
                    comments: JSON.int(v["comment_count"]),
                    shares: JSON.int(v["share_count"]),
                    url: JSON.url(v["share_url"]),
                    thumbnail: JSON.url(v["cover_image_url"])))
            }
            more = (d["has_more"] as? Bool) ?? false
            if !more { break }
            cursor = JSON.int(d["cursor"])
        }
        return (out, total, more)
    }
}
