import SwiftUI
import AVFoundation

@MainActor
final class AppModel: ObservableObject {
    @Published var c: Credentials { didSet { Keychain.save(c) } }

    @Published var videoURL: URL?
    @Published var player: AVPlayer?
    @Published var info = ""
    @Published var warnings: [String] = []
    @Published var caption = ""

    @Published var selected: Set<Platform> = Set(Platform.allCases)
    @Published var states: [Platform: JobState] = [:]
    @Published var tiktokPrivacy = "SELF_ONLY"
    @Published var tiktokOptions = ["SELF_ONLY"]

    @Published var isBusy = false
    @Published var connecting = false
    @Published var alertMessage: String?

    // Login-link flow
    @Published var showAccounts = false
    @Published var accountsError: String?
    @Published var tab: AppTab = .compose
    /// iPhone: the camera-roll identifier of the picked video (lets Instagram open with it preselected).
    @Published var assetID: String?
    @Published var showImporter = false
    @Published var library: [Platform: LibraryState] = [:]
    @Published var authPlatform: Platform?
    @Published var authLink: URL?
    private var activeAuth: OAuthLoopback?

    private var fileSize: Int64 = 0

    init() { c = Keychain.load() }

    // MARK: Connection state

    /// Instagram can be reached via a Facebook Page (graph.facebook.com) or via direct Instagram login.
    var igTarget: IGTarget? {
        if !c.igDirectToken.isEmpty, !c.igDirectUserID.isEmpty {
            return IGTarget(base: InstagramDirect.graph, userID: c.igDirectUserID,
                            token: c.igDirectToken, username: c.igDirectUsername)
        }
        if !c.igUserID.isEmpty, !c.fbPageToken.isEmpty {
            return IGTarget(base: Meta.graph, userID: c.igUserID, token: c.fbPageToken, username: c.igUsername)
        }
        return nil
    }

    /// Connected through the platform's API: full auto-posting and Library stats.
    func isLinked(_ p: Platform) -> Bool {
        switch p {
        case .facebook: return !c.fbPageToken.isEmpty
        case .instagram: return igTarget != nil
        case .tiktok: return !c.ttRefreshToken.isEmpty
        }
    }

    func isAssisted(_ p: Platform) -> Bool { c.assisted.contains(p.rawValue) }
    /// Manual mode (personal accounts): Blitz opens the upload page instead of using the API.
    func usesAssist(_ p: Platform) -> Bool { !isLinked(p) && isAssisted(p) }
    func isConnected(_ p: Platform) -> Bool { isLinked(p) || isAssisted(p) }

    func accountName(_ p: Platform) -> String {
        if usesAssist(p) { return "Manual mode" }
        switch p {
        case .facebook: return c.fbPageName
        case .instagram: return "@" + (igTarget?.username ?? "")
        case .tiktok: return "Connected"
        }
    }

    func setAssisted(_ p: Platform, _ on: Bool) {
        var set = Set(c.assisted)
        if on { set.insert(p.rawValue) } else { set.remove(p.rawValue) }
        c.assisted = Array(set)
    }

    var canPost: Bool {
        videoURL != nil && fileSize > 0 && !isBusy && !selected.isEmpty && selected.allSatisfy(isConnected)
    }

    var postHint: String? {
        if videoURL == nil { return "Add a video to get started" }
        if selected.isEmpty { return "Pick at least one platform" }
        if let p = Platform.allCases.first(where: { selected.contains($0) && !isConnected($0) }) {
            return "Connect \(p.rawValue) first"
        }
        return nil
    }

    static func privacyLabel(_ s: String) -> String {
        switch s {
        case "PUBLIC_TO_EVERYONE": return "Everyone"
        case "MUTUAL_FOLLOW_FRIENDS": return "Friends"
        case "FOLLOWER_OF_CREATOR": return "Followers"
        case "SELF_ONLY": return "Only me"
        default: return s
        }
    }

    // MARK: Connect / disconnect

    /// Shows the login link in the UI, opens the browser, and waits for the redirect (or a pasted link).
    private func authorizer() -> Authorizer {
        return { [weak self] url, state in
            let session = OAuthLoopback(expectedState: state)
            await MainActor.run {
                self?.activeAuth = session
                self?.authLink = url
            }
            defer { Task { @MainActor in self?.activeAuth = nil; self?.authLink = nil } }
            return try await session.run(open: url)
        }
    }

    func connectMeta() {
        accountsError = nil
        c.fbAppID = c.fbAppID.trimmingCharacters(in: .whitespacesAndNewlines)
        c.fbAppSecret = c.fbAppSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !c.fbAppID.isEmpty, !c.fbAppSecret.isEmpty else {
            accountsError = "Paste your Meta App ID and App Secret first (open “Developer keys” below)."
            return
        }
        connecting = true
        authPlatform = .facebook
        Task {
            defer { connecting = false; authPlatform = nil }
            do {
                let r = try await Meta.connect(c, authorize: authorizer())
                c.fbPages = r.fbPages
                c.fbPageID = r.fbPageID; c.fbPageName = r.fbPageName; c.fbPageToken = r.fbPageToken
                c.igUserID = r.igUserID; c.igUsername = r.igUsername
                library[.facebook] = nil; library[.instagram] = nil
            }
            catch OAuthError.cancelled { }
            catch { accountsError = error.localizedDescription }
        }
    }

