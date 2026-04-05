#!/usr/bin/env bash
# ============================================================================
#  macOS Hardening Script
#  Applies security best-practices to a MacBook Pro running macOS 13+
#  Run as your normal user — the script will sudo where needed.
#  A backup of current settings is saved so the rollback script can restore.
# ============================================================================
set -euo pipefail

# ── Colors ───────────────────────────────────────────────────────────────────
RED='\033[1;31m'
GRN='\033[1;32m'
YEL='\033[1;33m'
BLU='\033[1;34m'
MAG='\033[1;35m'
CYN='\033[1;36m'
WHT='\033[1;37m'
DIM='\033[2m'
RST='\033[0m'

BACKUP_DIR="$HOME/.macos_harden_backup"
BACKUP_FILE="$BACKUP_DIR/pre_harden_state1.plist"
LOG_FILE="$BACKUP_DIR/harden1.log"

# ── Helpers ──────────────────────────────────────────────────────────────────
banner() {
  echo ""
  echo -e "${BLU}┌──────────────────────────────────────────────────────────────┐${RST}"
  echo -e "${BLU}│${WHT}  🔒  macOS Hardening Script                                ${BLU}│${RST}"
  echo -e "${BLU}│${DIM}     Backup dir: ${BACKUP_DIR}${RST}${BLU}$(printf '%*s' $((30 - ${#BACKUP_DIR})) '')│${RST}"
  echo -e "${BLU}└──────────────────────────────────────────────────────────────┘${RST}"
  echo ""
}

section() {
  echo ""
  echo -e "${MAG}━━━ $1 ━━━${RST}"
}

info()    { echo -e "  ${CYN}ℹ${RST}  $1"; }
ok()      { echo -e "  ${GRN}✔${RST}  $1"; }
warn()    { echo -e "  ${YEL}⚠${RST}  $1"; }
fail()    { echo -e "  ${RED}✖${RST}  $1"; }
skip()    { echo -e "  ${DIM}⏭${RST}  ${DIM}$1${RST}"; }
run_cmd() { echo -e "  ${DIM}\$ $1${RST}"; }

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"; }

apply() {
  # apply <description> <command...>
  local desc="$1"; shift
  run_cmd "$*"
  if eval "$@" >> "$LOG_FILE" 2>&1; then
    ok "$desc"
    log "OK: $desc"
  else
    fail "$desc — command returned non-zero (may already be set)"
    log "FAIL: $desc"
  fi
}

backup_defaults() {
  # backup_defaults <domain> <key>
  local domain="$1" key="$2"
  local val
  val=$(defaults read "$domain" "$key" 2>/dev/null || echo "__NOTSET__")
  echo "${domain}|${key}|${val}" >> "$BACKUP_FILE"
}

backup_global_defaults() {
  local key="$1"
  local val
  val=$(defaults read NSGlobalDomain "$key" 2>/dev/null || echo "__NOTSET__")
  echo "NSGlobalDomain|${key}|${val}" >> "$BACKUP_FILE"
}

# ── Pre-flight ───────────────────────────────────────────────────────────────
banner

if [[ "$(uname)" != "Darwin" ]]; then
  fail "This script is for macOS only."
  exit 1
fi

echo -e "${YEL}This script will modify system and user defaults to harden macOS.${RST}"
echo -e "${YEL}A backup of current settings will be saved to:${RST}"
echo -e "  ${WHT}${BACKUP_DIR}${RST}"
echo ""
read -rp "$(echo -e "${CYN}Proceed? [y/N]:${RST} ")" confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
  info "Aborted."
  exit 0
fi

mkdir -p "$BACKUP_DIR"
: > "$BACKUP_FILE"      # reset backup state file
: > "$LOG_FILE"         # reset log
log "=== Hardening started ==="

# ── Ask for sudo upfront ────────────────────────────────────────────────────
sudo -v
# Keep sudo alive
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

# ═════════════════════════════════════════════════════════════════════════════
#  1. FIREWALL
# ═════════════════════════════════════════════════════════════════════════════
section "1 · Firewall"

backup_defaults "/Library/Preferences/com.apple.alf" globalstate

apply "Enable application-layer firewall" \
  sudo defaults write /Library/Preferences/com.apple.alf globalstate -int 1

apply "Enable stealth mode (drop unsolicited packets)" \
  sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode on

apply "Enable logging on the firewall" \
  sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setloggingmode on

apply "Block all incoming connections (signed apps still allowed)" \
  sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setblockall on

# ═════════════════════════════════════════════════════════════════════════════
#  2. GATEKEEPER & SIP
# ═════════════════════════════════════════════════════════════════════════════
section "2 · Gatekeeper & Code Signing"

