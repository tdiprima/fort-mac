#!/bin/bash

# AirDrop Doctor++ (symmetrical + color + auto visibility revert)

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

function log() {
    echo -e "${BLUE}[*]${NC} $1"
}

function success() {
    echo -e "${GREEN}[+]${NC} $1"
}

function warn() {
    echo -e "${YELLOW}[!]${NC} $1"
}

function usage() {
    echo -e "${YELLOW}Usage:${NC} $0 [1|2]"
    echo "  1 = Enable + fix AirDrop"
    echo "  2 = Disable + harden system"
    exit 1
}

if [[ "$1" != "1" && "$1" != "2" ]]; then
    usage
fi

# Detect Wi-Fi device once
WIFI_DEVICE=$(networksetup -listallhardwareports | awk '/Wi-Fi/{getline; print $2}')

if [[ "$1" == "1" ]]; then
    log "Enabling AirDrop + fixing common issues..."

    # Enable AirDrop
    defaults write com.apple.NetworkBrowser DisableAirDrop -bool false
    success "AirDrop enabled"

    # Firewall: allow inbound (not block-all)
    log "Adjusting firewall (disabling block-all)..."
    sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setblockall off
    success "Firewall ready"

    # Enable multicast (mDNS)
    log "Re-enabling multicast advertisements..."
    sudo defaults write /Library/Preferences/com.apple.mDNSResponder.plist NoMulticastAdvertisements -bool false
    sudo killall mDNSResponder || true
    success "mDNS enabled"

    # Wi-Fi ON
    if [[ -n "$WIFI_DEVICE" ]]; then
        log "Turning Wi-Fi ON ($WIFI_DEVICE)..."
        networksetup -setairportpower "$WIFI_DEVICE" on
        success "Wi-Fi enabled"
    else
        warn "Wi-Fi device not found"
    fi

    # Bluetooth ON
    log "Turning Bluetooth ON..."
    defaults write /Library/Preferences/com.apple.Bluetooth ControllerPowerState -int 1
    sudo killall -HUP blued || true
    success "Bluetooth enabled"

    # AirDrop visibility: Everyone
    log "Setting AirDrop visibility to Everyone..."
    defaults write com.apple.sharingd DiscoverableMode -string "Everyone"
    killall sharingd || true
    success "Visibility set to Everyone"

    # Auto-revert visibility after 10 min
    log "Scheduling visibility revert to Contacts Only in 10 minutes..."
    (
        sleep 600
        defaults write com.apple.sharingd DiscoverableMode -string "Contacts Only"
        killall sharingd || true
        echo -e "${YELLOW}[!] AirDrop visibility reverted to Contacts Only${NC}"
    ) &

    # Restart Finder
    log "Restarting Finder..."
    killall Finder

    success "AirDrop fully operational 🚀"

elif [[ "$1" == "2" ]]; then
    log "Disabling AirDrop + hardening system..."

    # Disable AirDrop
    defaults write com.apple.NetworkBrowser DisableAirDrop -bool true
    success "AirDrop disabled"

    # Firewall: block all incoming
    log "Enabling firewall block-all mode..."
    sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setblockall on
    success "Firewall hardened"

    # Disable multicast (mDNS)
    log "Disabling multicast advertisements..."
    sudo defaults write /Library/Preferences/com.apple.mDNSResponder.plist NoMulticastAdvertisements -bool true
    sudo killall mDNSResponder || true
    success "mDNS hardened"

    # Wi-Fi OFF
    if [[ -n "$WIFI_DEVICE" ]]; then
        log "Turning Wi-Fi OFF ($WIFI_DEVICE)..."
        networksetup -setairportpower "$WIFI_DEVICE" off
        success "Wi-Fi disabled"
    fi

    # Bluetooth OFF
    log "Turning Bluetooth OFF..."
    defaults write /Library/Preferences/com.apple.Bluetooth ControllerPowerState -int 0
    sudo killall -HUP blued || true
    success "Bluetooth disabled"

    # AirDrop visibility: No One
    log "Setting AirDrop visibility to No One..."
    defaults write com.apple.sharingd DiscoverableMode -string "Off"
    killall sharingd || true
    success "Visibility locked down"

    # Restart Finder
    log "Restarting Finder..."
    killall Finder

    success "System hardened 🔒"
fi