#!/usr/bin/env bash
# Build TampBar and assemble it into a real Tamp.app bundle.
#
# Usage:
#   Scripts/make-app.sh                   # build only → build/Tamp.app
#   Scripts/make-app.sh --install         # build + quit old + install to /Applications/ + relaunch
#   Scripts/make-app.sh --install 1.2.0   # same, with an explicit version override
set -euo pipefail

INSTALL=false
VERSION_ARG=""
for arg in "$@"; do
    case "$arg" in
        --install|-i) INSTALL=true ;;
        *) VERSION_ARG="$arg" ;;
    esac
done

APP_NAME="Tamp"
# The SwiftPM target is "TampBar", but the binary is installed under this name
# (see the cp below) so the running process and the bundle share one identity.
EXE_NAME="Tamp"
BUNDLE_ID="cz.kybernaut.tamp"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${VERSION_ARG:-$(cat "$ROOT/VERSION" 2>/dev/null || echo "0.0.0")}"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/$APP_NAME.app"

echo "==> Building release binary… (v${VERSION})"
swift build -c release --package-path "$ROOT"
BIN="$ROOT/.build/release/TampBar"

echo "==> Assembling $APP …"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
# Install the binary as $EXE_NAME so the running process and the bundle share
# one identity. (The SwiftPM target stays "TampBar" — it can't be renamed to
# "Tamp" because the filesystem is case-insensitive and the `tamp` CLI would
# collide.) The menu-bar / login-item identity comes from the bundle, not the
# target name, so this rename-on-copy is all it takes.
cp "$BIN" "$APP/Contents/MacOS/$EXE_NAME"

# Ship the SwiftPM resource bundle (custom icon SVGs) so Bundle.module resolves
# inside the packaged app — it looks for the bundle in Contents/Resources.
cp -R "$ROOT"/.build/release/*_TampBar.bundle "$APP/Contents/Resources/" 2>/dev/null || true

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key><string>${EXE_NAME}</string>
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
    echo "==> Quitting running Tamp.app…"
    # New bundles run as $EXE_NAME; "TampBar" covers bare dev runs, and the
    # Coffee/CoffeeBar names cover pre-rename installs.
    pkill -x "$EXE_NAME" 2>/dev/null || true
    pkill -x TampBar 2>/dev/null || true
    pkill -x Coffee 2>/dev/null || true
    pkill -x CoffeeBar 2>/dev/null || true
    sleep 1

    echo "==> Installing to /Applications/…"
    rm -rf /Applications/Tamp.app
    cp -r "$APP" /Applications/Tamp.app

    echo "==> Launching /Applications/Tamp.app…"
    open /Applications/Tamp.app
    echo "==> Done — Tamp ${VERSION} is running from /Applications/"
else
    cat <<NEXT

Next steps:
  • Install:   Scripts/make-app.sh --install
    (quits old instance, replaces /Applications/Tamp.app, relaunches)
  • Or manually:
      mv "$APP" /Applications/   # only works if Tamp.app isn't there yet
      open /Applications/${APP_NAME}.app
NEXT
fi
