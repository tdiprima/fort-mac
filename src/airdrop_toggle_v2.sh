#!/bin/bash

# AirDrop Doctor++ v2 (safe, idempotent, no Wi-Fi kill)

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

LOCK_FILE="/tmp/airdrop_visibility_revert.lock"

log() { echo -e "${BLUE}[*]${NC} $1"; }
success() { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }

usage() {
    echo -e "${YELLOW}Usage:${NC} $0 [1|2]"
    echo "  1 = Enable + fix AirDrop"
    echo "  2 = Disable + harden system"
    exit 1
}

[[ "$1" != "1" && "$1" != "2" ]] && usage

# Detect Wi-Fi device (for info only now)
WIFI_DEVICE=$(networksetup -listallhardwareports | awk '/Wi-Fi/{getline; print $2}')

# Helper: read defaults safely
get_default() {
    defaults read "$1" "$2" 2>/dev/null || echo "UNSET"
}

# Helper: set only if needed
set_default_bool() {
    local domain="$1"
    local key="$2"
    local desired="$3"
    local current
    current=$(get_default "$domain" "$key")

    if [[ "$current" != "$desired" ]]; then
        defaults write "$domain" "$key" -bool "$desired"
        success "$key set to $desired"
    else
        log "$key already $desired"
    fi
}

if [[ "$1" == "1" ]]; then
    log "Enabling AirDrop + fixing common issues..."

    # Enable AirDrop
    set_default_bool com.apple.NetworkBrowser DisableAirDrop false

    # Firewall: disable block-all if needed
    if /usr/libexec/ApplicationFirewall/socketfilterfw --getblockall | grep -q "enabled"; then
        log "Disabling firewall block-all..."
        sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setblockall off
        success "Firewall adjusted"
    else
        log "Firewall already not in block-all mode"
    fi

    # Enable multicast (mDNS)
    set_default_bool /Library/Preferences/com.apple.mDNSResponder.plist NoMulticastAdvertisements false
    sudo killall mDNSResponder || true
    success "mDNS ready"

    # Bluetooth ON (only if off)
    BT_STATE=$(defaults read /Library/Preferences/com.apple.Bluetooth ControllerPowerState 2>/dev/null || echo 1)
    if [[ "$BT_STATE" != "1" ]]; then
        log "Turning Bluetooth ON..."
        sudo defaults write /Library/Preferences/com.apple.Bluetooth ControllerPowerState -int 1
        sudo killall -HUP blued || true
        success "Bluetooth enabled"
    else
        log "Bluetooth already ON"
    fi

    # AirDrop visibility: Everyone
    CURRENT_VIS=$(get_default com.apple.sharingd DiscoverableMode)
    if [[ "$CURRENT_VIS" != "Everyone" ]]; then
        log "Setting AirDrop visibility to Everyone..."
        defaults write com.apple.sharingd DiscoverableMode -string "Everyone"
        killall sharingd || true
        success "Visibility set to Everyone"
    else
        log "Visibility already Everyone"
    fi

    # Prevent duplicate timers
    if [[ -f "$LOCK_FILE" ]]; then
        warn "Existing visibility timer detected — skipping new one"
    else
        log "Scheduling visibility revert (10 min)..."
        touch "$LOCK_FILE"
        (
            sleep 600
            defaults write com.apple.sharingd DiscoverableMode -string "Contacts Only"
            killall sharingd || true
            rm -f "$LOCK_FILE"
            echo -e "${YELLOW}[!] AirDrop visibility reverted to Contacts Only${NC}"
        ) &
        success "Revert timer set"
    fi

    # Restart Finder (only if running)
    if pgrep Finder >/dev/null; then
        log "Restarting Finder..."
        killall Finder
    fi

    success "AirDrop fully operational 🚀"

elif [[ "$1" == "2" ]]; then
    log "Disabling AirDrop + hardening system..."

    # Disable AirDrop
    set_default_bool com.apple.NetworkBrowser DisableAirDrop true

    # Firewall: enable block-all if not already
    if ! /usr/libexec/ApplicationFirewall/socketfilterfw --getblockall | grep -q "enabled"; then
        log "Enabling firewall block-all..."
        sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setblockall on
        success "Firewall hardened"
    else
        log "Firewall already in block-all mode"
    fi

    # Disable multicast
    set_default_bool /Library/Preferences/com.apple.mDNSResponder.plist NoMulticastAdvertisements true
    sudo killall mDNSResponder || true
    success "mDNS hardened"

    # Bluetooth OFF (only if on)
    BT_STATE=$(defaults read /Library/Preferences/com.apple.Bluetooth ControllerPowerState 2>/dev/null || echo 1)
    if [[ "$BT_STATE" != "0" ]]; then
        log "Turning Bluetooth OFF..."
        sudo defaults write /Library/Preferences/com.apple.Bluetooth ControllerPowerState -int 0
        sudo killall -HUP blued || true
        success "Bluetooth disabled"
    else
        log "Bluetooth already OFF"
    fi

    # AirDrop visibility: Off
    CURRENT_VIS=$(get_default com.apple.sharingd DiscoverableMode)
    if [[ "$CURRENT_VIS" != "Off" ]]; then
        log "Setting AirDrop visibility to Off..."
        defaults write com.apple.sharingd DiscoverableMode -string "Off"
        killall sharingd || true
        success "Visibility locked down"
    else
        log "Visibility already Off"
    fi

    # Clean up any timer
    if [[ -f "$LOCK_FILE" ]]; then
        rm -f "$LOCK_FILE"
        warn "Removed leftover visibility timer"
    fi

    # Restart Finder if needed
    if pgrep Finder >/dev/null; then
        log "Restarting Finder..."
        killall Finder
    fi

    success "System hardened 🔒"
fi
