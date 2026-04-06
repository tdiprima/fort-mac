#!/usr/bin/env bash
# mac-watchdog.sh
# Lightweight macOS detection helper
# Watches for:
#   * suspicious new LaunchAgents / LaunchDaemons / LoginItems
#   * firewall / SSH / FileVault state drift
#   * selected unified-log security events
#   * optional desktop notifications
#
# Run as your normal user. Some checks will use sudo if available.

set -euo pipefail

# =========================
# Colors
# =========================
RED='\033[1;31m'
GRN='\033[1;32m'
YEL='\033[1;33m'
BLU='\033[1;34m'
MAG='\033[1;35m'
CYN='\033[1;36m'
WHT='\033[1;37m'
DIM='\033[2m'
RST='\033[0m'

# =========================
# Config
# =========================
APP_NAME="mac-watchdog"
BASE_DIR="${HOME}/.mac-watchdog"
STATE_DIR="${BASE_DIR}/state"
LOG_DIR="${BASE_DIR}/logs"
ALERT_LOG="${LOG_DIR}/alerts.log"
EVENT_LOG="${LOG_DIR}/events.log"
PID_DIR="${BASE_DIR}/pids"

ENABLE_NOTIFICATIONS=1
POLL_SECONDS=30

WATCH_PATHS=(
  "/Library/LaunchDaemons"
  "/Library/LaunchAgents"
  "${HOME}/Library/LaunchAgents"
  "/var/db/com.apple.xpc.launchd"
)

mkdir -p "${STATE_DIR}" "${LOG_DIR}" "${PID_DIR}"

# =========================
# Pretty output
# =========================
banner() {
  echo ""
  echo -e "${BLU}┌──────────────────────────────────────────────────────────────┐${RST}"
  echo -e "${BLU}│${WHT}  👀  mac-watchdog                                         ${BLU}│${RST}"
  echo -e "${BLU}│${DIM}  Logs: ${LOG_DIR}${RST}$(printf '%*s' $((48 - ${#LOG_DIR})) '')${BLU}│${RST}"
  echo -e "${BLU}└──────────────────────────────────────────────────────────────┘${RST}"
  echo ""
}

info()  { echo -e "${CYN}[INFO]${RST}  $*"; }
ok()    { echo -e "${GRN}[OK]${RST}    $*"; }
warn()  { echo -e "${YEL}[WARN]${RST}  $*"; }
fail()  { echo -e "${RED}[ALERT]${RST} $*"; }
step()  { echo -e "${MAG}[STEP]${RST}  $*"; }
cmd()   { echo -e "${DIM}\$ $*${RST}"; }

ts() { date '+%Y-%m-%d %H:%M:%S'; }

log_event() {
  echo "[$(ts)] $*" >> "${EVENT_LOG}"
}

log_alert() {
  echo "[$(ts)] ALERT: $*" | tee -a "${ALERT_LOG}" >/dev/null
}

notify() {
  local title="$1"
  local body="$2"

  if [[ "${ENABLE_NOTIFICATIONS}" -eq 1 ]]; then
    /usr/bin/osascript -e "display notification \"${body//\"/\\\"}\" with title \"${title//\"/\\\"}\"" >/dev/null 2>&1 || true
  fi
}

alert() {
  local msg="$*"
  fail "${msg}"
  log_alert "${msg}"
  notify "mac-watchdog" "${msg}"
}

have_sudo() {
  sudo -n true >/dev/null 2>&1
}

# =========================
# Helpers
# =========================
safe_hash_file() {
  local target="$1"
  if [[ -f "$target" ]]; then
    shasum -a 256 "$target" 2>/dev/null | awk '{print $1}'
  fi
}

snapshot_tree() {
  local outfile="$1"
  : > "$outfile"

  for p in "${WATCH_PATHS[@]}"; do
    if [[ -e "$p" ]]; then
      find "$p" -maxdepth 3 \( -type f -o -type l \) 2>/dev/null | sort | while read -r f; do
        local hash=""
        hash="$(safe_hash_file "$f" || true)"
        printf '%s|%s\n' "$f" "$hash" >> "$outfile"
      done
    fi
  done
}

