#!/bin/zsh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$PROJECT_DIR/dist/星迹.app"
CONTENTS_DIR="$APP_DIR/Contents"
BUILD_DIR="$PROJECT_DIR/.build"

mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources" "$BUILD_DIR"

# 分别编译 arm64 与 x86_64，再用 lipo 合成通用二进制，
# 这样 Apple Silicon 和 Intel 的 Mac 都能直接运行。
for ARCH in arm64 x86_64; do
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
    -target "${ARCH}-apple-macosx15.0" \
    "$PROJECT_DIR"/Sources/NebulaPhotos/*.swift \
    -o "$BUILD_DIR/NebulaPhotos-$ARCH"
done

lipo -create \
  -output "$CONTENTS_DIR/MacOS/NebulaPhotos" \
  "$BUILD_DIR/NebulaPhotos-arm64" "$BUILD_DIR/NebulaPhotos-x86_64"

cp "$PROJECT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$PROJECT_DIR/Resources/AppIcon.icns" "$CONTENTS_DIR/Resources/AppIcon.icns"
xattr -cr "$APP_DIR"
codesign --force --deep --sign - "$APP_DIR"

echo "$APP_DIR"
