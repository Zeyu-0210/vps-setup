#!/usr/bin/env bash
# 准备 iOS 工程：编译 Xray 内核 → 下载分流数据 → 生成 Xcode 工程并打开
#
# 用法（在 Mac 的终端里运行）：
#   cd vps-setup/ios-app
#   TEAM_ID=你的TeamID bash setup.sh
#
# 可选环境变量：
#   TEAM_ID      Apple 开发者 Team ID（不填也行，之后在 Xcode 里选）
#   BUNDLE_ID    App 的 Bundle ID，默认 com.zeyu0210.vpn（被占用时换一个）
#   LIBXRAY_TAG  libXray 版本，默认 v26.11.9（和服务器上的 Xray 版本一致）

set -euo pipefail
cd "$(dirname "$0")"

export TEAM_ID="${TEAM_ID:-}"
export BUNDLE_ID="${BUNDLE_ID:-com.zeyu0210.vpn}"
LIBXRAY_TAG="${LIBXRAY_TAG:-v26.11.9}"
XCODEGEN_VERSION="${XCODEGEN_VERSION:-2.47.0}"
BUILD=.build

red()  { printf '\033[31m%s\033[0m\n' "$*"; }
info() { printf '\033[36m==> %s\033[0m\n' "$*"; }

info "检查 Xcode 和 Go"
if ! xcodebuild -version >/dev/null 2>&1; then
  red "没找到完整的 Xcode。"
  red "先从 App Store 安装 Xcode，打开一次同意协议，然后运行："
  red "  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
  exit 1
fi
if ! command -v go >/dev/null 2>&1; then
  red "没找到 Go。去 https://go.dev/dl/ 下载 macOS 安装包（Apple 芯片选 arm64），装完重新打开终端。"
  exit 1
fi
export PATH="$(go env GOPATH)/bin:$PATH"
mkdir -p "$BUILD" Frameworks Resources

if [ -d Frameworks/LibXray.xcframework ]; then
  info "已有 Frameworks/LibXray.xcframework，跳过编译（想重新编译就删掉它）"
else
  info "编译 Xray 内核 libXray $LIBXRAY_TAG（第一次大约 5–15 分钟）"
  rm -rf "$BUILD/libXray"
  git clone --depth 1 --branch "$LIBXRAY_TAG" https://github.com/XTLS/libXray.git "$BUILD/libXray"
  (cd "$BUILD/libXray" && python3 build/main.py apple gomobile)
  XCF=$(find "$BUILD/libXray" -maxdepth 2 -type d -name 'LibXray.xcframework' | head -n 1)
  [ -n "$XCF" ] || { red "编译结束了，但没找到 LibXray.xcframework"; exit 1; }
  cp -R "$XCF" Frameworks/
fi

info "下载分流数据（让国内网站直连）"
curl -fL --retry 3 -o Resources/geosite.dat \
  https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat
curl -fL --retry 3 -o Resources/geoip.dat \
  https://github.com/Loyalsoldier/geoip/releases/latest/download/geoip-only-cn-private.dat

if command -v xcodegen >/dev/null 2>&1; then
  XCODEGEN=xcodegen
else
  XCODEGEN=$(find "$BUILD/xcodegen" -type f -name xcodegen -perm -u+x 2>/dev/null | head -n 1 || true)
  if [ -z "$XCODEGEN" ]; then
    info "下载 XcodeGen $XCODEGEN_VERSION"
    curl -fL --retry 3 -o "$BUILD/xcodegen.zip" \
      "https://github.com/yonaskolb/XcodeGen/releases/download/$XCODEGEN_VERSION/xcodegen.zip"
    rm -rf "$BUILD/xcodegen"
    unzip -q -o "$BUILD/xcodegen.zip" -d "$BUILD"
    XCODEGEN=$(find "$BUILD/xcodegen" -type f -name xcodegen -perm -u+x | head -n 1)
    [ -n "$XCODEGEN" ] || { red "XcodeGen 下载后没找到可执行文件"; exit 1; }
  fi
fi

info "生成 Xcode 工程（Bundle ID: $BUNDLE_ID）"
"$XCODEGEN" generate --spec project.yml

printf '\n\033[32m准备好了！\033[0m 接下来在 Xcode 里：\n'
echo "  1. 左上角选中 ZeyuVPN，Signing & Capabilities 里确认 Team（两个 target 都要）"
echo "  2. 用数据线连上 iPhone，在顶部设备列表里选中它"
echo "  3. 点 ▶ 运行"
open ZeyuVPN.xcodeproj