    func connectInstagramDirect() {
        accountsError = nil
        c.igAppID = c.igAppID.trimmingCharacters(in: .whitespacesAndNewlines)
        c.igAppSecret = c.igAppSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !c.igAppID.isEmpty, !c.igAppSecret.isEmpty else {
            accountsError = "Paste your Instagram App ID and App Secret first (open “Developer keys” below)."
            return
        }
        connecting = true
        authPlatform = .instagram
        Task {
            defer { connecting = false; authPlatform = nil }
            do {
                let r = try await InstagramDirect.connect(c, authorize: authorizer())
                c.igDirectToken = r.igDirectToken
                c.igDirectUserID = r.igDirectUserID
                c.igDirectUsername = r.igDirectUsername
                library[.instagram] = nil
            }
            catch OAuthError.cancelled { }
            catch { accountsError = error.localizedDescription }
        }
    }

    func connectTikTok() {
        accountsError = nil
        c.ttClientKey = c.ttClientKey.trimmingCharacters(in: .whitespacesAndNewlines)
        c.ttClientSecret = c.ttClientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !c.ttClientKey.isEmpty, !c.ttClientSecret.isEmpty else {
            accountsError = "Paste your TikTok Client Key and Client Secret first (open “Developer keys” below)."
            return
        }
        connecting = true
        authPlatform = .tiktok
        Task {
            defer { connecting = false; authPlatform = nil }
            do {
                let r = try await TikTok.connect(c, authorize: authorizer())
                c.ttAccessToken = r.ttAccessToken
                c.ttRefreshToken = r.ttRefreshToken
                library[.tiktok] = nil
                await loadTikTokOptions()
            }
            catch OAuthError.cancelled { }
            catch { accountsError = error.localizedDescription }
        }
    }

    func cancelConnect() { activeAuth?.cancel() }

    func submitPastedLink(_ text: String) {
        guard let a = activeAuth else { return }
        if !a.complete(pasted: text) {
            accountsError = "That doesn't look like the address from the login page. It should contain “code=…”."
        }
    }

    /// Switch which Facebook Page (and its linked Instagram account) Blitz posts to.
    func selectPage(_ id: String) {
        guard let pg = c.fbPages.first(where: { $0.id == id }) else { return }
        c.fbPageID = pg.id; c.fbPageName = pg.name; c.fbPageToken = pg.token
        c.igUserID = pg.igUserID; c.igUsername = pg.igUsername
        library[.facebook] = nil; library[.instagram] = nil
    }

    func disconnectMeta() {
        c.fbPageID = ""; c.fbPageName = ""; c.fbPageToken = ""; c.igUserID = ""; c.igUsername = ""; c.fbPages = []
        library[.facebook] = nil; library[.instagram] = nil
    }

    func disconnectInstagramDirect() {
        c.igDirectToken = ""; c.igDirectUserID = ""; c.igDirectUsername = ""
        library[.instagram] = nil
    }

    func disconnectTikTok() {
        c.ttAccessToken = ""; c.ttRefreshToken = ""
        library[.tiktok] = nil
    }

    /// Refresh in place (never overwrite the whole struct: other uploads may be running).
    private func refreshTikTok() async throws {
        let r = try await TikTok.refresh(c)
        c.ttAccessToken = r.ttAccessToken
        c.ttRefreshToken = r.ttRefreshToken
    }

    private func refreshInstagramDirect() async {
        guard !c.igDirectToken.isEmpty else { return }
        if let t = await InstagramDirect.refreshedToken(c.igDirectToken) { c.igDirectToken = t }
    }

    func loadTikTokOptions() async {
        guard !c.ttRefreshToken.isEmpty else { return }
        do {
            try await refreshTikTok()
            let opts = try await TikTok.privacyOptions(c)
            if !opts.isEmpty {
                tiktokOptions = opts
                if !opts.contains(tiktokPrivacy) { tiktokPrivacy = opts[0] }
            }
        } catch { /* non-fatal; keep defaults */ }
    }

    // MARK: Video

    func load(_ url: URL, assetID: String? = nil) {
        _ = url.startAccessingSecurityScopedResource()
        player?.pause()
        self.assetID = assetID
        videoURL = url
        player = AVPlayer(url: url)
        states = [:]
        fileSize = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        Task { await inspect(url) }
    }

    private func inspect(_ url: URL) async {
        var warn: [String] = []
        var text = url.lastPathComponent
        let ext = url.pathExtension.lowercased()
        if ext != "mp4" && ext != "mov" { warn.append("Use MP4 or MOV (H.264 + AAC) for best results.") }

        let asset = AVURLAsset(url: url)
        do {
            let dur = try await asset.load(.duration).seconds
            if let track = try await asset.loadTracks(withMediaType: .video).first {
                let nat = try await track.load(.naturalSize)
                let t = try await track.load(.preferredTransform)
                let s = nat.applying(t)
                let w = abs(s.width), h = abs(s.height)
                text += "\n\(Int(w))×\(Int(h)) · \(Int(dur)) s · \(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))"
                if h < w * 1.5 { warn.append("Not vertical 9:16 – Reels and TikTok may crop or reject it.") }
            }
            if dur < 3 { warn.append("Shorter than 3 s – Reels need at least 3 seconds.") }
            if dur > 90 { warn.append("Longer than 90 s – Facebook Reels may reject it.") }
        } catch {
            warn.append("Couldn't read video metadata.")
        }
        info = text
        warnings = warn
    }

