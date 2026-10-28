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
# quit returns before Nano and WebKit's network process finish writing cookies and storage.
# Replacing the app mid-write leaves stale cookies, and sites like YouTube then sign out.
busy() {
  pgrep -qf '^/Applications/Nano.app/' ||
    [[ -n "$(lsof -t +D ~/Library/HTTPStorages/com.joshoettinger.nano +D ~/Library/WebKit/com.joshoettinger.nano 2>/dev/null)" ]]
}
for _ in {1..100}; do busy || break; sleep 0.1; done
if busy; then
  echo "Nano or its web content is still running; quit it and run this again." >&2
  exit 1
fi
rm -rf /Applications/Nano.app
cp -R "$app" /Applications/Nano.app
echo "Installed /Applications/Nano.app"
