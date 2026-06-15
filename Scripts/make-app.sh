#!/usr/bin/env bash
# Build CoffeeBar and assemble it into a real Coffee.app bundle.
# Usage: Scripts/make-app.sh [version]   (version defaults to 1.0.0)
set -euo pipefail

VERSION="${1:-1.0.0}"
APP_NAME="Coffee"
BUNDLE_ID="cz.kybernaut.coffee"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/$APP_NAME.app"

echo "==> Building release binary…"
swift build -c release --package-path "$ROOT"
BIN="$ROOT/.build/release/CoffeeBar"

echo "==> Assembling $APP …"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/CoffeeBar"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key><string>CoffeeBar</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHumanReadableCopyright</key><string>© Karolína Vyskočilová</string>
</dict>
</plist>
PLIST

echo "==> Ad-hoc code signing… (helps SMAppService and Gatekeeper for local use)"
codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"

echo "==> Done: $APP"
codesign -dvv "$APP" 2>&1 | sed -n '1,4p' || true

cat <<NEXT

Next steps:
  • Move into Applications:  mv "$APP" /Applications/
  • Launch it:               open /Applications/${APP_NAME}.app
  • Enable launch-at-login:  click the menu bar icon → "Launch at Login"
                             (works from the .app; move to /Applications first
                              so the login registration points at a stable path)
NEXT
