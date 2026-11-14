import SwiftUI
import AVKit

struct ContentView: View {
    @EnvironmentObject var m: AppModel
    @State private var targeted = false

    var body: some View {
        ZStack {
            AmbientBackground()
            VStack(spacing: 18) {
                header
                Group {
                    if m.tab == .compose { compose } else { LibraryView() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 28)
            .padding(.top, 42)
            .padding(.bottom, 24)
        }
        .frame(minWidth: 900, minHeight: 720)
        .preferredColorScheme(.dark)
        .background(WindowConfigurator())
        .fileImporter(isPresented: $m.showImporter, allowedContentTypes: [.movie]) { result in
            if case .success(let url) = result { m.load(url) }
        }
        .sheet(isPresented: $m.showAccounts) { AccountsView().environmentObject(m) }
        .alert("Something went wrong",
               isPresented: Binding(get: { m.alertMessage != nil },
                                    set: { if !$0 { m.alertMessage = nil } }),
               actions: { Button("OK") {} },
               message: { Text(m.alertMessage ?? "") })
        .task {
            await m.loadTikTokOptions()
            if !Platform.allCases.contains(where: { m.isConnected($0) }) { m.showAccounts = true }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Theme.accent).frame(width: 38, height: 38)
                Image(systemName: "bolt.fill").font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Blitz").font(.system(size: 23, weight: .heavy, design: .rounded)).foregroundStyle(Theme.accent)
                Text("One video. Every platform. Instantly.").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            tabs
            Spacer()
            Button { m.showAccounts = true } label: {
                HStack(spacing: 10) {
                    HStack(spacing: 5) {
                        ForEach(Platform.allCases) { p in
                            PlatformBadge(p: p, size: 20)
                                .saturation(m.isConnected(p) ? 1 : 0)
                                .opacity(m.isConnected(p) ? 1 : 0.45)
                        }
                    }
                    Text("Accounts").font(.callout.weight(.medium))
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Color.white.opacity(0.09), in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private var tabs: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases) { t in
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { m.tab = t }
                } label: {
                    Label(t.title, systemImage: t.symbol)
                        .font(.callout.weight(.medium))
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .foregroundStyle(m.tab == t ? Color.white : Color.secondary)
                        .background {
                            if m.tab == t { Capsule().fill(Theme.accent) }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.white.opacity(0.08), in: Capsule())
    }

    // MARK: Compose tab

    private var compose: some View {
        HStack(alignment: .top, spacing: 24) {
            videoColumn.frame(width: 250)
            VStack(spacing: 14) {
                captionCard
                platformsCard
                Spacer(minLength: 0)
                postArea
            }
        }
    }

    private var videoColumn: some View {
        VStack(spacing: 12) {
            ZStack {
                if let player = m.player {
                    VideoPlayer(player: player)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                } else {
                    dropZone
                }
            }
            .aspectRatio(9.0 / 16.0, contentMode: .fit)
            .shadow(color: .black.opacity(0.45), radius: 22, y: 10)
            .dropDestination(for: URL.self) { urls, _ in
                if let u = urls.first { m.load(u); return true }
                return false
            } isTargeted: { targeted = $0 }

            if m.videoURL != nil {
                VStack(spacing: 6) {
                    Text(m.info).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    ForEach(m.warnings, id: \.self) {
                        Label($0, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption2).foregroundStyle(.orange).multilineTextAlignment(.leading)
                    }
                    Button("Choose another video") { m.showImporter = true }
                        .buttonStyle(GhostButtonStyle()).controlSize(.small)
                        .disabled(m.isBusy)
                }
            }
        }
    }

    private var dropZone: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color.white.opacity(targeted ? 0.13 : 0.05))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(targeted ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Color.white.opacity(0.22)),
                                  style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
            )
            .overlay(
                VStack(spacing: 10) {
                    Image(systemName: "film.stack").font(.system(size: 40, weight: .light)).foregroundStyle(Theme.accent)
                    Text("Drop your video").font(.headline)
                    Text("MP4 or MOV · vertical works best").font(.caption).foregroundStyle(.secondary)
                    Button("Choose File") { m.showImporter = true }
                        .buttonStyle(GradientButtonStyle()).padding(.top, 6)
                }
            )
            .animation(.easeOut(duration: 0.15), value: targeted)
    }

    private var captionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Caption").font(.headline)
                Spacer()
                Text("\(m.caption.count) / 2200").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            CaptionEditor(text: $m.caption, placeholder: "Write a caption… #hashtags work too")
                .frame(height: 96)
                .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .card()
    }

