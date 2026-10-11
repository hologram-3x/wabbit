#!/bin/sh
# Builds build/Hours.app from the SwiftPM "Hours" product, signs it, and optionally packs a DMG.
#   scripts/build-app.sh            ad-hoc signed app (local runs)
#   SIGN_IDENTITY="Developer ID Application: …" scripts/build-app.sh dmg
#                                    Developer ID signed app + build/Hours.dmg (CI release)
# VERSION / BUILD_NUMBER override the Info.plist versions.
set -eu
cd "$(dirname "$0")/.."

# ponytail: host arch only (arm64 on CI); add `--arch arm64 --arch x86_64` if Intel Macs matter.
swift build -c release --product Hours
BIN=$(swift build -c release --show-bin-path)

APP=build/Hours.app
rm -rf build && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Hours" "$APP/Contents/MacOS/Hours"
cp App/Info.plist "$APP/Contents/Info.plist"
for b in "$BIN"/*.bundle; do [ -e "$b" ] && cp -R "$b" "$APP/Contents/Resources/"; done
[ -n "${VERSION:-}" ] && plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
[ -n "${BUILD_NUMBER:-}" ] && plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$APP/Contents/Info.plist"

if [ -n "${SIGN_IDENTITY:-}" ]; then
  codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
else
  codesign --force --deep --sign - "$APP"
fi
codesign --verify --strict "$APP"

if [ "${1:-}" = dmg ]; then
  STAGE=build/dmg && mkdir -p "$STAGE"
  cp -R "$APP" "$STAGE/" && ln -s /Applications "$STAGE/Applications"
  hdiutil create -volname Hours -srcfolder "$STAGE" -ov -format UDZO build/Hours.dmg
  [ -n "${SIGN_IDENTITY:-}" ] && codesign --sign "$SIGN_IDENTITY" --timestamp build/Hours.dmg
fi
echo "Built $APP"
