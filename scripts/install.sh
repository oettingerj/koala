#!/bin/zsh
# Builds Nano in Release and installs it to /Applications for daily use.
# Debug builds from Xcode run as "Nano Dev" (com.joshoettinger.nano.dev) with separate data.
set -euo pipefail
cd "${0:A:h}/.."

xcodegen generate --quiet
xcodebuild -project Nano.xcodeproj -scheme Nano -configuration Release \
  -derivedDataPath build/release -quiet build

app="build/release/Build/Products/Release/Nano.app"
osascript -e 'quit app id "com.joshoettinger.nano"' 2>/dev/null || true
rm -rf /Applications/Nano.app
cp -R "$app" /Applications/Nano.app
echo "Installed /Applications/Nano.app"
