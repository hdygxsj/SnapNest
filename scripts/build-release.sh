#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)"
RELEASE_DIR="$PWD/dist/releases/v$VERSION"
APP="$RELEASE_DIR/拾图.app"
if [ -e "$APP" ]; then
    printf '%s\n' 'Release bundle already exists; use a new version or move the previous bundle before rebuilding.' >&2
    exit 2
fi
# Separate builds work with Command Line Tools; SwiftPM's multi-arch invocation requires full Xcode.
swift build -c release --arch arm64
swift build -c release --arch x86_64
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create .build/arm64-apple-macosx/release/Shitu .build/x86_64-apple-macosx/release/Shitu -output "$APP/Contents/MacOS/Shitu"
cp Resources/Info.plist "$APP/Contents/Info.plist"
swift scripts/make-icon.swift .build/ReleaseIcon.iconset
iconutil -c icns .build/ReleaseIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign "${SHITU_SIGNING_IDENTITY:--}" --identifier com.shitu.capture "$APP"
codesign --verify --deep --strict "$APP"
lipo "$APP/Contents/MacOS/Shitu" -verify_arch arm64 x86_64
ditto -c -k --sequesterRsrc --keepParent "$APP" "$RELEASE_DIR/SnapNest-v$VERSION-macos-universal.zip"
(cd "$RELEASE_DIR" && shasum -a 256 "SnapNest-v$VERSION-macos-universal.zip" > SHA256SUMS.txt)
printf 'Built release: %s\n' "$RELEASE_DIR"
