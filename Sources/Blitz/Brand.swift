import SwiftUI

enum Theme {
    static let accent = LinearGradient(
        colors: [Color(red: 0.46, green: 0.36, blue: 1.0), Color(red: 0.95, green: 0.30, blue: 0.65)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
}

extension Platform {
    var brand: AnyShapeStyle {
        switch self {
        case .facebook:
            return AnyShapeStyle(LinearGradient(colors: [Color(red: 0.25, green: 0.55, blue: 1.0), Color(red: 0.05, green: 0.38, blue: 0.92)],
                                                startPoint: .top, endPoint: .bottom))
        case .instagram:
            return AnyShapeStyle(LinearGradient(colors: [Color(red: 0.99, green: 0.69, blue: 0.19), Color(red: 0.93, green: 0.20, blue: 0.40), Color(red: 0.55, green: 0.20, blue: 0.80)],
                                                startPoint: .bottomLeading, endPoint: .topTrailing))
        case .tiktok:
            return AnyShapeStyle(LinearGradient(colors: [Color(red: 0.10, green: 0.80, blue: 0.80), Color(red: 0.95, green: 0.15, blue: 0.35)],
                                                startPoint: .leading, endPoint: .trailing))
        }
    }
}

struct AmbientBackground: View {
    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.05, blue: 0.09)
            Circle().fill(Color(red: 0.46, green: 0.36, blue: 1.0).opacity(0.35))
                .frame(width: 520, height: 520).blur(radius: 120).offset(x: -300, y: -240)
            Circle().fill(Color(red: 0.95, green: 0.30, blue: 0.65).opacity(0.22))
                .frame(width: 460, height: 460).blur(radius: 120).offset(x: 320, y: 280)
            Circle().fill(Color(red: 0.10, green: 0.45, blue: 0.95).opacity(0.18))
                .frame(width: 380, height: 380).blur(radius: 110).offset(x: 320, y: -260)
        }
        .ignoresSafeArea()
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.10)))
    }
}

struct PlatformBadge: View {
    let p: Platform
    var size: CGFloat = 36

    var body: some View {
        Group {
            switch p {
            case .facebook: facebook
            case .instagram: instagram
            case .tiktok: tiktok
            }
        }
        .frame(width: size, height: size)
    }

    /// Facebook: blue disc with the white "f" (the logo's "f" is a cut-out, so a white disc sits behind it).
    private var facebook: some View {
        ZStack {
            Circle().fill(Color.white).padding(size * 0.03)
            FacebookLogo().fill(Color(red: 8.0 / 255, green: 102.0 / 255, blue: 255.0 / 255))
        }
    }

    /// Instagram: white glyph on the signature yellow → magenta → blue gradient.
    private var instagram: some View {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(RadialGradient(
                colors: [Color(red: 0.996, green: 0.835, blue: 0.463),
                         Color(red: 0.957, green: 0.443, blue: 0.200),
                         Color(red: 0.737, green: 0.188, blue: 0.506),
                         Color(red: 0.298, green: 0.388, blue: 0.824)],
                center: UnitPoint(x: 0.25, y: 1.0), startRadius: 0, endRadius: size * 1.25))
            .overlay(InstagramLogo().fill(Color.white).padding(size * 0.2))
    }

    /// TikTok: white note with the cyan / red offset shadows on black.
    private var tiktok: some View {
        let o = size * 0.03
        return RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(Color.black)
            .overlay(
                ZStack {
                    TikTokLogo().fill(Color(red: 0.145, green: 0.957, blue: 0.933)).offset(x: -o, y: -o)
                    TikTokLogo().fill(Color(red: 0.996, green: 0.173, blue: 0.333)).offset(x: o, y: o)
                    TikTokLogo().fill(Color.white)
                }
                .padding(size * 0.24)
            )
    }
}

struct GradientButtonStyle: ButtonStyle {
    var large = false
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        Inner(configuration: configuration, large: large)
    }
    private struct Inner: View {
        let configuration: ButtonStyleConfiguration
        let large: Bool
        @Environment(\.isEnabled) private var enabled
        var body: some View {
            configuration.label
                .font(large ? .headline : .callout.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, large ? 24 : 16)
                .padding(.vertical, large ? 14 : 8)
                .frame(maxWidth: large ? .infinity : nil)
                .background(Theme.accent, in: Capsule())
                .opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.35)
        }
    }
}

struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            .font(.callout.weight(.medium))
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(Color.white.opacity(configuration.isPressed ? 0.18 : 0.10), in: Capsule())
    }
}

/// A link that always works: opens in the default browser, with a copy button next to it.
struct LinkButton: View {
    let title: String
    let url: String

    var body: some View {
        HStack(spacing: 8) {
            Button {
                if let u = URL(string: url) { Native.open(u) }
            } label: {
                Label(title, systemImage: "arrow.up.forward.square")
            }
            .buttonStyle(GhostButtonStyle())

            Button {
                Native.copy(url)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(GhostButtonStyle())
            .help("Copy link")

            Text(url.replacingOccurrences(of: "https://", with: ""))
                .font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
        }
    }
}