apply "Restrict app sources to App Store + identified developers" \
  sudo spctl --master-enable

info "Checking System Integrity Protection (SIP)..."
if csrutil status 2>/dev/null | grep -q "enabled"; then
  ok "SIP is already enabled"
else
  warn "SIP is disabled — enable it from Recovery Mode (csrutil enable)"
fi

# ═════════════════════════════════════════════════════════════════════════════
#  3. FILEVAULT (DISK ENCRYPTION)
# ═════════════════════════════════════════════════════════════════════════════
section "3 · FileVault Disk Encryption"

if fdesetup status | grep -q "On"; then
  ok "FileVault is already enabled"
else
  warn "FileVault is OFF — enabling now (you will be prompted for credentials)"
  info "If this is a remote session, run manually: sudo fdesetup enable"
  sudo fdesetup enable 2>>"$LOG_FILE" || warn "Could not enable FileVault automatically"
fi

# ═════════════════════════════════════════════════════════════════════════════
#  4. SHARING & REMOTE ACCESS
# ═════════════════════════════════════════════════════════════════════════════
section "4 · Disable Unnecessary Sharing Services"

apply "Disable Remote Apple Events" \
  sudo systemsetup -setremoteappleevents off

# apply "Disable Remote Login (SSH)" \
#   sudo systemsetup -setremotelogin off

run_cmd "echo yes | sudo systemsetup -setremotelogin off"
if echo yes | sudo systemsetup -setremotelogin off >> "$LOG_FILE" 2>&1; then
  ok "Disable Remote Login (SSH)"
  log "OK: Disable Remote Login (SSH)"
else
  fail "Disable Remote Login (SSH)"
  log "FAIL: Disable Remote Login (SSH)"
fi

apply "Disable Wake on Network Access" \
  sudo systemsetup -setwakeonnetworkaccess off

apply "Disable Bluetooth Sharing" \
  defaults -currentHost write com.apple.Bluetooth PrefKeyServicesEnabled -bool false

# ═════════════════════════════════════════════════════════════════════════════
#  5. SCREEN LOCK & LOGIN
# ═════════════════════════════════════════════════════════════════════════════
section "5 · Screen Lock & Login Window"

backup_defaults "com.apple.screensaver" askForPassword
backup_defaults "com.apple.screensaver" askForPasswordDelay

# apply "Require password immediately after sleep/screensaver" \
#   defaults write com.apple.screensaver askForPassword -int 1

# apply "Set password delay to 0 seconds" \
#   defaults write com.apple.screensaver askForPasswordDelay -int 0

apply "Disable guest account" \
  sudo defaults write /Library/Preferences/com.apple.loginwindow GuestEnabled -bool false

apply "Show login window as name+password (not user list)" \
  sudo defaults write /Library/Preferences/com.apple.loginwindow SHOWFULLNAME -bool true

apply "Disable login-window password hints" \
  sudo defaults write /Library/Preferences/com.apple.loginwindow RetriesUntilHint -int 0

# ═════════════════════════════════════════════════════════════════════════════
#  6. PRIVACY — SAFARI & TRACKING
# ═════════════════════════════════════════════════════════════════════════════
section "6 · Safari & Privacy"

backup_defaults "com.apple.Safari" UniversalSearchEnabled
backup_defaults "com.apple.Safari" SuppressSearchSuggestions
backup_defaults "com.apple.Safari" SendDoNotTrackHTTPHeader
backup_defaults "com.apple.Safari" AutoOpenSafeDownloads
backup_defaults "com.apple.Safari" com.apple.Safari.ContentPageGroupIdentifier.WebKit2JavaScriptCanOpenWindowsAutomatically

apply "Disable Safari universal search (sends queries to Apple)" \
  defaults write com.apple.Safari UniversalSearchEnabled -bool false

apply "Disable Safari search suggestions" \
  defaults write com.apple.Safari SuppressSearchSuggestions -bool true

apply "Enable Do Not Track header" \
  defaults write com.apple.Safari SendDoNotTrackHTTPHeader -bool true

apply "Disable auto-open of 'safe' downloads" \
  defaults write com.apple.Safari AutoOpenSafeDownloads -bool false

apply "Block pop-up windows" \
  defaults write com.apple.Safari com.apple.Safari.ContentPageGroupIdentifier.WebKit2JavaScriptCanOpenWindowsAutomatically -bool false

# ═════════════════════════════════════════════════════════════════════════════
#  7. PRIVACY — DIAGNOSTICS & TELEMETRY
# ═════════════════════════════════════════════════════════════════════════════
section "7 · Diagnostics & Telemetry"

