import SwiftUI
import AppKit

struct AccountsView: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var pasted = ""
    @State private var metaKeysOpen = false
    @State private var igKeysOpen = false
    @State private var tiktokKeysOpen = false

    var body: some View {
        ZStack {
            AmbientBackground()
            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Connect your accounts").font(.system(size: 22, weight: .bold, design: .rounded))
                        Text("You log in on the platform's own page in your browser. Your password never touches this app.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Done") { dismiss() }.buttonStyle(GhostButtonStyle())
                }
                .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 14)

                if let err = m.accountsError {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text(err).font(.callout).textSelection(.enabled)
                        Spacer()
                        Button { m.accountsError = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                    }
                    .padding(12)
                    .background(Color.red.opacity(0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.red.opacity(0.45)))
                    .padding(.horizontal, 24).padding(.bottom, 12)
                }

                ScrollView {
                    VStack(spacing: 16) {
                        typesCard
                        metaCard
                        instagramDirectCard
                        tiktokCard
                        manualCard
                        redirectCard
                    }
                    .padding(.horizontal, 24).padding(.bottom, 24)
                }
            }
        }
        .frame(width: 620, height: 740)
        .preferredColorScheme(.dark)
        .onChange(of: m.accountsError) { _, _ in
            if m.c.fbAppID.isEmpty || m.c.fbAppSecret.isEmpty { metaKeysOpen = true }
            if m.c.igAppID.isEmpty || m.c.igAppSecret.isEmpty { igKeysOpen = true }
            if m.c.ttClientKey.isEmpty || m.c.ttClientSecret.isEmpty { tiktokKeysOpen = true }
        }
        .onAppear {
            metaKeysOpen = m.c.fbAppID.isEmpty || m.c.fbAppSecret.isEmpty
            igKeysOpen = m.c.igAppID.isEmpty || m.c.igAppSecret.isEmpty
            tiktokKeysOpen = m.c.ttClientKey.isEmpty || m.c.ttClientSecret.isEmpty
        }
    }

    // MARK: Which account types work

    private struct TypeRow: Identifiable {
        let id = UUID()
        let platform: Platform
        let account: String
        let how: String
        let auto: Bool
    }

    private let typeRows: [TypeRow] = [
        TypeRow(platform: .facebook, account: "Facebook Page", how: "Full auto – use “Facebook & Instagram” below", auto: true),
        TypeRow(platform: .facebook, account: "Facebook personal profile", how: "Manual mode – Facebook doesn't let any app post to profiles", auto: false),
        TypeRow(platform: .instagram, account: "Instagram Business / Creator", how: "Full auto – via your Facebook Page, or “Instagram direct login” (no Page needed)", auto: true),
        TypeRow(platform: .instagram, account: "Instagram personal", how: "Switch to Creator (free: Instagram app → Settings → Account type) or use Manual mode", auto: false),
        TypeRow(platform: .tiktok, account: "TikTok personal & Business", how: "Full auto – use “TikTok” below", auto: true)
    ]

    private var typesCard: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(typeRows) { r in
                    HStack(alignment: .top, spacing: 10) {
                        PlatformBadge(p: r.platform, size: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.account).font(.callout.weight(.semibold))
                            Label(r.how, systemImage: r.auto ? "checkmark.circle.fill" : "hand.tap.fill")
                                .font(.caption).foregroundStyle(r.auto ? Color.green : Color.orange)
                        }
                    }
                }
            }
            .padding(.top, 10)
        } label: {
            Label("Which account types work?", systemImage: "person.2.fill").font(.callout.weight(.semibold))
        }
        .card()
    }

    // MARK: Facebook & Instagram via Page

    private var metaCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                HStack(spacing: 6) { PlatformBadge(p: .facebook, size: 40); PlatformBadge(p: .instagram, size: 40) }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Facebook & Instagram").font(.headline)
                    Text("Facebook Page + the Instagram account linked to it").font(.caption2).foregroundStyle(.secondary)
                    if m.c.fbPageToken.isEmpty == false {
                        Label("Page: \(m.c.fbPageName)", systemImage: "checkmark.circle.fill")
                            .font(.caption).foregroundStyle(.green)
                        if !m.c.igUserID.isEmpty {
                            Label("Instagram: @\(m.c.igUsername)", systemImage: "checkmark.circle.fill")
                                .font(.caption).foregroundStyle(.green)
                        } else {
                            Label("No Instagram linked to this Page", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption).foregroundStyle(.orange)
                        }
                    } else {
                        Text("Not connected").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                actionButtons(connected: !m.c.fbPageToken.isEmpty, platform: .facebook,
                              connect: m.connectMeta, disconnect: m.disconnectMeta)
            }

            if m.c.fbPages.count > 1 {
                HStack {
                    Label("Post to Page", systemImage: "rectangle.stack.person.crop").font(.callout)
                    Spacer()
                    Picker("", selection: Binding(get: { m.c.fbPageID }, set: { m.selectPage($0) })) {
                        ForEach(m.c.fbPages) { pg in
                            Text(pg.igUsername.isEmpty ? pg.name : "\(pg.name)  ·  @\(pg.igUsername)").tag(pg.id)
                        }
                    }
                    .labelsHidden().pickerStyle(.menu).frame(maxWidth: 280)
                }
                .padding(10)
                .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            if m.c.fbAppID.isEmpty || m.c.fbAppSecret.isEmpty {
                Label("Step 1: paste your App ID and App Secret below, then press Connect.", systemImage: "key.fill")
                    .font(.caption).foregroundStyle(.orange)
            }

            DisclosureGroup(isExpanded: $metaKeysOpen) {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("App ID", text: $m.c.fbAppID).textFieldStyle(.roundedBorder)
                    SecureField("App Secret", text: $m.c.fbAppSecret).textFieldStyle(.roundedBorder)
                    LinkButton(title: "Open Meta for Developers", url: "https://developers.facebook.com/apps")
                    Text("""
                    How to get these (one time, free):
                    1. Open Meta for Developers → Create App → type “Business”.
                    2. Add the product “Facebook Login” → Settings → paste the redirect link (bottom of this window) into “Valid OAuth Redirect URIs”.
                    3. App settings → Basic: copy App ID and App Secret here.
                    You must be admin of the Page. Several Pages? Connect once, then pick one above.
                    """)
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.top, 8)
            } label: {
                Text("Developer keys").font(.callout.weight(.medium))
            }

            if m.authPlatform == .facebook { linkPanel }
        }
        .card()
    }

    // MARK: Instagram direct

    private var instagramDirectCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                PlatformBadge(p: .instagram, size: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Instagram direct login").font(.headline)
                    Text("Business or Creator account – no Facebook Page needed").font(.caption2).foregroundStyle(.secondary)
                    if !m.c.igDirectToken.isEmpty {
                        Label("@\(m.c.igDirectUsername)", systemImage: "checkmark.circle.fill")
                            .font(.caption).foregroundStyle(.green)
                    } else {
                        Text("Not connected").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                actionButtons(connected: !m.c.igDirectToken.isEmpty, platform: .instagram,
                              connect: m.connectInstagramDirect, disconnect: m.disconnectInstagramDirect)
            }

            DisclosureGroup(isExpanded: $igKeysOpen) {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Instagram App ID", text: $m.c.igAppID).textFieldStyle(.roundedBorder)
                    SecureField("Instagram App Secret", text: $m.c.igAppSecret).textFieldStyle(.roundedBorder)
                    LinkButton(title: "Open Meta for Developers", url: "https://developers.facebook.com/apps")
                    Text("""
                    How to get these (one time, free):
                    1. In your Meta app add the product “Instagram” → “API setup with Instagram login”.
                    2. Under “Business login settings” add the redirect link (bottom of this window).
                    3. Copy the Instagram app ID and Instagram app secret here (they differ from the Facebook ones).
                    4. App roles → Roles → add your Instagram account as an “Instagram Tester” and accept the invite in Instagram.
                    If Instagram refuses http://localhost, use the custom redirect link at the bottom.
                    """)
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.top, 8)
            } label: {
                Text("Developer keys").font(.callout.weight(.medium))
            }

            if m.authPlatform == .instagram { linkPanel }
        }
        .card()
    }

    // MARK: TikTok

    private var tiktokCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                PlatformBadge(p: .tiktok, size: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text("TikTok").font(.headline)
                    Text("Personal and Business accounts").font(.caption2).foregroundStyle(.secondary)
                    if m.isLinked(.tiktok) {
                        Label("Connected", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
                    } else {
                        Text("Not connected").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                actionButtons(connected: m.isLinked(.tiktok), platform: .tiktok,
                              connect: m.connectTikTok, disconnect: m.disconnectTikTok)
            }

            if m.c.ttClientKey.isEmpty || m.c.ttClientSecret.isEmpty {
                Label("Step 1: paste your Client Key and Client Secret below, then press Connect.", systemImage: "key.fill")
                    .font(.caption).foregroundStyle(.orange)
            }

            DisclosureGroup(isExpanded: $tiktokKeysOpen) {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Client Key", text: $m.c.ttClientKey).textFieldStyle(.roundedBorder)
                    SecureField("Client Secret", text: $m.c.ttClientSecret).textFieldStyle(.roundedBorder)
                    LinkButton(title: "Open TikTok for Developers", url: "https://developers.tiktok.com/apps")
                    Text("""
                    How to get these (one time, free):
                    1. TikTok for Developers → Manage apps → Connect an app.
                    2. Add products “Login Kit” and “Content Posting API” (enable Direct Post) and the scopes user.info.basic, user.info.stats, video.list, video.publish, video.upload (the last three power the Library tab).
                    3. Paste the redirect link (bottom of this window), then copy Client Key and Client Secret here.
                    Posts stay private until TikTok approves your app. To switch accounts, press Reconnect and log in with the other one.
                    """)
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.top, 8)
            } label: {
                Text("Developer keys").font(.callout.weight(.medium))
            }

            if m.authPlatform == .tiktok { linkPanel }
        }
        .card()
    }

    // MARK: Manual mode

    private var manualCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Manual mode", systemImage: "hand.tap.fill").font(.headline)
            Text("For personal accounts, or if you'd rather skip developer setup. Blitz copies your caption, shows the video in Finder and opens the platform's upload page, so you just drag the file in and paste. (Facebook and Instagram don't let any app post to personal accounts.)")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(Platform.allCases) { p in
                Toggle(isOn: Binding(get: { m.isAssisted(p) }, set: { m.setAssisted(p, $0) })) {
                    HStack(spacing: 8) {
                        PlatformBadge(p: p, size: 22)
                        Text(p.rawValue).font(.callout)
                        if m.isLinked(p) {
                            Text("(connected – full auto is used)").font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
                .toggleStyle(.switch)
            }
        }
        .card()
    }

    // MARK: Redirect

    private var redirectCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Redirect link").font(.headline)
            Text("Add this exact link as the redirect / callback URL in the developer portals.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Text(OAuthLoopback.redirectURI)
                    .font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                Spacer()
                Button("Copy") { copy(OAuthLoopback.redirectURI) }.buttonStyle(GhostButtonStyle())
            }
            .padding(10)
            .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            DisclosureGroup {
                VStack(alignment: .leading, spacing: 6) {
                    TextField("https://your-page.example/callback", text: $m.c.redirectOverride)
                        .textFieldStyle(.roundedBorder)
                    Text("Only if a platform refuses http://localhost (TikTok and Instagram sometimes do). Host any tiny https page, register its address in the developer portal and enter it here. After logging in, copy the address you land on and paste it into Blitz's “paste the address” box.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.top, 6)
            } label: {
                Text("Custom redirect link (advanced)").font(.callout.weight(.medium))
            }

            Label("Keys and tokens are stored in your macOS Keychain.", systemImage: "lock.fill")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .card()
    }

    // MARK: Pieces

    @ViewBuilder
    private func actionButtons(connected: Bool, platform: Platform,
                               connect: @escaping () -> Void, disconnect: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            if connected && m.authPlatform != platform {
                Button("Disconnect", action: disconnect).buttonStyle(GhostButtonStyle())
            }
            Button(connected ? "Reconnect" : "Connect", action: connect)
                .buttonStyle(GradientButtonStyle())
                .disabled(m.connecting)
        }
    }

    /// Shown while a login is in progress: the link itself, plus a paste-back fallback.
    private var linkPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Waiting for you to log in in your browser…").font(.callout.weight(.medium))
            }
            if let url = m.authLink {
                Text(url.absoluteString)
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                    .lineLimit(2).textSelection(.enabled)
                HStack(spacing: 8) {
                    Button("Open login link") { NSWorkspace.shared.open(url) }.buttonStyle(GhostButtonStyle())
                    Button("Copy link") { copy(url.absoluteString) }.buttonStyle(GhostButtonStyle())
                    Spacer()
                    Button("Cancel") { m.cancelConnect() }.buttonStyle(GhostButtonStyle())
                }
            }
            Divider().overlay(Color.white.opacity(0.1))
            Text("Logged in somewhere else, or the page didn't open? Paste the address you ended up on:")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                TextField("http://localhost:8765/callback?code=…", text: $pasted)
                    .textFieldStyle(.roundedBorder)
                Button("Submit") { m.submitPastedLink(pasted); pasted = "" }
                    .buttonStyle(GradientButtonStyle())
                    .disabled(pasted.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(12)
        .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func copy(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }
}