    // MARK: Library

    var hasResults: Bool {
        states.values.contains { if case .done = $0 { return true } else { return false } }
    }

    func reset() {
        player?.pause()
        player = nil
        videoURL = nil
        assetID = nil
        info = ""
        warnings = []
        caption = ""
        states = [:]
        fileSize = 0
    }

    /// Loads posted videos + view counts for every connected platform (cached for 5 minutes unless forced).
    func loadLibrary(force: Bool = false) async {
        var targets: [Platform] = []
        for p in Platform.allCases where isLinked(p) {
            if library[p]?.loading == true { continue }
            if !force, let t = library[p]?.loadedAt, Date().timeIntervalSince(t) < 300 { continue }
            library[p, default: LibraryState()].loading = true
            library[p, default: LibraryState()].error = nil
            targets.append(p)
        }
        await withTaskGroup(of: Void.self) { group in
            for p in targets { group.addTask { await self.fetchLibrary(p) } }
        }
    }

    private func fetchLibrary(_ p: Platform) async {
        do {
            var st = LibraryState()
            switch p {
            case .facebook:
                let r = try await Meta.facebookLibrary(c)
                st.videos = r.videos; st.truncated = r.truncated
            case .instagram:
                await refreshInstagramDirect()
                guard let t = igTarget else { throw APIError("Instagram isn't connected.") }
                let r = try await Meta.instagramLibrary(t)
                st.videos = r.videos; st.truncated = r.truncated
            case .tiktok:
                try await refreshTikTok()
                let r = try await TikTok.library(c)
                st.videos = r.videos; st.truncated = r.truncated; st.totalCount = r.total
            }
            st.loadedAt = Date()
            library[p] = st
        } catch {
            var st = library[p] ?? LibraryState()
            st.loading = false
            st.error = error.localizedDescription
            library[p] = st
        }
    }

    // MARK: Posting

    func postAll() {
        guard canPost, let url = videoURL else { return }
        isBusy = true
        let targets = Platform.allCases.filter { selected.contains($0) }
        states = [:]
        for p in targets { states[p] = .uploading(0) }
        let size = fileSize, text = caption, privacy = tiktokPrivacy
        if targets.contains(where: { usesAssist($0) }) {
            Native.reveal(url)   // Mac: show the video in Finder, ready to drag in
        }
        Native.keepAwake(true)

        Task {
            await withTaskGroup(of: Void.self) { group in
                for p in targets {
                    group.addTask { await self.run(p, file: url, size: size, caption: text, privacy: privacy) }
                }
            }
            isBusy = false
            Native.keepAwake(false)
            for p in Platform.allCases { library[p]?.loadedAt = nil }   // stats are stale after posting
        }
    }

    /// Ignore late progress callbacks once a job has finished.
    private func update(_ p: Platform, _ s: JobState) {
        switch states[p] {
        case .done?, .failed?: return
        default: states[p] = s
        }
    }

    private func run(_ p: Platform, file: URL, size: Int64, caption: String, privacy: String) async {
        let progress: (Double) -> Void = { [weak self] v in
            Task { @MainActor in self?.update(p, .uploading(v)) }
        }
        let status: (String) -> Void = { [weak self] s in
            Task { @MainActor in self?.update(p, .processing(s)) }
        }
        do {
            if usesAssist(p) {
                states[p] = .done(assist(p, caption: caption))
                return
            }
            let message: String
            switch p {
            case .facebook:
                message = try await Meta.postFacebookReel(file: file, size: size, caption: caption, c: c, progress: progress)
            case .instagram:
                await refreshInstagramDirect()
                guard let t = igTarget else { throw APIError("Instagram isn't connected.") }
                message = try await Meta.postInstagramReel(file: file, size: size, caption: caption, target: t,
                                                           progress: progress, status: status)
            case .tiktok:
                try await refreshTikTok()
                message = try await TikTok.post(file: file, size: size, title: caption, privacy: privacy, c: c,
                                                progress: progress, status: status)
            }
            states[p] = .done(message)
        } catch {
            states[p] = .failed(error.localizedDescription)
        }
    }

    /// Manual mode. Mac: copy the caption and open the upload page. iPhone: copy the caption; the UI then shows
    /// an "Open <app>" button per platform (opening one app leaves Blitz, so it has to be one tap each).
    private func assist(_ p: Platform, caption: String) -> String {
        Native.copy(caption)
        #if os(macOS)
        Native.open(Native.uploadPage(p))
        return "Upload page opened · caption copied"
        #else
        return "Caption copied · tap Open \(p.rawValue) below"
        #endif
    }
}