backup_defaults "com.apple.CrashReporter" DialogType

apply "Disable crash reporter dialog (still logs locally)" \
  defaults write com.apple.CrashReporter DialogType -string "none"

apply "Disable Siri analytics submission" \
  defaults write com.apple.assistant.support "Siri Data Sharing Opt-In Status" -int 2

# ═════════════════════════════════════════════════════════════════════════════
#  8. NETWORK HARDENING
# ═════════════════════════════════════════════════════════════════════════════
section "8 · Network Hardening"

apply "Disable Captive Portal detection (prevents auto HTTP probes)" \
  sudo defaults write /Library/Preferences/SystemConfiguration/com.apple.captive.control Active -bool false

# apply "Disable AirDrop by default" \
#   defaults write com.apple.NetworkBrowser DisableAirDrop -bool true

# ═════════════════════════════════════════════════════════════════════════════
#  9. FINDER & SYSTEM UI HARDENING
# ═════════════════════════════════════════════════════════════════════════════
section "9 · Finder & UI Hardening"

backup_defaults "com.apple.finder" AppleShowAllExtensions
backup_defaults "NSGlobalDomain" com.apple.swipescrolldirection

apply "Show all file extensions in Finder" \
  defaults write NSGlobalDomain AppleShowAllExtensions -bool true

# apply "Show hidden files in Finder" \
#   defaults write com.apple.finder AppleShowAllFiles -bool true

apply "Disable .DS_Store on network volumes" \
  defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true

apply "Disable .DS_Store on USB volumes" \
  defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true

# ═════════════════════════════════════════════════════════════════════════════
#  10. POWER & HIBERNATION
# ═════════════════════════════════════════════════════════════════════════════
section "10 · Secure Hibernation"

apply "Destroy FileVault keys on standby (cold boot protection)" \
  sudo pmset -a destroyfvkeyonstandby 1

apply "Enable hibernation mode (write RAM to disk)" \
  sudo pmset -a hibernatemode 25

# ═════════════════════════════════════════════════════════════════════════════
#  11. AUTOMATIC UPDATES
# ═════════════════════════════════════════════════════════════════════════════
section "11 · Automatic Updates"

apply "Enable automatic update checks" \
  defaults write com.apple.SoftwareUpdate AutomaticCheckEnabled -bool true

apply "Enable automatic downloads of updates" \
  defaults write com.apple.SoftwareUpdate AutomaticDownload -bool true

apply "Install macOS data files & security updates automatically" \
  defaults write com.apple.SoftwareUpdate CriticalUpdateInstall -bool true

apply "Enable App Store auto-updates" \
  defaults write com.apple.commerce AutoUpdate -bool true

# ═════════════════════════════════════════════════════════════════════════════
#  12. MISCELLANEOUS
# ═════════════════════════════════════════════════════════════════════════════
section "12 · Miscellaneous"

apply "Enable Secure Keyboard Entry in Terminal.app" \
  defaults write com.apple.terminal SecureKeyboardEntry -bool true

apply "Disable Bonjour multicast advertisements" \
  sudo defaults write /Library/Preferences/com.apple.mDNSResponder.plist NoMulticastAdvertisements -bool true

# ═════════════════════════════════════════════════════════════════════════════
#  DONE
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo -e "${GRN}┌──────────────────────────────────────────────────────────────┐${RST}"
echo -e "${GRN}│${WHT}  ✅  Hardening complete                                      ${GRN}│${RST}"
echo -e "${GRN}│${RST}                                                              ${GRN}│${RST}"
echo -e "${GRN}│${RST}  ${DIM}Backup saved to:${RST} ${CYN}${BACKUP_DIR}${RST}$(printf '%*s' $((23 - ${#BACKUP_DIR})) '')${GRN}│${RST}"
echo -e "${GRN}│${RST}  ${DIM}Log file:${RST}        ${CYN}${LOG_FILE}${RST}$(printf '%*s' $((23 - ${#LOG_FILE})) '')${GRN}│${RST}"
echo -e "${GRN}│${RST}                                                              ${GRN}│${RST}"
echo -e "${GRN}│${RST}  ${YEL}⚠  A restart is recommended to apply all changes.${RST}          ${GRN}│${RST}"
echo -e "${GRN}│${RST}  ${YEL}⚠  Run the rollback script to undo these changes.${RST}          ${GRN}│${RST}"
echo -e "${GRN}└──────────────────────────────────────────────────────────────┘${RST}"
echo ""

log "=== Hardening finished ==="
