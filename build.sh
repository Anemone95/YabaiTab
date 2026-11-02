#!/bin/sh
# Build build/YabaiTab.app. Signed with a stable identity so the Accessibility and Screen Recording
# grants survive rebuilds.
set -eu
cd "$(dirname "$0")"
APP=build/YabaiTab.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp Info.plist "$APP/Contents/Info.plist"
swiftc -O -swift-version 5 -target arm64-apple-macos26.0 -o "$APP/Contents/MacOS/YabaiTab" Sources/*.swift
codesign --force --sign "${SIGN_IDENTITY:-yabai-cert}" --options runtime "$APP"
codesign --verify --strict "$APP"
echo "built $APP"