diff_snapshots() {
  local old="$1"
  local new="$2"

  if [[ ! -f "$old" ]]; then
    cp "$new" "$old"
    return 0
  fi

  local added removed changed
  added="$(comm -13 <(cut -d'|' -f1 "$old" | sort) <(cut -d'|' -f1 "$new" | sort) || true)"
  removed="$(comm -23 <(cut -d'|' -f1 "$old" | sort) <(cut -d'|' -f1 "$new" | sort) || true)"

  while IFS= read -r path; do
    [[ -z "$path" ]] && continue
    alert "New persistence-related file detected: $path"
  done <<< "$added"

  while IFS= read -r path; do
    [[ -z "$path" ]] && continue
    warn "Persistence-related file removed: $path"
    log_event "Removed persistence-related file: $path"
  done <<< "$removed"

  join -t '|' -j 1 <(sort "$old") <(sort "$new") 2>/dev/null | \
  while IFS='|' read -r path oldhash newhash; do
    if [[ -n "${oldhash:-}" && -n "${newhash:-}" && "$oldhash" != "$newhash" ]]; then
      alert "Persistence-related file changed: $path"
    fi
  done

  cp "$new" "$old"
}

check_firewall() {
  local status
  status="$(defaults read /Library/Preferences/com.apple.alf globalstate 2>/dev/null || echo "unknown")"

  case "$status" in
    1|2)
      ok "Firewall enabled (globalstate=${status})"
      ;;
    0)
      alert "Firewall appears disabled"
      ;;
    *)
      warn "Could not determine firewall state"
      ;;
  esac
}

check_ssh() {
  local out
  if have_sudo; then
    out="$(sudo systemsetup -getremotelogin 2>/dev/null || true)"
  else
    out="$(systemsetup -getremotelogin 2>/dev/null || true)"
  fi

  if echo "$out" | grep -qi "On"; then
    alert "Remote Login (SSH) is ON"
  elif echo "$out" | grep -qi "Off"; then
    ok "Remote Login (SSH) is OFF"
  else
    warn "Could not determine SSH state"
  fi
}

check_filevault() {
  local out
  out="$(fdesetup status 2>/dev/null || true)"

  if echo "$out" | grep -qi "FileVault is On"; then
    ok "FileVault is ON"
  elif echo "$out" | grep -qi "FileVault is Off"; then
    alert "FileVault is OFF"
  else
    warn "Could not determine FileVault state"
  fi
}

check_launchctl_disabled() {
  local outfile="${STATE_DIR}/launchctl_print.txt"

  if have_sudo; then
    sudo launchctl print-disabled system > "$outfile" 2>/dev/null || true
  else
    launchctl print-disabled system > "$outfile" 2>/dev/null || true
  fi

  if [[ -s "$outfile" ]]; then
    log_event "Captured launchctl disabled service list"
  fi
}

check_login_items() {
  local current="${STATE_DIR}/loginitems.current"
  local previous="${STATE_DIR}/loginitems.previous"

  osascript <<'OSA' > "$current" 2>/dev/null || true
tell application "System Events"
  set theItems to the name of every login item
  repeat with i in theItems
    log i
  end repeat
end tell
OSA

  sort -u "$current" -o "$current" 2>/dev/null || true

  if [[ -f "$previous" ]]; then
    local added
    added="$(comm -13 "$previous" "$current" || true)"
    while IFS= read -r item; do
      [[ -z "$item" ]] && continue
      alert "New login item detected: $item"
    done <<< "$added"
  fi

  cp "$current" "$previous"
}

seed_baseline() {
  step "Creating baseline"
  snapshot_tree "${STATE_DIR}/tree.baseline"
  check_login_items
  check_launchctl_disabled
  ok "Baseline created"
}

watch_files() {
  local current="${STATE_DIR}/tree.current"
  snapshot_tree "$current"
  diff_snapshots "${STATE_DIR}/tree.baseline" "$current"
}

