#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if pgrep -x Shitu >/dev/null; then
    printf '%s\n' '拾图仍在运行。请先退出应用，再重新构建；不会覆盖正在使用的版本。' >&2
    exit 2
fi
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
APP="$PWD/dist/拾图.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Shitu" "$APP/Contents/MacOS/Shitu"
swift scripts/make-icon.swift .build/AppIcon.iconset
iconutil -c icns .build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp LICENSE "$APP/Contents/Resources/LICENSE.txt"
SIGNING_IDENTITY="${SHITU_SIGNING_IDENTITY:--}"
codesign --force --sign "$SIGNING_IDENTITY" --identifier com.shitu.capture "$APP"
codesign --verify --deep --strict "$APP"
if [ "$SIGNING_IDENTITY" = "-" ]; then
    printf '%s\n' '本机临时签名：更新后可能需要重新启用录屏授权。正式开发可设置 SHITU_SIGNING_IDENTITY 使用稳定证书。'
fi
printf 'Built: %s\n' "$APP"
