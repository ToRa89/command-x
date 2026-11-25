#!/bin/bash
# Builds a universal Release app, signs it ad-hoc (no Apple Developer account needed)
# and packs it into dist/CommandX-<version>.dmg (+ .zip) with an Applications shortcut.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
BUILD="$ROOT/build"
DIST="$ROOT/dist"
APP="$BUILD/Build/Products/Release/CommandX.app"

rm -rf "$BUILD" "$DIST"
mkdir -p "$DIST"

xcodebuild -project CommandX.xcodeproj -scheme CommandX -configuration Release \
  -derivedDataPath "$BUILD" ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="-" DEVELOPMENT_TEAM="" build

# Xcode injects get-task-allow (debugger attach) even for ad-hoc Release builds. Re-sign without it.
codesign --force --deep --sign - --entitlements "$ROOT/CommandX.entitlements" "$APP"
codesign --verify --deep --strict "$APP"

VERSION="$(defaults read "$APP/Contents/Info" CFBundleShortVersionString)"
NAME="CommandX-$VERSION"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

hdiutil create -volname "Command X" -srcfolder "$STAGE" -ov -format UDZO "$DIST/$NAME.dmg" >/dev/null
(cd "$DIST" && zip -q "$NAME.dmg.zip" "$NAME.dmg" && shasum -a 256 "$NAME.dmg" "$NAME.dmg.zip" > SHA256SUMS.txt)

echo "Fertig:"; ls -lh "$DIST"; cat "$DIST/SHA256SUMS.txt"
