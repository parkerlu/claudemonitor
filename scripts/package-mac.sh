#!/usr/bin/env bash
#
# 打出一个可以直接发给别人的 Mac 版：Developer ID 签名 → 公证 → 装订 → .dmg
#
# 对方拿到后双击挂载、拖进「应用程序」即可，不会看到「无法验证开发者」。
# 没有公证的话，对方会被 Gatekeeper 拦下，还得教他右键打开——那种链接发出去
# 基本等于没发。
#
#   用法： scripts/package-mac.sh [版本号]
#
set -euo pipefail

cd "$(dirname "$0")/.."

TEAM_ID="5X3QDNMZ83"
SCHEME="EnDraftMac"
APP_NAME="EnDraft"
NOTARY_PROFILE="endraft-notary"
VERSION="${1:-$(date +%Y.%m.%d)}"

BUILD_DIR="$(mktemp -d)"
OUT_DIR="$PWD/dist"
DMG="$OUT_DIR/$APP_NAME-$VERSION.dmg"

trap 'rm -rf "$BUILD_DIR"' EXIT

say() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }
die() { printf '\n\033[31m✗ %s\033[0m\n' "$1" >&2; exit 1; }

# ---------------------------------------------------------------- 前置检查
# 这两样都是账号操作，脚本代劳不了，所以失败时要说清楚怎么补，
# 而不是丢一句 codesign 的报错让人去猜。

say "检查前置条件"

if ! security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
    die "缺少 Developer ID Application 证书。

    这是对外分发专用的证书，跟你现在用的 Apple Development 不是一回事：
    Development 签名的 App 只能在你自己注册过的机器上跑。

    创建方式（付费账号才有这一项，你有）：
      Xcode → Settings → Accounts → 选中账号 → Manage Certificates…
      → 左下角 + → Developer ID Application

    建完重新跑本脚本。"
fi

if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    die "还没存公证凭据（钥匙串 profile: $NOTARY_PROFILE）。

    先去 https://appleid.apple.com → 登录与安全 → App 专用密码，生成一个，
    然后执行（把 <你的AppleID> 和刚生成的密码填进去）：

      xcrun notarytool store-credentials \"$NOTARY_PROFILE\" \\
        --apple-id \"<你的AppleID>\" \\
        --team-id \"$TEAM_ID\" \\
        --password \"<App 专用密码>\"

    存一次就够，以后不用再管。"
fi

command -v xcodegen >/dev/null || die "缺 xcodegen：brew install xcodegen"

# ---------------------------------------------------------------- 构建
say "生成工程并构建 Release（Developer ID 签名 + 加固运行时）"

xcodegen generate >/dev/null

# 加固运行时是公证的硬性前提。手动指定签名身份，避免 automatic signing
# 挑了 Development 证书——那样能构建成功，却过不了公证。
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
    OTHER_CODE_SIGN_FLAGS="--timestamp" \
    build 2>&1 | grep -E '(error|warning): |\*\* BUILD' | sort -u || true

APP="$BUILD_DIR/dd/Build/Products/Release/$APP_NAME.app"
[ -d "$APP" ] || die "构建产物不在预期位置：$APP"

say "校验签名"
codesign --verify --deep --strict --verbose=1 "$APP"
codesign -d --verbose=2 "$APP" 2>&1 | grep -E 'Authority=Developer ID|flags=' | head -2

# ---------------------------------------------------------------- 打包
say "打包 .dmg"
mkdir -p "$OUT_DIR"
STAGE="$BUILD_DIR/stage"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/应用程序"

rm -f "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" \
    -ov -format UDZO -quiet "$DMG"

# ---------------------------------------------------------------- 公证
say "提交公证（通常 1–5 分钟）"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait

say "装订公证票据"
# 装订之后，对方即使离线也能通过 Gatekeeper 校验。
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

say "完成"
echo "  $DMG"
echo
echo "  发给对方即可。首次打开后要去"
echo "  系统设置 → 隐私与安全性 → 辅助功能 里勾上 EnDraft（自动粘贴用）。"
