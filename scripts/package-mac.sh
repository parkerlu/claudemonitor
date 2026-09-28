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

# 三个都不能少：
#   加固运行时 —— 公证的硬性前提。
#   手动指定签名身份 —— 否则 automatic signing 会挑 Development 证书，
#     构建照样成功，公证却过不了。
#   关掉基础权限注入 —— Xcode 默认塞一个 com.apple.security.get-task-allow
#     进去（允许调试器附加）。带着它必然被公证拒绝，而且 entitlements 文件里
#     根本看不到这一条，只能从产物上 codesign -d 才查得出来。
#     只在分发构建关，本地调试还得靠它让 Xcode 附加上来。
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
    OTHER_CODE_SIGN_FLAGS="--timestamp" \
    build 2>&1 | grep -E '(error|warning): |\*\* BUILD' | sort -u || true

APP="$BUILD_DIR/dd/Build/Products/Release/$APP_NAME.app"
[ -d "$APP" ] || die "构建产物不在预期位置：$APP"

say "校验签名"
codesign --verify --deep --strict --verbose=1 "$APP"
codesign -d --verbose=2 "$APP" 2>&1 | grep -E 'Authority=Developer ID|flags=' | head -2

# ---------------------------------------------------------------- 打包
# 公证一个产物并等待结果。notarytool 即使判定 Invalid 也返回 0，
# 所以必须自己看状态，否则会带着没过公证的包继续往下走。
notarize() {
    local target="$1" log="$BUILD_DIR/notary-$(basename "$target").txt"
    xcrun notarytool submit "$target" --keychain-profile "$NOTARY_PROFILE" --wait 2>&1 | tee "$log"
    if ! grep -q "status: Accepted" "$log"; then
        local sid; sid="$(awk '/^[[:space:]]*id: /{print $2; exit}' "$log")"
        printf '\n\033[31m公证未通过。Apple 给出的具体理由：\033[0m\n\n'
        xcrun notarytool log "$sid" --keychain-profile "$NOTARY_PROFILE" 2>&1 | head -60
        die "修完上面的问题再跑一次。"
    fi
}

# 先公证并装订 App 本身，再拿装订好的 App 去打 dmg。
# 只装订 dmg 是不够的：对方把 App 拖进「应用程序」之后，dmg 上那张票就跟它没关系了，
# 首次启动若没网，Gatekeeper 只能在线查验，会卡住。
say "公证 App（第 1 轮，通常 1–5 分钟）"
ZIP="$BUILD_DIR/$APP_NAME.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
notarize "$ZIP"
xcrun stapler staple "$APP"

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
say "公证 dmg（第 2 轮）"
notarize "$DMG"
xcrun stapler staple "$DMG"

say "验收：模拟对方机器上的 Gatekeeper 裁决"
xcrun stapler validate "$DMG"
MNT="$(hdiutil attach "$DMG" -nobrowse -readonly | tail -1 | awk '{$1=$2=""; print $0}' | sed 's/^ *//')"
spctl -a -vvv "$MNT/$APP_NAME.app" 2>&1 | head -3
xcrun stapler validate "$MNT/$APP_NAME.app"
hdiutil detach "$MNT" -quiet

say "完成"
echo "  $DMG"
echo
echo "  发给对方即可。首次打开后要去"
echo "  系统设置 → 隐私与安全性 → 辅助功能 里勾上 EnDraft（自动粘贴用）。"
