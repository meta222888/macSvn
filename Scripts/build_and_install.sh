#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="SVN访达菜单"
INSTALL_DIR="/Applications"
DERIVED="$ROOT/build"
SCHEME="SVN访达菜单"
BUNDLE_ID="com.local.svnfindermenu.FinderSync"

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
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM= \
  PROVISIONING_PROFILE_SPECIFIER= \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGNING_REQUIRED=NO \
  AD_HOC_CODE_SIGNING_ALLOWED=YES \
  build

APP_SRC="$(find "$DERIVED/Build/Products/Release" -maxdepth 1 -name "${APP_NAME}.app" | head -n 1)"
if [[ -z "$APP_SRC" ]]; then
  echo "Build succeeded but app bundle not found" >&2
  exit 1
fi

APPEX="$APP_SRC/Contents/PlugIns/SVNFinderSync.appex"
if [[ ! -d "$APPEX" ]]; then
  echo "Finder Sync appex missing at $APPEX" >&2
  exit 1
fi

echo "==> Ad-hoc codesign (appex last, never overwrite with app entitlements)"
# Sign appex first with its own entitlements (sandbox required for Finder Sync).
codesign --force --sign - --entitlements "$ROOT/FinderSync/FinderSync.entitlements" "$APPEX"
# Sign the host app without --deep so the appex signature/entitlements stay intact.
codesign --force --sign - --entitlements "$ROOT/App/App.entitlements" "$APP_SRC"

echo "==> Verify entitlements"
codesign -d --entitlements - "$APPEX" 2>&1 | rg -n "app-sandbox|temporary-exception|Dict|Bool|true|false" || true

echo "==> Installing to ${INSTALL_DIR}"
osascript -e "tell application \"${APP_NAME}\" to quit" >/dev/null 2>&1 || true
sleep 0.5

# Drop stale PluginKit registrations that point at the build folder.
pluginkit -r "$APPEX" 2>/dev/null || true
pluginkit -r "${INSTALL_DIR}/${APP_NAME}.app/Contents/PlugIns/SVNFinderSync.appex" 2>/dev/null || true

rm -rf "${INSTALL_DIR}/${APP_NAME}.app"
cp -R "$APP_SRC" "${INSTALL_DIR}/"

INSTALLED_APPEX="${INSTALL_DIR}/${APP_NAME}.app/Contents/PlugIns/SVNFinderSync.appex"
echo "==> Registering Finder Sync from Applications"
pluginkit -a "$INSTALLED_APPEX" || true
pluginkit -e use -i "$BUNDLE_ID" || true

echo "==> Restart Finder"
killall Finder 2>/dev/null || true
sleep 1

echo "==> PluginKit status"
pluginkit -mAvvv -i "$BUNDLE_ID" 2>&1 || true

echo "==> Opening app"
open "${INSTALL_DIR}/${APP_NAME}.app"

echo ""
echo "安装完成：${INSTALL_DIR}/${APP_NAME}.app"
echo "请确认插件路径指向 /Applications（见上方 PluginKit status）。"
echo "在已登记工作副本内右键应出现「SVN 更新」「SVN 提交」。"
