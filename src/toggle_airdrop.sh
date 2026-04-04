#!/bin/bash

# Toggle AirDrop on macOS
# Usage: ./toggle_airdrop.sh [1|2]
# 1 = Enable AirDrop
# 2 = Disable AirDrop

if [[ "$1" != "1" && "$1" != "2" ]]; then
    echo "Usage: $0 [1|2]"
    echo "  1 = Enable AirDrop"
    echo "  2 = Disable AirDrop"
    exit 1
fi

if [[ "$1" == "1" ]]; then
    echo "Enabling AirDrop..."
    defaults write com.apple.NetworkBrowser DisableAirDrop -bool false

    echo "Ensuring firewall isn't blocking AirDrop..."
    sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setblockall off

elif [[ "$1" == "2" ]]; then
    echo "Disabling AirDrop..."
    defaults write com.apple.NetworkBrowser DisableAirDrop -bool true
    sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setblockall on
fi

# Restart Finder to apply changes
killall Finder

echo "Done."
