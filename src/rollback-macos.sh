#!/usr/bin/env bash
# ============================================================================
#  macOS Hardening Rollback Script
#  Reverts the changes made by harden-macos.sh
#  Restores backed-up defaults and re-enables disabled services.
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
BACKUP_FILE="$BACKUP_DIR/pre_harden_state.plist"
LOG_FILE="$BACKUP_DIR/rollback.log"

# ── Helpers ──────────────────────────────────────────────────────────────────
banner() {
  echo ""
  echo -e "${RED}┌──────────────────────────────────────────────────────────────┐${RST}"
  echo -e "${RED}│${WHT}  🔓  macOS Hardening — ROLLBACK                              ${RED}│${RST}"
  echo -e "${RED}│${DIM}     This will undo the hardening changes.                   ${RST}${RED}│${RST}"
  echo -e "${RED}└──────────────────────────────────────────────────────────────┘${RST}"
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
run_cmd() { echo -e "  ${DIM}\$ $1${RST}"; }

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"; }

revert() {
  local desc="$1"; shift
  run_cmd "$*"
  if "$@" >> "$LOG_FILE" 2>&1; then
    ok "$desc"
    log "OK: $desc"
  else
    fail "$desc — command returned non-zero"
    log "FAIL: $desc"
  fi
}

# ── Restore a backed-up defaults value ───────────────────────────────────────
restore_default() {
  local domain="$1" key="$2"
  if [[ ! -f "$BACKUP_FILE" ]]; then return; fi
  local line val
  line=$(grep "^${domain}|${key}|" "$BACKUP_FILE" 2>/dev/null || true)
  if [[ -z "$line" ]]; then return; fi
  val="${line#*|*|}"
  if [[ "$val" == "__NOTSET__" ]]; then
    defaults delete "$domain" "$key" 2>/dev/null || true
    info "Restored ${DIM}${domain} ${key}${RST} → ${YEL}(deleted / factory default)${RST}"
  else
    defaults write "$domain" "$key" "$val" 2>/dev/null || true
    info "Restored ${DIM}${domain} ${key}${RST} → ${CYN}${val}${RST}"
  fi
}

# ── Pre-flight ───────────────────────────────────────────────────────────────
banner

if [[ "$(uname)" != "Darwin" ]]; then
  fail "This script is for macOS only."
  exit 1
fi

echo -e "${YEL}This will revert firewall, sharing, privacy, and other hardening${RST}"
echo -e "${YEL}changes back to macOS defaults (or your pre-hardening state).${RST}"
echo ""
read -rp "$(echo -e "${RED}Are you sure? [y/N]:${RST} ")" confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
  info "Aborted."
  exit 0
fi

mkdir -p "$BACKUP_DIR"
: > "$LOG_FILE"
log "=== Rollback started ==="

sudo -v
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

# ═════════════════════════════════════════════════════════════════════════════
#  1. FIREWALL
# ═════════════════════════════════════════════════════════════════════════════
section "1 · Firewall → Relax"

revert "Disable stealth mode" \
  sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode off

revert "Disable firewall logging" \
  sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setloggingmode off

revert "Allow incoming connections" \
  sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setblockall off

info "Note: Firewall itself left ON — disable manually in System Settings if desired."

# ═════════════════════════════════════════════════════════════════════════════
#  2. GATEKEEPER
# ═════════════════════════════════════════════════════════════════════════════
section "2 · Gatekeeper"

info "Gatekeeper left enabled (Apple default). No rollback needed."

# ═════════════════════════════════════════════════════════════════════════════
#  3. FILEVAULT
# ═════════════════════════════════════════════════════════════════════════════
section "3 · FileVault"

warn "FileVault is NOT automatically disabled by rollback (data protection)."
info "To disable: System Settings → Privacy & Security → FileVault → Turn Off"

# ═════════════════════════════════════════════════════════════════════════════
#  4. SHARING & REMOTE ACCESS (FIXED)
# ═════════════════════════════════════════════════════════════════════════════
section "4 · Sharing Services → Default-safe"

# 🚫 macOS default: OFF → DO NOT enable
# revert "Re-enable Remote Apple Events" \
#   sudo systemsetup -setremoteappleevents on

info "Remote Apple Events left OFF (default macOS)"

# 🚫 macOS default: OFF → DO NOT enable SSH
# revert "Re-enable Remote Login (SSH)" \
#   sudo systemsetup -setremotelogin on

info "Remote Login (SSH) left OFF (default macOS)"

# ⚠️ Wake-on-LAN is usually ON by default → safe to restore
revert "Re-enable Wake on Network Access" \
  sudo systemsetup -setwakeonnetworkaccess on

# ⚠️ Bluetooth sharing varies, but enabling is fine
revert "Re-enable Bluetooth Sharing" \
  defaults -currentHost write com.apple.Bluetooth PrefKeyServicesEnabled -bool true

# ═════════════════════════════════════════════════════════════════════════════
#  5. SCREEN LOCK & LOGIN
# ═════════════════════════════════════════════════════════════════════════════
section "5 · Screen Lock & Login Window → Relax"

restore_default "com.apple.screensaver" askForPassword
restore_default "com.apple.screensaver" askForPasswordDelay

# 🚫 Default macOS: Guest OFF
# revert "Re-enable guest account" \
#   sudo defaults write /Library/Preferences/com.apple.loginwindow GuestEnabled -bool true

info "Guest account left DISABLED (default macOS)"

revert "Show user list at login (not name+password)" \
  sudo defaults write /Library/Preferences/com.apple.loginwindow SHOWFULLNAME -bool false

revert "Restore password hints" \
  sudo defaults delete /Library/Preferences/com.apple.loginwindow RetriesUntilHint

# ═════════════════════════════════════════════════════════════════════════════
#  6. SAFARI & PRIVACY
# ═════════════════════════════════════════════════════════════════════════════
section "6 · Safari & Privacy → Relax"

restore_default "com.apple.Safari" UniversalSearchEnabled
restore_default "com.apple.Safari" SuppressSearchSuggestions
restore_default "com.apple.Safari" SendDoNotTrackHTTPHeader
restore_default "com.apple.Safari" AutoOpenSafeDownloads
restore_default "com.apple.Safari" com.apple.Safari.ContentPageGroupIdentifier.WebKit2JavaScriptCanOpenWindowsAutomatically

# ═════════════════════════════════════════════════════════════════════════════
#  7. DIAGNOSTICS & TELEMETRY
# ═════════════════════════════════════════════════════════════════════════════
section "7 · Diagnostics → Restore"

restore_default "com.apple.CrashReporter" DialogType

revert "Re-enable Siri analytics" \
  defaults write com.apple.assistant.support "Siri Data Sharing Opt-In Status" -int 0

# ═════════════════════════════════════════════════════════════════════════════
#  8. NETWORK
# ═════════════════════════════════════════════════════════════════════════════
section "8 · Network → Relax"

revert "Re-enable Captive Portal detection" \
  sudo defaults write /Library/Preferences/SystemConfiguration/com.apple.captive.control Active -bool true

revert "Re-enable AirDrop" \
  defaults write com.apple.NetworkBrowser DisableAirDrop -bool false

# ═════════════════════════════════════════════════════════════════════════════
#  9. FINDER & UI
# ═════════════════════════════════════════════════════════════════════════════
section "9 · Finder → Restore"

revert "Hide file extensions (macOS default)" \
  defaults write NSGlobalDomain AppleShowAllExtensions -bool false

revert "Hide hidden files" \
  defaults write com.apple.finder AppleShowAllFiles -bool false

revert "Allow .DS_Store on network volumes" \
  defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool false

revert "Allow .DS_Store on USB volumes" \
  defaults write com.apple.desktopservices DSDontWriteUSBStores -bool false

# ═════════════════════════════════════════════════════════════════════════════
#  10. POWER & HIBERNATION
# ═════════════════════════════════════════════════════════════════════════════
section "10 · Power → Restore Defaults"

revert "Disable FileVault key destruction on standby" \
  sudo pmset -a destroyfvkeyonstandby 0

revert "Restore default hibernation mode (suspend to RAM)" \
  sudo pmset -a hibernatemode 3

# ═════════════════════════════════════════════════════════════════════════════
#  11. AUTOMATIC UPDATES (left enabled — generally you want these)
# ═════════════════════════════════════════════════════════════════════════════
section "11 · Automatic Updates"

info "Auto-updates left enabled (keeping your Mac patched is always a good idea)."

# ═════════════════════════════════════════════════════════════════════════════
#  12. MISCELLANEOUS
# ═════════════════════════════════════════════════════════════════════════════
section "12 · Miscellaneous → Restore"

revert "Disable Secure Keyboard Entry in Terminal" \
  defaults write com.apple.terminal SecureKeyboardEntry -bool false

revert "Re-enable Bonjour multicast advertisements" \
  sudo defaults write /Library/Preferences/com.apple.mDNSResponder.plist NoMulticastAdvertisements -bool false

# ═════════════════════════════════════════════════════════════════════════════
#  DONE
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo -e "${YEL}┌──────────────────────────────────────────────────────────────┐${RST}"
echo -e "${YEL}│${WHT}  🔓  Rollback complete                                       ${YEL}│${RST}"
echo -e "${YEL}│${RST}                                                              ${YEL}│${RST}"
echo -e "${YEL}│${RST}  ${DIM}Log file:${RST} ${CYN}${LOG_FILE}${RST}$(printf '%*s' $((30 - ${#LOG_FILE})) '')${YEL}│${RST}"
echo -e "${YEL}│${RST}                                                              ${YEL}│${RST}"
echo -e "${YEL}│${RST}  ${GRN}✔${RST}  Firewall relaxed (stealth off, block-all off)             ${YEL}│${RST}"
echo -e "${YEL}│${RST}  ${GRN}✔${RST}  Sharing services re-enabled                               ${YEL}│${RST}"
echo -e "${YEL}│${RST}  ${GRN}✔${RST}  Login & screensaver settings restored                     ${YEL}│${RST}"
echo -e "${YEL}│${RST}  ${GRN}✔${RST}  Safari & privacy defaults restored                        ${YEL}│${RST}"
echo -e "${YEL}│${RST}  ${GRN}✔${RST}  Network, Finder, power settings restored                  ${YEL}│${RST}"
echo -e "${YEL}│${RST}  ${DIM}⏭${RST}  FileVault & Gatekeeper unchanged (manual if needed)       ${YEL}│${RST}"
echo -e "${YEL}│${RST}                                                              ${YEL}│${RST}"
echo -e "${YEL}│${RST}  ${RED}⚠  A restart is recommended to apply all changes.${RST}          ${YEL}│${RST}"
echo -e "${YEL}└──────────────────────────────────────────────────────────────┘${RST}"
echo ""

log "=== Rollback finished ==="
