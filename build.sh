#!/bin/zsh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$PROJECT_DIR/dist/星迹.app"
CONTENTS_DIR="$APP_DIR/Contents"

mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources"

swiftc \
  -swift-version 5 \
  -parse-as-library \
  -O \
  -framework SwiftUI \
  -framework AppKit \
  -framework Photos \
  -framework Vision \
  -framework PhotosUI \
  -lsqlite3 \
  -target arm64-apple-macosx15.0 \
  "$PROJECT_DIR"/Sources/NebulaPhotos/*.swift \
  -o "$CONTENTS_DIR/MacOS/NebulaPhotos"

cp "$PROJECT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$PROJECT_DIR/Resources/AppIcon.icns" "$CONTENTS_DIR/Resources/AppIcon.icns"
xattr -cr "$APP_DIR"
codesign --force --deep --sign - "$APP_DIR"

echo "$APP_DIR"
