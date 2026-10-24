#!/bin/sh
# Builds build/Wabbit.app from the SwiftPM "Wabbit" product, signs it, and optionally packs a DMG.
#   scripts/build-app.sh            ad-hoc signed app (local runs)
#   SIGN_IDENTITY="Developer ID Application: …" scripts/build-app.sh dmg
#                                    Developer ID signed app + build/Wabbit.dmg (CI release)
# VERSION / BUILD_NUMBER override the Info.plist versions.
# SPARKLE_PUBLIC_ED_KEY (from `generate_keys`, see docs/release.md) turns on in-app updates;
# without it the app is built with Sparkle embedded but never checks.
set -eu
cd "$(dirname "$0")/.."

# ponytail: arm64 only; add `--arch x86_64` to BUILD if Intel Macs matter.
# Xcode's build system with an explicit SDK: SwiftPM's default backend stamps the deployment target (14.0)
# as the SDK version, which makes macOS run Wabbit in compatibility mode with the old look. This records
# the real SDK (e.g. 27.0), so macOS 26+ gives it the current design.
BUILD="--build-system xcode -c release --product Wabbit --arch arm64 --sdk $(xcrun --sdk macosx --show-sdk-path)"
swift build $BUILD
BIN=$(swift build $BUILD --show-bin-path)

APP=build/Wabbit.app
rm -rf build && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN/Wabbit" "$APP/Contents/MacOS/Wabbit"
# SwiftPM links Sparkle with @rpath but only adds @loader_path (Contents/MacOS) as an rpath.
install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/Wabbit"
ditto "$BIN/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
# Wabbit isn't sandboxed, so Sparkle's XPC services are unused (sparkle-project.org/documentation/sandboxing).
rm -rf "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices" "$APP/Contents/Frameworks/Sparkle.framework/XPCServices"
cp App/Info.plist "$APP/Contents/Info.plist"
cp icons/wabbit-idle.svg icons/wabbit-running.svg "$APP/Contents/Resources/"
# App icon: Liquid Glass App/Wabbit.icon -> Assets.car (+ Wabbit.icns fallback). actool ships with full Xcode only.
if xcrun --find actool >/dev/null 2>&1; then
  xcrun actool App/Wabbit.icon --compile "$APP/Contents/Resources" --platform macosx --minimum-deployment-target 14.0 \
    --app-icon Wabbit --output-partial-info-plist build/icon-info.plist >/dev/null
  plutil -replace CFBundleIconFile -string Wabbit "$APP/Contents/Info.plist"
  plutil -replace CFBundleIconName -string Wabbit "$APP/Contents/Info.plist"
else
  echo "warning: actool not found (needs full Xcode); building without the app icon" >&2
fi
for b in "$BIN"/*.bundle; do [ -e "$b" ] && cp -R "$b" "$APP/Contents/Resources/"; done
[ -n "${VERSION:-}" ] && plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
[ -n "${BUILD_NUMBER:-}" ] && plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$APP/Contents/Info.plist"
[ -n "${SPARKLE_PUBLIC_ED_KEY:-}" ] && plutil -replace SUPublicEDKey -string "$SPARKLE_PUBLIC_ED_KEY" "$APP/Contents/Info.plist"

# Inside-out, no --deep: Sparkle's helpers, then the framework, then the app.
# Extra arguments (the app's entitlements) apply to hardened-runtime signing only.
sign() {
  local target="$1"; shift
  if [ -n "${SIGN_IDENTITY:-}" ]; then codesign --force --options runtime --timestamp "$@" --sign "$SIGN_IDENTITY" "$target"
  else codesign --force --sign - "$target"; fi
}
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
for code in "$SPARKLE/Versions/B/Autoupdate" "$SPARKLE/Versions/B/Updater.app" "$SPARKLE"; do sign "$code"; done
# The hardened runtime blocks Apple Events (browser addresses) without this entitlement.
sign "$APP" --entitlements App/Wabbit.entitlements
codesign --verify --strict "$APP"

if [ "${1:-}" = dmg ]; then
  STAGE=build/dmg && mkdir -p "$STAGE"
  cp -R "$APP" "$STAGE/" && ln -s /Applications "$STAGE/Applications"
  hdiutil create -volname Wabbit -srcfolder "$STAGE" -ov -format UDZO build/Wabbit.dmg
  [ -n "${SIGN_IDENTITY:-}" ] && codesign --sign "$SIGN_IDENTITY" --timestamp build/Wabbit.dmg
fi
echo "Built $APP"
