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
# Do not remove download quarantine or unrelated extended attributes.
# Strip only metadata that codesign cannot include in a locally built bundle.
xattr -dr com.apple.FinderInfo "$APP_DIR" 2>/dev/null || true
xattr -dr com.apple.ResourceFork "$APP_DIR" 2>/dev/null || true
STARTRAIL_BUILD_IDENTITY="${STARTRAIL_SIGNING_IDENTITY:--}"
if [[ "$STARTRAIL_BUILD_IDENTITY" == "-" ]]; then
  codesign --force --options runtime --entitlements "$PROJECT_DIR/Resources/PhotoAccess.entitlements" --sign - "$APP_DIR"
else
  codesign --force --options runtime --entitlements "$PROJECT_DIR/Resources/PhotoAccess.entitlements" --timestamp --sign "$STARTRAIL_BUILD_IDENTITY" "$APP_DIR"
fi
codesign --verify --deep --strict "$APP_DIR"

# Verify the actual signed executable, not just the source entitlement file.
# A valid signature alone does not ensure Photos access under Hardened Runtime.
for ARCH in arm64 x86_64; do
  STARTRAIL_ENTITLEMENTS_JSON="$(codesign -d --xml --arch "$ARCH" --entitlements - "$APP_DIR" 2>/dev/null | plutil -convert json -o - -)"
  if [[ "$STARTRAIL_ENTITLEMENTS_JSON" != *'"com.apple.security.personal-information.photos-library":true'* ]]; then
    echo "Missing Photos Library entitlement in $ARCH signature" >&2
    exit 1
  fi
done

echo "$APP_DIR"
