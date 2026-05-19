#!/usr/bin/env bash
set -euo pipefail

# kill anything watchdog
pkill -f watchdog || true
pkill -f "log stream" || true

# remove launch agent
rm -f ~/Library/LaunchAgents/com.mac-watchdog.plist

# reset network basics
sudo defaults write /Library/Preferences/SystemConfiguration/com.apple.captive.control Active -bool true
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setblockall off

# flush DNS
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder
