# Blitz

Native SwiftUI Mac app: drop in one video, write one caption, post to
Facebook Reels, Instagram Reels and TikTok at the same time.

## Build

Requires macOS 14+ and Xcode 15+ (or just the command line tools).

    ./build.sh          # creates build/Blitz.app
    open build/Blitz.app

Or open `Package.swift` in Xcode and press Run.

## One-time setup (each platform needs its own developer app)

Redirect URI for BOTH platforms (copy from the app's Accounts window):

    http://localhost:8765/callback

### Meta (Facebook + Instagram)
1. developers.facebook.com -> Create App (type "Business"). Add the **Facebook Login** product.
2. Facebook Login -> Settings -> Valid OAuth Redirect URIs: add the URI above.
3. Copy App ID + App Secret into the app's Accounts window.
4. Instagram must be a **Business or Creator** account linked to a Facebook **Page** you admin.
5. Leave the app in Development mode. You (as app admin) can post to your own
   Page/Instagram without App Review.
6. Click Connect. If your app only offers "Facebook Login for Business", create a
   Configuration with the permissions listed in `Meta.swift` and swap `scope` for
   `config_id` in `Meta.connect`.

### TikTok
1. developers.tiktok.com -> Manage apps -> Connect an app.
2. Add products **Login Kit** and **Content Posting API** (enable Direct Post).
3. Add the redirect URI above (if TikTok refuses plain http://localhost, see below).
4. Add scopes: user.info.basic, video.publish, video.upload.
5. Copy Client Key + Client Secret into Accounts, click Connect.
6. **Until TikTok audits your app, every post is forced to "Only me" (private).**
   Apply for the audit in the developer portal to post publicly.

## Connecting accounts (login links)
Open **Accounts** (top right, or ⌘,), paste your developer keys, press **Connect**.
Your browser opens the platform's login page. The app also shows the login link:
copy it into any browser if you like. If you end up on a page that can't load
(`localhost:8765/callback?code=...`), copy that address from the address bar and paste it
into the app's "paste the address" box. That also works for TikTok if it won't accept
a plain http://localhost redirect.

## iPhone app
`BlitzPhone.swiftpm` is the iPhone version (same posting engine as the Mac app).
1. Double-click `BlitzPhone.swiftpm` (opens in Xcode 15+).
2. Plug in your iPhone, unlock it, tap Trust. iPhone: Settings → Privacy & Security → Developer Mode → On.
3. In Xcode pick your iPhone at the top. Click the project → Signing & Capabilities → Team: your Apple ID
   (Xcode → Settings → Accounts → + to add it).
4. Press Run. First launch: iPhone Settings → General → VPN & Device Management → trust your Apple ID.
A free Apple ID installs last 7 days (just press Run again). A paid developer account ($99/yr) lets you use TestFlight / the App Store.
After editing anything in `Sources/Blitz/Shared`, run `./sync-iphone.sh` to copy it into the iPhone project.

**Automatic vs. one tap:** Facebook Pages, Instagram Business/Creator and TikTok (public or private) post fully
automatically. Facebook personal profiles and personal Instagram can't be posted to by any app (Meta doesn't
offer an API), so Blitz copies your caption and opens the app (Instagram with the video preselected); you tap Share.

Optional `relay/index.html`: a tiny page that forwards logins back to the iPhone app. Host it on any https site
(e.g. GitHub Pages), register its address as the redirect in the developer portal and enter it under
Accounts → Advanced → Custom https redirect.

## Which account types work
| Account | How |
|---|---|
| Facebook **Page** | Full auto (Facebook & Instagram card). Several Pages? Connect once, pick one. |
| Facebook personal profile | **Manual mode**: Facebook doesn't let any app post to profiles. |
| Instagram **Business / Creator** | Full auto, via the linked Facebook Page **or** "Instagram direct login" (no Page needed). |
| Instagram personal | Switch to Creator (free, in the Instagram app) or use Manual mode. |
| TikTok personal & Business | Full auto. |

Manual mode copies your caption, reveals the video in Finder and opens the platform's upload page,
so it also works with zero developer setup. If a platform refuses `http://localhost`, set a
"Custom redirect link" (https) in Accounts and paste the address you land on after logging in.

## Library tab (posted videos + views)
Shows how many videos each account has posted and how many views they got.
It needs extra permissions, so **reconnect each account once** after updating:
- Meta: `read_insights`, `instagram_manage_insights` (requested automatically; fine in Development mode for your own accounts).
- TikTok: enable the scopes `user.info.stats` and `video.list` for your app in the TikTok developer portal
  (Login Kit), then reconnect. TikTok only lists *public* videos.
Facebook / Instagram show your latest ~150 videos; view-count metric names change over time,
so a missing number means Meta didn't return one for that video.

## Logos
The Facebook, Instagram and TikTok logos are vector shapes in `Logos.swift` (paths from the
Simple Icons collection). They're trademarks of their owners: fine for personal use, but if you
distribute the app, follow each company's brand guidelines.

## Notes
- Video: MP4/MOV, H.264 + AAC, vertical 9:16, 3–90 s works everywhere.
- Graph API version is a constant in `Meta.swift` (`version`). Bump it when Meta retires it.
- If TikTok rejects the http redirect, host a tiny HTTPS page that forwards to
  `http://localhost:8765/callback?...` and register that page's URL instead.
