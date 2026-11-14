import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var m: AppModel
    @State private var platformFilter: Platform?
    @State private var sort: SortOrder = .newest

    enum SortOrder: String, CaseIterable, Identifiable {
        case newest = "Newest"
        case views = "Most views"
        var id: String { rawValue }
    }

    private var connected: [Platform] { Platform.allCases.filter { m.isLinked($0) } }
    private var anyLoading: Bool { connected.contains { m.library[$0]?.loading == true } }
    private var totalViews: Int { connected.reduce(0) { $0 + (m.library[$1]?.totalViews ?? 0) } }
    private var totalVideos: Int { connected.reduce(0) { $0 + (m.library[$1]?.count ?? 0) } }
    private var anyTruncated: Bool { connected.contains { (m.library[$0]?.truncated ?? false) && m.library[$0]?.totalCount == nil } }

    private var shown: [LibraryVideo] {
        let base = connected.flatMap { m.library[$0]?.videos ?? [] }
            .filter { platformFilter == nil || $0.platform == platformFilter }
        switch sort {
        case .newest: return base.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        case .views: return base.sorted { ($0.views ?? -1) > ($1.views ?? -1) }
        }
    }

    var body: some View {
        Group {
            if connected.isEmpty { emptyState } else { content }
        }
        .task { await m.loadLibrary() }
    }

    // MARK: Empty

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.xaxis").font(.system(size: 44, weight: .light)).foregroundStyle(Theme.accent)
            Text("Your library lives here").font(.title3.weight(.semibold))
            Text("Connect an account (not Manual mode) to see every video you've posted and how many views it got.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Connect accounts") { m.showAccounts = true }.buttonStyle(GradientButtonStyle())
        }
        .frame(maxWidth: 380, maxHeight: .infinity)
    }

    // MARK: Content

    private var content: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                totalCard
                ForEach(connected) { platformCard($0) }
            }
            controls
            if shown.isEmpty {
                if anyLoading {
                    ProgressView("Loading your videos…").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "film").font(.system(size: 30, weight: .light)).foregroundStyle(.secondary)
                        Text("No videos found").font(.headline)
                        Text("Videos you post will show up here. TikTok only lists public videos.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(shown) { row($0) }
                        if m.isLinked(.tiktok) {
                            Text("TikTok only reports public videos. Facebook and Instagram show your latest ~150.")
                                .font(.caption2).foregroundStyle(.tertiary).padding(.top, 6)
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
        }
    }

    private var totalCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.accent).frame(width: 28, height: 28)
                    Image(systemName: "sum").font(.caption.weight(.bold)).foregroundStyle(.white)
                }
                Text("All platforms").font(.subheadline.weight(.semibold))
                Spacer()
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(totalVideos.compact)\(anyTruncated ? "+" : "")")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text("videos").font(.caption).foregroundStyle(.secondary)
            }
            Label("\(totalViews.compact) views", systemImage: "eye.fill")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 14)
    }

    private func platformCard(_ p: Platform) -> some View {
        let st = m.library[p] ?? LibraryState()
        let share = totalViews > 0 ? Double(st.totalViews) / Double(totalViews) : 0
        let selected = platformFilter == p
        return Button {
            platformFilter = selected ? nil : p
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    PlatformBadge(p: p, size: 28)
                    Text(p.rawValue).font(.subheadline.weight(.semibold))
                    Spacer()
                    if st.loading { ProgressView().controlSize(.small) }
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(st.count.compact)\(st.truncated && st.totalCount == nil ? "+" : "")")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                    Text("videos").font(.caption).foregroundStyle(.secondary)
                }
                Label("\(st.totalViews.compact) views", systemImage: "eye.fill")
                    .font(.caption).foregroundStyle(.secondary)
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.10))
                        Capsule().fill(p.brand).frame(width: max(0, g.size.width * share))
                    }
                }
                .frame(height: 5)
                if let e = st.error {
                    Text(e).font(.caption2).foregroundStyle(.red).lineLimit(2)
                } else if st.viewsMissing {
                    Text("No view counts – reconnect in Accounts to grant stats access")
                        .font(.caption2).foregroundStyle(.orange).lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(padding: 14)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(selected ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Color.clear), lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Text(platformFilter.map { "\($0.rawValue) videos" } ?? "All videos").font(.headline)
            if platformFilter != nil {
                Button("Show all") { platformFilter = nil }.buttonStyle(GhostButtonStyle())
            }
            Spacer()
            Picker("Sort", selection: $sort) {
                ForEach(SortOrder.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu).frame(width: 140)
            Button {
                Task { await m.loadLibrary(force: true) }
            } label: {
                HStack(spacing: 6) {
                    if anyLoading { ProgressView().controlSize(.small) } else { Image(systemName: "arrow.clockwise") }
                    Text("Refresh")
                }
            }
            .buttonStyle(GhostButtonStyle())
            .disabled(anyLoading)
        }
    }

    private func row(_ v: LibraryVideo) -> some View {
        HStack(spacing: 14) {
            AsyncImage(url: v.thumbnail) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                default:
                    Rectangle().fill(Color.white.opacity(0.08))
                        .overlay(Image(systemName: "film").foregroundStyle(.secondary))
                }
            }
            .frame(width: 54, height: 96)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    PlatformBadge(p: v.platform, size: 20)
                    Text(v.date.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Unknown date")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text(v.caption.isEmpty ? "No caption" : v.caption)
                    .font(.body)
                    .foregroundStyle(v.caption.isEmpty ? Color.secondary : Color.primary)
                    .lineLimit(2)
                HStack(spacing: 16) {
                    stat("eye.fill", v.views)
                    stat("heart.fill", v.likes)
                    stat("bubble.right.fill", v.comments)
                    if v.shares != nil { stat("arrowshape.turn.up.right.fill", v.shares) }
                }
            }
            Spacer()
            if let url = v.url {
                Link(destination: url) {
                    Image(systemName: "arrow.up.forward.square").font(.title3)
                }
                .help("Open on \(v.platform.rawValue)")
            }
        }
        .card(padding: 12)
    }

    private func stat(_ symbol: String, _ value: Int?) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.caption2)
            Text(value.map { $0.compact } ?? "–").font(.caption.monospacedDigit())
        }
        .foregroundStyle(.secondary)
    }
}
