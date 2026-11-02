#!/bin/sh
# Build YabaiTab, install it to /Applications and start it now and at every login (LaunchAgent).
set -eu
cd "$(dirname "$0")"
./build.sh
AGENT="$HOME/Library/LaunchAgents/org.wenyuan.yabaitab.plist"
launchctl bootout "gui/$(id -u)" "$AGENT" 2>/dev/null || true
pkill -x YabaiTab || true
rm -rf /Applications/YabaiTab.app
ditto build/YabaiTab.app /Applications/YabaiTab.app
cp org.wenyuan.yabaitab.plist "$AGENT"
launchctl bootstrap "gui/$(id -u)" "$AGENT"
echo "installed /Applications/YabaiTab.app, running at login"
