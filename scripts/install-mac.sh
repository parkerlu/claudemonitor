#!/usr/bin/env bash
#
# 本地装一版到 /Applications，供自己用。不公证、不打包 —— 那是发给别人时才做的事
# （见 package-mac.sh），两轮公证要等好几分钟，改一行就等一次不值得。
#
# 仍然用 Developer ID 签名，虽然本地跑并不需要它：TCC 是按「bundle ID + 签名身份」
# 记住授权的，换成开发证书签，辅助功能的勾就会被撤销，每次改完都得重新去系统设置点一遍。
#
#   用法： scripts/install-mac.sh
#
set -euo pipefail

cd "$(dirname "$0")/.."

TEAM_ID="5X3QDNMZ83"
SCHEME="EnDraftMac"
APP_NAME="EnDraft"
DEST="/Applications/$APP_NAME.app"

BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT

say() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }
die() { printf '\n\033[31m✗ %s\033[0m\n' "$1" >&2; exit 1; }

security find-identity -v -p codesigning | grep -q "Developer ID Application" \
    || die "缺少 Developer ID Application 证书。见 package-mac.sh 里的说明。"

say "构建"
xcodegen generate >/dev/null
xcodebuild \
    -project EnDraft.xcodeproj \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination 'platform=macOS' \
    -derivedDataPath "$BUILD_DIR/dd" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="Developer ID Application" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    ENABLE_HARDENED_RUNTIME=YES \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    build 2>&1 | grep -E '(error): |\*\* BUILD' | sort -u

APP="$BUILD_DIR/dd/Build/Products/Release/$APP_NAME.app"
[ -d "$APP" ] || die "构建产物不在预期位置：$APP"

say "替换 $DEST"
pkill -f "$DEST" 2>/dev/null || true
rm -rf "$DEST"
cp -R "$APP" /Applications/

say "启动"
open -a "$DEST"

printf '\n  已装上并启动。签名身份没变，辅助功能授权保留。\n'
codesign -d --verbose=2 "$DEST" 2>&1 | grep -E 'Authority=Developer ID Application'
