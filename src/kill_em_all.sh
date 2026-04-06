#!/bin/bash

# kill anything watchdog
pkill -f watchdog
pkill -f "log stream"

# remove launch agent
rm -f ~/Library/LaunchAgents/com.mac-watchdog.plist

# reset network basics
sudo defaults write /Library/Preferences/SystemConfiguration/com.apple.captive.control Active -bool true
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setblockall off

# flush DNS
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder
