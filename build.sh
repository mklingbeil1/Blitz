#!/bin/bash
# Builds a double-clickable Blitz.app into ./build
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN="$(swift build -c release --show-bin-path)"
APP="build/Blitz.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Blitz" "$APP/Contents/MacOS/Blitz"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# App icon: AppIcon.png -> AppIcon.icns
if [ -f Resources/AppIcon.png ]; then
  SET="$(mktemp -d)/AppIcon.iconset"
  mkdir -p "$SET"
  for s in 16 32 128 256 512; do
    sips -z $s $s Resources/AppIcon.png --out "$SET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) Resources/AppIcon.png --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
done
  iconutil -c icns "$SET" -o "$APP/Contents/Resources/AppIcon.icns"
fi

codesign --force --deep --sign - "$APP"
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
echo "Built $APP  ->  open it with: open $APP"
