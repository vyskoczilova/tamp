#!/usr/bin/env bash
# Build CoffeeBar and assemble it into a real Coffee.app bundle.
#
# Usage:
#   Scripts/make-app.sh                   # build only → build/Coffee.app
#   Scripts/make-app.sh --install         # build + quit old + install to /Applications/ + relaunch
#   Scripts/make-app.sh --install 0.3.0   # same, with an explicit version override
set -euo pipefail

INSTALL=false
VERSION_ARG=""
for arg in "$@"; do
    case "$arg" in
        --install|-i) INSTALL=true ;;
        *) VERSION_ARG="$arg" ;;
    esac
done

APP_NAME="Coffee"
BUNDLE_ID="cz.kybernaut.coffee"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${VERSION_ARG:-$(cat "$ROOT/VERSION" 2>/dev/null || echo "0.0.0")}"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/$APP_NAME.app"

echo "==> Building release binary… (v${VERSION})"
swift build -c release --package-path "$ROOT"
BIN="$ROOT/.build/release/CoffeeBar"

echo "==> Assembling $APP …"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
# Install the binary as "Coffee" so the running process and the bundle share one
# identity. (The SwiftPM target stays "CoffeeBar" — it can't be renamed to
# "Coffee" because the filesystem is case-insensitive and the `coffee` CLI would
# collide.) The menu-bar / login-item identity comes from the bundle, not the
# target name, so this rename-on-copy is all it takes.
cp "$BIN" "$APP/Contents/MacOS/Coffee"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key><string>Coffee</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHumanReadableCopyright</key><string>© 2026 Karolína Vyskočilová</string>
</dict>
</plist>
PLIST

echo "==> Ad-hoc code signing…"
codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"

echo "==> Done: $APP"
codesign -dvv "$APP" 2>&1 | sed -n '1,4p' || true

if $INSTALL; then
    echo "==> Quitting running Coffee.app…"
    # New bundles run as "Coffee"; "CoffeeBar" covers older installs and bare runs.
    pkill -x Coffee 2>/dev/null || true
    pkill -x CoffeeBar 2>/dev/null || true
    sleep 1

    echo "==> Installing to /Applications/…"
    rm -rf /Applications/Coffee.app
    cp -r "$APP" /Applications/Coffee.app

    echo "==> Launching /Applications/Coffee.app…"
    open /Applications/Coffee.app
    echo "==> Done — Coffee ${VERSION} is running from /Applications/"
else
    cat <<NEXT

Next steps:
  • Install:   Scripts/make-app.sh --install
    (quits old instance, replaces /Applications/Coffee.app, relaunches)
  • Or manually:
      mv "$APP" /Applications/   # only works if Coffee.app isn't there yet
      open /Applications/${APP_NAME}.app
NEXT
fi
