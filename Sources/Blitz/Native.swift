import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// The few places where macOS and iOS differ. Everything else in the app is shared.
enum Native {
    static func copy(_ s: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
        #else
        UIPasteboard.general.string = s
        #endif
    }

    static func open(_ url: URL) {
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        UIApplication.shared.open(url)
        #endif
    }

    /// Show a file in Finder (Mac only).
    static func reveal(_ url: URL) {
        #if os(macOS)
        NSWorkspace.shared.activateFileViewerSelecting([url])
        #endif
    }

    /// Keep the iPhone screen on while uploading (an upload pauses if the phone locks).
    static func keepAwake(_ on: Bool) {
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = on
        #endif
    }

    static func uploadPage(_ p: Platform) -> URL {
        switch p {
        case .facebook: return URL(string: "https://www.facebook.com/reels/create")!
        case .instagram: return URL(string: "https://www.instagram.com/")!
        case .tiktok: return URL(string: "https://www.tiktok.com/tiktokstudio/upload")!
        }
    }

    /// iPhone hand-off: copy the caption, then jump into the platform's app.
    /// Instagram opens with your video already selected; Facebook and TikTok open to their home screen
    /// (your video is the newest one in your camera roll).
    static func openApp(_ p: Platform, caption: String, assetID: String?) {
        copy(caption)
        #if os(iOS)
        var candidates: [URL] = []
        switch p {
        case .instagram:
            if let id = assetID,
               let enc = id.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
               let u = URL(string: "instagram://library?LocalIdentifier=\(enc)") { candidates.append(u) }
            candidates += [URL(string: "instagram://app")!]
        case .facebook:
            candidates += [URL(string: "fb://")!]
        case .tiktok:
            candidates += [URL(string: "snssdk1233://")!, URL(string: "tiktok://")!]
        }
        candidates.append(uploadPage(p))
        for u in candidates where u.scheme == "https" || UIApplication.shared.canOpenURL(u) {
            UIApplication.shared.open(u)
            return
        }
        #else
        open(uploadPage(p))
        #endif
    }
}
