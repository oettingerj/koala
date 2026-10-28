#!/bin/zsh
# Builds Koala in Release and installs it to /Applications for daily use.
# Debug builds from Xcode run as "Koala Dev" (com.joshoettinger.koala.dev) with separate data.
set -euo pipefail
cd "${0:A:h}/.."

xcodegen generate --quiet
xcodebuild -project Koala.xcodeproj -scheme Koala -configuration Release \
  -derivedDataPath build/release -quiet build

app="build/release/Build/Products/Release/Koala.app"
osascript -e 'quit app id "com.joshoettinger.koala"' 2>/dev/null || true
# quit returns before Koala and WebKit's network process finish writing cookies and storage.
# Replacing the app mid-write leaves stale cookies, and sites like YouTube then sign out.
busy() {
  pgrep -qf '^/Applications/Koala.app/' ||
    [[ -n "$(lsof -t +D ~/Library/HTTPStorages/com.joshoettinger.koala +D ~/Library/WebKit/com.joshoettinger.koala 2>/dev/null)" ]]
}
for _ in {1..100}; do busy || break; sleep 0.1; done
if busy; then
  echo "Koala or its web content is still running; quit it and run this again." >&2
  exit 1
fi
rm -rf /Applications/Koala.app
cp -R "$app" /Applications/Koala.app
echo "Installed /Applications/Koala.app"
