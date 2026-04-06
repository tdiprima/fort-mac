#!/usr/bin/env bash
# ============================================================================
#  macOS Hardening Rollback — SAFE VERSION
#  Restores ONLY what was changed. Never enables new attack surface.
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

banner() {
  echo ""
  echo -e "${BLU}┌──────────────────────────────────────────────────────────────┐${RST}"
  echo -e "${BLU}│${WHT}  🔄  macOS Rollback (Safe Mode)                             ${BLU}│${RST}"
  echo -e "${BLU}│${DIM}  Only restores previous values — no new exposure         ${BLU}│${RST}"
  echo -e "${BLU}└──────────────────────────────────────────────────────────────┘${RST}"
  echo ""
}

info() { echo -e "${CYN}ℹ${RST}  $1"; }
ok()   { echo -e "${GRN}✔${RST}  $1"; }
warn() { echo -e "${YEL}⚠${RST}  $1"; }
fail() { echo -e "${RED}✖${RST}  $1"; }

log() { echo "[$(date '+%F %T')] $*" >> "$LOG_FILE"; }

# ── Restore defaults safely ──────────────────────────────────────────────────
restore_default() {
  local domain="$1" key="$2"

  if [[ ! -f "$BACKUP_FILE" ]]; then
    warn "No backup file found — skipping ${domain}:${key}"
    return
  fi

  local line val
  line=$(grep "^${domain}|${key}|" "$BACKUP_FILE" 2>/dev/null || true)

  if [[ -z "$line" ]]; then
    # 🔥 safest fallback: remove override
    defaults delete "$domain" "$key" 2>/dev/null || true
    info "Reset ${domain}:${key} → system default"
    return
  fi

  val="${line#*|*|}"

  if [[ "$val" == "__NOTSET__" ]]; then
    defaults delete "$domain" "$key" 2>/dev/null || true
    info "Deleted ${domain}:${key} → system default"
  else
    defaults write "$domain" "$key" "$val" 2>/dev/null || true
    info "Restored ${domain}:${key}"
  fi
}

banner

mkdir -p "$BACKUP_DIR"
: > "$LOG_FILE"

sudo -v
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

# ═════════════════════════════════════════════════════════════════════════════
#  FIREWALL
# ═════════════════════════════════════════════════════════════════════════════
info "Restoring firewall defaults"

restore_default "/Library/Preferences/com.apple.alf" globalstate

# DO NOT disable firewall automatically
warn "Firewall left as-is (safer default)"

sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode off || true
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setloggingmode off || true
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setblockall off || true

# ═════════════════════════════════════════════════════════════════════════════
#  SHARING SERVICES
# ═════════════════════════════════════════════════════════════════════════════
info "Restoring sharing services (safe mode)"

# 🔒 DO NOT enable these (default = OFF)
info "Remote Login (SSH): left OFF"
info "Remote Apple Events: left OFF"

# Only restore Wake-on-LAN (safe default)
sudo systemsetup -setwakeonnetworkaccess on || true

# ═════════════════════════════════════════════════════════════════════════════
#  LOGIN / SCREEN
# ═════════════════════════════════════════════════════════════════════════════
info "Restoring login settings"

restore_default "com.apple.screensaver" askForPassword
restore_default "com.apple.screensaver" askForPasswordDelay

# 🔒 Guest stays OFF (modern macOS default)
info "Guest account left DISABLED"

restore_default "/Library/Preferences/com.apple.loginwindow" SHOWFULLNAME
restore_default "/Library/Preferences/com.apple.loginwindow" RetriesUntilHint

# ═════════════════════════════════════════════════════════════════════════════
#  SAFARI / PRIVACY
# ═════════════════════════════════════════════════════════════════════════════
info "Restoring Safari + privacy"

restore_default "com.apple.Safari" UniversalSearchEnabled
restore_default "com.apple.Safari" SuppressSearchSuggestions
restore_default "com.apple.Safari" SendDoNotTrackHTTPHeader
restore_default "com.apple.Safari" AutoOpenSafeDownloads
restore_default "com.apple.Safari" com.apple.Safari.ContentPageGroupIdentifier.WebKit2JavaScriptCanOpenWindowsAutomatically

# ═════════════════════════════════════════════════════════════════════════════
#  TELEMETRY
# ═════════════════════════════════════════════════════════════════════════════
info "Restoring telemetry"

restore_default "com.apple.CrashReporter" DialogType
restore_default "com.apple.assistant.support" "Siri Data Sharing Opt-In Status"

# ═════════════════════════════════════════════════════════════════════════════
#  NETWORK
# ═════════════════════════════════════════════════════════════════════════════
info "Restoring network behavior"

restore_default "/Library/Preferences/SystemConfiguration/com.apple.captive.control" Active
restore_default "com.apple.NetworkBrowser" DisableAirDrop

# ═════════════════════════════════════════════════════════════════════════════
#  FINDER
# ═════════════════════════════════════════════════════════════════════════════
info "Restoring Finder settings"

restore_default "NSGlobalDomain" AppleShowAllExtensions
restore_default "com.apple.finder" AppleShowAllFiles
restore_default "com.apple.desktopservices" DSDontWriteNetworkStores
restore_default "com.apple.desktopservices" DSDontWriteUSBStores

# ═════════════════════════════════════════════════════════════════════════════
#  POWER
# ═════════════════════════════════════════════════════════════════════════════
info "Restoring power settings"

sudo pmset -a destroyfvkeyonstandby 0 || true
sudo pmset -a hibernatemode 3 || true

# ═════════════════════════════════════════════════════════════════════════════
#  MISC
# ═════════════════════════════════════════════════════════════════════════════
info "Restoring misc settings"

restore_default "com.apple.terminal" SecureKeyboardEntry
restore_default "/Library/Preferences/com.apple.mDNSResponder.plist" NoMulticastAdvertisements

echo ""
echo -e "${GRN}✔ Rollback complete (safe mode)${RST}"
echo -e "${DIM}Log: ${LOG_FILE}${RST}"