    private var platformsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Post to").font(.headline)
            ForEach(Platform.allCases) { row($0) }
        }
        .card()
    }

    private func row(_ p: Platform) -> some View {
        let on = m.selected.contains(p)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                PlatformBadge(p: p)
                VStack(alignment: .leading, spacing: 3) {
                    Text(p.rawValue).font(.body.weight(.semibold))
                    statusLine(p)
                }
                Spacer()
                Button {
                    if on { m.selected.remove(p) } else { m.selected.insert(p) }
                } label: {
                    Image(systemName: on ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(on ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Color.secondary))
                }
                .buttonStyle(.plain)
                .disabled(m.isBusy)
            }
            if p == .tiktok, on, m.isLinked(.tiktok) {
                HStack {
                    Text("Who can see it").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Picker("", selection: $m.tiktokPrivacy) {
                        ForEach(m.tiktokOptions, id: \.self) { Text(AppModel.privacyLabel($0)).tag($0) }
                    }
                    .labelsHidden().pickerStyle(.menu).frame(width: 130)
                }
                .padding(.leading, 48)
                Text("Until TikTok audits your app, only “Only me” goes through.")
                    .font(.caption2).foregroundStyle(.tertiary).padding(.leading, 48)
            }
        }
        .padding(10)
        .background(Color.white.opacity(on ? 0.07 : 0.03), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .opacity(on ? 1 : 0.6)
    }

    @ViewBuilder
    private func statusLine(_ p: Platform) -> some View {
        switch m.states[p] {
        case .uploading(let v)?:
            HStack(spacing: 8) {
                ProgressView(value: v).frame(width: 160)
                Text("\(Int(v * 100))%").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
        case .processing(let s)?:
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text(s).font(.caption).foregroundStyle(.secondary) }
        case .done(let s)?:
            Label(s, systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
        case .failed(let msg)?:
            Label(msg, systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(.red).lineLimit(3).textSelection(.enabled)
        case .idle?, nil:
            if m.isConnected(p) {
                Text(m.accountName(p)).font(.caption).foregroundStyle(.secondary)
            } else {
                Button("Connect account") { m.showAccounts = true }
                    .buttonStyle(.link).font(.caption)
            }
        }
    }

    private var postArea: some View {
        VStack(spacing: 8) {
            Button { m.postAll() } label: {
                HStack(spacing: 8) {
                    if m.isBusy { ProgressView().controlSize(.small) } else { Image(systemName: "paperplane.fill") }
                    Text(m.isBusy ? "Posting…" : "Post to \(m.selected.count) platform\(m.selected.count == 1 ? "" : "s")")
                }
            }
            .buttonStyle(GradientButtonStyle(large: true))
            .disabled(!m.canPost)
            .keyboardShortcut(.return, modifiers: .command)

            if let hint = m.postHint, !m.isBusy {
                Text(hint).font(.caption).foregroundStyle(.secondary)
            }
            if !m.isBusy, m.hasResults {
                HStack(spacing: 10) {
                    Button("Post another video") { m.reset() }.buttonStyle(GhostButtonStyle())
                    Button("See in Library") { m.tab = .library }.buttonStyle(GhostButtonStyle())
                }
            }
        }
    }
}
