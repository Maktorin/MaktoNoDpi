#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$REPO_ROOT/App"
BUILD_DIR="$REPO_ROOT/build"
DIST_DIR="$REPO_ROOT/dist"
APP_NAME="MaktoNoDpi"
DMG_NAME="$APP_NAME.dmg"

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
  build

APP_PATH="$BUILD_DIR/Build/Products/Release/$APP_NAME.app"
if [ ! -d "$APP_PATH" ]; then
  echo "ERROR: .app not found at $APP_PATH" >&2
  exit 1
fi
echo "==> Built: $APP_PATH"

echo "==> Creating DMG staging directory..."
STAGE_DIR="$(mktemp -d)"
trap 'rm -rf "$STAGE_DIR"' EXIT

cp -r "$APP_PATH" "$STAGE_DIR/$APP_NAME.app"
ln -s /Applications "$STAGE_DIR/Applications"

echo "==> Creating $DIST_DIR/$DMG_NAME..."
mkdir -p "$DIST_DIR"
hdiutil create \
  -volname "MaktoNoDpi" \
  -srcfolder "$STAGE_DIR" \
  -ov \
  -format UDZO \
  "$DIST_DIR/$DMG_NAME"

echo "==> Done: $DIST_DIR/$DMG_NAME"
ls -la "$DIST_DIR/$DMG_NAME"
