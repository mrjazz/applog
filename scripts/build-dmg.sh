#!/bin/bash
set -euo pipefail

# Builds a Release archive of the applog app, exports it, and packages it
# into a DMG under site/releases/.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT_DIR/applog.xcodeproj"
SCHEME="applog"
CONFIGURATION="Release"

BUILD_DIR="$ROOT_DIR/build"
ARCHIVE_PATH="$BUILD_DIR/applog.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
EXPORT_OPTIONS_PLIST="$BUILD_DIR/export-options.plist"
RELEASES_DIR="$ROOT_DIR/site/releases"

VERSION=$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -showBuildSettings -configuration "$CONFIGURATION" 2>/dev/null | awk -F' = ' '/MARKETING_VERSION/{print $2; exit}')
if [ -z "$VERSION" ]; then
  echo "error: could not determine MARKETING_VERSION" >&2
  exit 1
fi

APP_NAME="applog"
DMG_NAME="applog-v${VERSION}.dmg"
DMG_PATH="$RELEASES_DIR/$DMG_NAME"
STAGING_DIR="$BUILD_DIR/dmg-staging"

echo "==> Building version $VERSION"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$RELEASES_DIR"

echo "==> Archiving"
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -archivePath "$ARCHIVE_PATH"

cat > "$EXPORT_OPTIONS_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>mac-application</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
EOF

echo "==> Exporting archive"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS_PLIST"

APP_PATH="$EXPORT_PATH/$APP_NAME.app"
if [ ! -d "$APP_PATH" ]; then
  echo "error: exported app not found at $APP_PATH" >&2
  exit 1
fi

echo "==> Assembling DMG contents"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

rm -f "$DMG_PATH"

echo "==> Creating DMG"
hdiutil create -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov -format UDZO \
  "$DMG_PATH"

echo "==> Done: $DMG_PATH"
