#!/usr/bin/env bash
# Builds "Suspenders Helper.app" into helper/build/ (ad-hoc signed for local use).
# Usage: ./helper/build-app.sh [--install]   (--install copies it to /Applications)
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
APP="$HERE/build/Suspenders Helper.app"
cd "$HERE"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/SuspendersHelper"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/SuspendersHelper"
cp "$HERE/Resources/Info.plist" "$APP/Contents/Info.plist"
if [ -d "$HERE/Resources/AppIcon.iconset" ]; then
  iconutil -c icns "$HERE/Resources/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
fi

codesign --force --sign - --timestamp=none "$APP"
echo "Built: $APP"

if [ "${1:-}" = "--install" ]; then
  pkill -x SuspendersHelper 2>/dev/null || true
  rm -rf "/Applications/Suspenders Helper.app"
  cp -R "$APP" /Applications/
  open "/Applications/Suspenders Helper.app"
  echo "Installed to /Applications and launched."
fi