watch_states() {
  check_firewall
  check_ssh
  check_filevault
}

start_log_stream() {
  local pidfile="${PID_DIR}/log-stream.pid"

  if [[ -f "$pidfile" ]] && kill -0 "$(cat "$pidfile")" >/dev/null 2>&1; then
    warn "Unified log watcher already running (PID $(cat "$pidfile"))"
    return 0
  fi

  step "Starting unified log watcher"

  # Watches for:
  #   * launchd messages
  #   * authentication-ish failures
  #   * firewall subsystem messages
  #   * malware / Gatekeeper / XProtect-ish signals when visible in log text
  #
  # This is intentionally broad. You'll tune it over time.
  log stream --style compact \
    --predicate '
      process == "launchd" OR
      process == "sshd" OR
      process == "sudo" OR
      subsystem == "com.apple.securityd" OR
      subsystem == "com.apple.alf" OR
      eventMessage CONTAINS[c] "xprotect" OR
      eventMessage CONTAINS[c] "gatekeeper" OR
      eventMessage CONTAINS[c] "malware" OR
      eventMessage CONTAINS[c] "launch agent" OR
      eventMessage CONTAINS[c] "launch daemon" OR
      eventMessage CONTAINS[c] "authentication failed" OR
      eventMessage CONTAINS[c] "failed password" OR
      eventMessage CONTAINS[c] "screen sharing" OR
      eventMessage CONTAINS[c] "remote login"
    ' 2>/dev/null | while IFS= read -r line; do
      echo "[$(ts)] $line" >> "${EVENT_LOG}"

      case "$line" in
        *"authentication failed"*|*"failed password"*|*"xprotect"*|*"gatekeeper"*|*"malware"*|*"launch agent"*|*"launch daemon"*|*"remote login"*|*"Screen Sharing"*)
          alert "Unified log hit: $line"
          ;;
        *)
          ;;
      esac
    done &

  echo $! > "$pidfile"
  ok "Unified log watcher started (PID $(cat "$pidfile"))"
}

stop_log_stream() {
  local pidfile="${PID_DIR}/log-stream.pid"

  if [[ -f "$pidfile" ]]; then
    local pid
    pid="$(cat "$pidfile")"
    if kill -0 "$pid" >/dev/null 2>&1; then
      kill "$pid" >/dev/null 2>&1 || true
      ok "Stopped unified log watcher (PID $pid)"
    fi
    rm -f "$pidfile"
  else
    warn "No unified log watcher PID file found"
  fi
}

run_once() {
  step "Running checks"
  watch_states
  watch_files
  check_login_items
  check_launchctl_disabled
  ok "Checks complete"
}

run_loop() {
  start_log_stream
  while true; do
    run_once
    sleep "${POLL_SECONDS}"
  done
}

status() {
  echo ""
  echo -e "${WHT}State dir:${RST} ${STATE_DIR}"
  echo -e "${WHT}Event log:${RST} ${EVENT_LOG}"
  echo -e "${WHT}Alert log:${RST} ${ALERT_LOG}"
  if [[ -f "${PID_DIR}/log-stream.pid" ]]; then
    echo -e "${WHT}Log PID:${RST}   $(cat "${PID_DIR}/log-stream.pid")"
  else
    echo -e "${WHT}Log PID:${RST}   not running"
  fi
  echo ""
}

usage() {
  cat <<EOF
Usage:
  $0 baseline     Create/update baseline
  $0 once         Run checks one time
  $0 watch        Run continuously
  $0 stop         Stop background log watcher
  $0 status       Show status

Examples:
  $0 baseline
  $0 once
  $0 watch
EOF
}

main() {
  banner

  local action="${1:-}"
  case "$action" in
    baseline)
      seed_baseline
      ;;
    once)
      [[ -f "${STATE_DIR}/tree.baseline" ]] || seed_baseline
      run_once
      ;;
    watch)
      [[ -f "${STATE_DIR}/tree.baseline" ]] || seed_baseline
      run_loop
      ;;
    stop)
      stop_log_stream
      ;;
    status)
      status
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
