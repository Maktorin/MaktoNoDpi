#!/usr/bin/env bash
# Build, package and sign a MaktoNoDpi release for Sparkle auto-update.
#
# Usage:  scripts/release.sh <version>      e.g.  scripts/release.sh 1.0
#
# Produces in dist/:
#   MaktoNoDpi-<version>.zip   — the update archive (Sparkle downloads this)
#   MaktoNoDpi.dmg             — for manual first-time install
#   appcast.xml                — EdDSA-signed feed (Sparkle reads this)
#
# Then publish all three to a GitHub Release tagged v<version> and mark it
# "latest" (SUFeedURL points at releases/latest/download/appcast.xml).
# The private EdDSA key is read from the login Keychain (generated once via
# Sparkle's generate_keys); never committed.
set -euo pipefail

VERSION="${1:-}"
if [ -z "$VERSION" ]; then echo "usage: $0 <version>  (e.g. 1.0)" >&2; exit 2; fi
TAG="v$VERSION"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$REPO_ROOT/App"
BUILD_DIR="$REPO_ROOT/build"
DIST_DIR="$REPO_ROOT/dist"
APP_NAME="MaktoNoDpi"
DL_PREFIX="https://github.com/Maktorin/MaktoNoDpi/releases/download/$TAG/"

echo "==> Regenerating Xcode project..."
cd "$APP_DIR"
xcodegen generate

echo "==> Building Release .app..."
xcodebuild \
  -project "$APP_DIR/$APP_NAME.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR" \
  CODE_SIGNING_ALLOWED=NO \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  build >/dev/null
APP_PATH="$BUILD_DIR/Build/Products/Release/$APP_NAME.app"
[ -d "$APP_PATH" ] || { echo "ERROR: .app not found at $APP_PATH" >&2; exit 1; }

# Ad-hoc code sign (identity "-"): no Apple Developer ID, but Sparkle requires a
# valid signature to verify bundle integrity across updates (generate_appcast
# rejects fully-unsigned apps). The bundled tpws is signed first so the deep
# signature is consistent. We are not sandboxed / not hardened, so --deep is safe.
echo "==> Ad-hoc signing .app..."
codesign --force --sign - --timestamp=none "$APP_PATH/Contents/Resources/bin/tpws"
codesign --force --deep --sign - --timestamp=none "$APP_PATH"
codesign --verify --verbose "$APP_PATH"

# Sparkle CLI tools live inside the resolved SwiftPM artifacts of the build.
SPARKLE_BIN="$(find "$BUILD_DIR" -path '*sparkle/Sparkle/bin/generate_appcast' 2>/dev/null | head -1)"
SPARKLE_BIN="$(dirname "${SPARKLE_BIN:-}")"
[ -x "$SPARKLE_BIN/generate_appcast" ] || { echo "ERROR: Sparkle bin not found under $BUILD_DIR" >&2; exit 1; }

echo "==> Packaging update archive + dmg..."
rm -rf "$DIST_DIR"; mkdir -p "$DIST_DIR"
# A Sparkle archives folder holding ONLY this version's zip, so the generated
# appcast describes exactly this release with per-tag enclosure URLs.
ARCHIVES="$DIST_DIR/archives"; mkdir -p "$ARCHIVES"
# ditto -c -k preserves bundle symlinks/permissions (plain zip corrupts .app).
/usr/bin/ditto -c -k --keepParent "$APP_PATH" "$ARCHIVES/$APP_NAME-$VERSION.zip"

# DMG for manual first install (Applications symlink for drag-install).
STAGE="$(mktemp -d)"; trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP_PATH" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DIST_DIR/$APP_NAME.dmg" >/dev/null

echo "==> Generating EdDSA-signed appcast..."
"$SPARKLE_BIN/generate_appcast" --download-url-prefix "$DL_PREFIX" "$ARCHIVES"
mv "$ARCHIVES/appcast.xml" "$DIST_DIR/appcast.xml"
mv "$ARCHIVES/$APP_NAME-$VERSION.zip" "$DIST_DIR/$APP_NAME-$VERSION.zip"
rm -rf "$ARCHIVES"

echo "==> Done. Artifacts in $DIST_DIR:"
ls -1 "$DIST_DIR"
cat <<EOF

Next: publish the GitHub Release (marks it latest automatically for newest tag):
  gh release create $TAG \\
    "$DIST_DIR/$APP_NAME-$VERSION.zip" \\
    "$DIST_DIR/appcast.xml" \\
    "$DIST_DIR/$APP_NAME.dmg" \\
    --title "$APP_NAME $VERSION" --notes "…"
EOF
