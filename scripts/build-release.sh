#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)"
if [ "$(/usr/libexec/PlistBuddy -c 'Print SnapNestPrivateEdition' Resources/Info.plist 2>/dev/null || true)" = "true" ]; then
    RELEASE_DIR="$PWD/dist/private/v$VERSION"
else
    RELEASE_DIR="$PWD/dist/releases/v$VERSION"
fi
# Optional build suffix keeps trial bundles separate from an already running release.
if [ -n "${SHITU_BUILD_SUFFIX:-}" ]; then
    [[ "$SHITU_BUILD_SUFFIX" =~ ^[a-zA-Z0-9-]+$ ]] || { echo "Invalid build suffix" >&2; exit 2; }
    RELEASE_DIR="$RELEASE_DIR-$SHITU_BUILD_SUFFIX"
fi
APP="$RELEASE_DIR/轻屿.app"
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
cp LICENSE "$APP/Contents/Resources/LICENSE.txt"
swift scripts/make-icon.swift .build/ReleaseIcon.iconset
iconutil -c icns .build/ReleaseIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign "${SHITU_SIGNING_IDENTITY:--}" --identifier com.shitu.capture "$APP"
codesign --verify --deep --strict "$APP"
lipo "$APP/Contents/MacOS/Shitu" -verify_arch arm64 x86_64
ditto -c -k --sequesterRsrc --keepParent "$APP" "$RELEASE_DIR/轻屿-v$VERSION-macos-universal.zip"
(cd "$RELEASE_DIR" && shasum -a 256 "轻屿-v$VERSION-macos-universal.zip" > SHA256SUMS.txt)
printf 'Built release: %s\n' "$RELEASE_DIR"
