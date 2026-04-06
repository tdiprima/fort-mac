#!/usr/bin/env bash

BACKUP_DIR="$HOME/.macos_harden_backup"
BACKUP_FILE="$BACKUP_DIR/pre_harden_state.plist"

mkdir -p "$BACKUP_DIR"
: > "$BACKUP_FILE"

echo "[*] Rebuilding backup from current system defaults..."

backup() {
  local domain="$1"
  local key="$2"

  local val
  val=$(defaults read "$domain" "$key" 2>/dev/null || echo "__NOTSET__")

  echo "${domain}|${key}|${val}" >> "$BACKUP_FILE"
}

# Core settings from your hardening script
backup "/Library/Preferences/com.apple.alf" globalstate

backup "com.apple.screensaver" askForPassword
backup "com.apple.screensaver" askForPasswordDelay

backup "/Library/Preferences/com.apple.loginwindow" GuestEnabled
backup "/Library/Preferences/com.apple.loginwindow" SHOWFULLNAME
backup "/Library/Preferences/com.apple.loginwindow" RetriesUntilHint

backup "com.apple.Safari" UniversalSearchEnabled
backup "com.apple.Safari" SuppressSearchSuggestions
backup "com.apple.Safari" SendDoNotTrackHTTPHeader
backup "com.apple.Safari" AutoOpenSafeDownloads
backup "com.apple.Safari" com.apple.Safari.ContentPageGroupIdentifier.WebKit2JavaScriptCanOpenWindowsAutomatically

backup "com.apple.CrashReporter" DialogType
backup "com.apple.assistant.support" "Siri Data Sharing Opt-In Status"

backup "/Library/Preferences/SystemConfiguration/com.apple.captive.control" Active
backup "com.apple.NetworkBrowser" DisableAirDrop

backup "NSGlobalDomain" AppleShowAllExtensions
backup "com.apple.finder" AppleShowAllFiles
backup "com.apple.desktopservices" DSDontWriteNetworkStores
backup "com.apple.desktopservices" DSDontWriteUSBStores

backup "com.apple.terminal" SecureKeyboardEntry
backup "/Library/Preferences/com.apple.mDNSResponder.plist" NoMulticastAdvertisements

echo "[+] Backup rebuilt at $BACKUP_FILE"
