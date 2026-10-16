#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="SVN访达菜单"
INSTALL_DIR="/Applications"
DERIVED="$ROOT/build"
SCHEME="SVN访达菜单"

echo "==> Generating Xcode project"
xcodegen generate

echo "==> Building"
rm -rf "$DERIVED"
xcodebuild \
  -project macSvn.xcodeproj \
  -scheme "$SCHEME" \
  -configuration Release \
  -derivedDataPath "$DERIVED" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGNING_REQUIRED=NO \
  AD_HOC_CODE_SIGNING_ALLOWED=YES \
  build

APP_SRC="$(find "$DERIVED/Build/Products/Release" -maxdepth 1 -name "${APP_NAME}.app" | head -n 1)"
if [[ -z "$APP_SRC" ]]; then
  echo "Build succeeded but app bundle not found" >&2
  exit 1
fi

echo "==> Ad-hoc codesign"
codesign --force --deep --sign - --entitlements "$ROOT/App/App.entitlements" "$APP_SRC"
APPEX="$APP_SRC/Contents/PlugIns/SVNFinderSync.appex"
if [[ -d "$APPEX" ]]; then
  codesign --force --sign - --entitlements "$ROOT/FinderSync/FinderSync.entitlements" "$APPEX"
  codesign --force --deep --sign - --entitlements "$ROOT/App/App.entitlements" "$APP_SRC"
fi

echo "==> Installing to ${INSTALL_DIR}"
# Quit running instance if any
osascript -e "tell application \"${APP_NAME}\" to quit" >/dev/null 2>&1 || true
sleep 0.5
rm -rf "${INSTALL_DIR}/${APP_NAME}.app"
cp -R "$APP_SRC" "${INSTALL_DIR}/"

echo "==> Registering Finder Sync plugin"
pluginkit -a "${INSTALL_DIR}/${APP_NAME}.app/Contents/PlugIns/SVNFinderSync.appex" || true
pluginkit -e use -i com.local.svnfindermenu.FinderSync || true

echo "==> Opening app"
open "${INSTALL_DIR}/${APP_NAME}.app"

echo ""
echo "安装完成：${INSTALL_DIR}/${APP_NAME}.app"
echo "请在「系统设置 → 通用 → 登录项与扩展 → 访达扩展」中打开「SVN 访达菜单」。"
echo "若右键菜单未出现，可在应用内点击「重新启动访达」。"
