#!/usr/bin/env bash
# Cut a Tamp release: universal binaries → zip → GitHub release on the public
# tap repo → formula bump. The source repo is private, so release assets are
# published on the tap repo (where brew can download them).
#
# Requires: gh (authenticated), push access to the tap repo.
#
# Usage:
#   Scripts/make-release.sh           # version from the VERSION file
#   Scripts/make-release.sh 1.1.0     # explicit version override
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-$(cat "$ROOT/VERSION")}"
TAP_REPO="vyskoczilova/homebrew-tap"
TAG="v${VERSION}"
STAGE="$ROOT/build/release-stage"
ZIP="$ROOT/build/tamp-${VERSION}-macos.zip"

echo "==> Building arm64 + x86_64 release binaries… (v${VERSION})"
# CLT-only toolchains can't do a single dual-arch build (needs xcbuild), so
# build each arch separately and lipo. arm64 goes last so the .build/release
# symlink — where make-app.sh picks up the SwiftPM resource bundle — points at
# a fresh build.
swift build -c release --arch x86_64 --package-path "$ROOT"
swift build -c release --arch arm64 --package-path "$ROOT"

echo "==> Creating universal binaries…"
mkdir -p "$ROOT/build"
lipo -create "$ROOT/.build/arm64-apple-macosx/release/tamp" \
             "$ROOT/.build/x86_64-apple-macosx/release/tamp" \
     -output "$ROOT/build/tamp-universal"
lipo -create "$ROOT/.build/arm64-apple-macosx/release/TampBar" \
             "$ROOT/.build/x86_64-apple-macosx/release/TampBar" \
     -output "$ROOT/build/TampBar-universal"

echo "==> Assembling Tamp.app around the universal binary…"
TAMP_BIN_OVERRIDE="$ROOT/build/TampBar-universal" "$ROOT/Scripts/make-app.sh" "$VERSION"

echo "==> Staging release contents…"
rm -rf "$STAGE" "$ZIP"
mkdir -p "$STAGE"
cp "$ROOT/build/tamp-universal" "$STAGE/tamp"
cp -R "$ROOT/build/Tamp.app" "$STAGE/Tamp.app"
cp "$ROOT/LICENSE" "$STAGE/LICENSE"
# lipo output is unsigned; ad-hoc sign the CLI (the app was signed by make-app.sh).
codesign --force --sign - --identifier "cz.kybernaut.tamp.cli" "$STAGE/tamp"

echo "==> Zipping…"
ditto -c -k "$STAGE" "$ZIP"
SHA256="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
echo "    $ZIP"
echo "    sha256: $SHA256"

echo "==> Publishing GitHub release ${TAG} on ${TAP_REPO}…"
gh release create "$TAG" --repo "$TAP_REPO" \
    --title "Tamp ${VERSION}" \
    --notes "Universal (arm64 + x86_64) prebuilt binaries: \`tamp\` CLI + Tamp.app menu bar app. Install: \`brew install vyskoczilova/tap/tamp\`" \
    "$ZIP"

echo "==> Bumping Formula/tamp.rb in ${TAP_REPO}…"
TAPDIR="$(mktemp -d)"
gh repo clone "$TAP_REPO" "$TAPDIR" -- --depth 1 --quiet
sed -i '' \
    -e "s|^  url \".*\"|  url \"https://github.com/${TAP_REPO}/releases/download/${TAG}/tamp-${VERSION}-macos.zip\"|" \
    -e "s|^  sha256 \".*\"|  sha256 \"${SHA256}\"|" \
    -e "s|^  version \".*\"|  version \"${VERSION}\"|" \
    "$TAPDIR/Formula/tamp.rb"
git -C "$TAPDIR" commit -am "tamp ${VERSION}" --quiet
git -C "$TAPDIR" push --quiet
rm -rf "$TAPDIR"

echo "==> Done. Install/upgrade with: brew install ${TAP_REPO/homebrew-/}/tamp"
