#!/usr/bin/env bash
# mac-watchdog-v2.sh
# Defensive macOS monitor for personal use.
# Watches for:
#   * persistence drift (LaunchAgents / LaunchDaemons)
#   * login item changes
#   * state drift (firewall / SSH / FileVault / Gatekeeper)
#   * new listening ports
#   * lightweight unified-log signals
#   * optional webhook and desktop notifications
# Supports:
#   * baseline creation
#   * whitelist regexes
#   * user LaunchAgent install for auto-start
#
# Designed for macOS 13+.

set -uo pipefail
IFS=$'\n\t'

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
VERSION="2.0"
BASE_DIR="${HOME}/.mac-watchdog"
STATE_DIR="${BASE_DIR}/state"
LOG_DIR="${BASE_DIR}/logs"
RUN_DIR="${BASE_DIR}/run"
CONF_DIR="${BASE_DIR}/config"
ALERT_LOG="${LOG_DIR}/alerts.log"
EVENT_LOG="${LOG_DIR}/events.log"
STATUS_LOG="${LOG_DIR}/status.log"
LOG_STREAM_PID="${RUN_DIR}/log-stream.pid"
WATCHDOG_PID="${RUN_DIR}/watchdog.pid"
WHITELIST_FILE="${CONF_DIR}/whitelist.regex"
ENV_FILE="${CONF_DIR}/watchdog.env"
LAUNCH_AGENT_LABEL="local.mac-watchdog"
LAUNCH_AGENT_PATH="${HOME}/Library/LaunchAgents/${LAUNCH_AGENT_LABEL}.plist"

POLL_SECONDS="${POLL_SECONDS:-30}"
ENABLE_NOTIFICATIONS="${ENABLE_NOTIFICATIONS:-1}"
ENABLE_WEBHOOKS="${ENABLE_WEBHOOKS:-0}"
WEBHOOK_URL="${WEBHOOK_URL:-}"
ENABLE_PORT_CHECKS="${ENABLE_PORT_CHECKS:-1}"
ENABLE_UNIFIED_LOG="${ENABLE_UNIFIED_LOG:-1}"
STRICT_MODE="${STRICT_MODE:-0}"

WATCH_PATHS=(
  "/Library/LaunchDaemons"
  "/Library/LaunchAgents"
  "${HOME}/Library/LaunchAgents"
  "/var/db/com.apple.xpc.launchd"
)

mkdir -p "${STATE_DIR}" "${LOG_DIR}" "${RUN_DIR}" "${CONF_DIR}"
touch "${ALERT_LOG}" "${EVENT_LOG}" "${STATUS_LOG}" "${WHITELIST_FILE}" "${ENV_FILE}"

# shellcheck source=/dev/null
[[ -f "${ENV_FILE}" ]] && source "${ENV_FILE}"

# =========================
# Pretty output
# =========================
banner() {
  echo ""
  echo -e "${BLU}┌──────────────────────────────────────────────────────────────┐${RST}"
  printf "${BLU}│${WHT}  👀  %-54s${BLU}│${RST}\n" "${APP_NAME} v${VERSION}"
  printf "${BLU}│${DIM}  Base: %-54s${BLU}│${RST}\n" "${BASE_DIR}"
  echo -e "${BLU}└──────────────────────────────────────────────────────────────┘${RST}"
  echo ""
}

info()  { echo -e "${CYN}[INFO]${RST}  $*"; }
ok()    { echo -e "${GRN}[OK]${RST}    $*"; }
warn()  { echo -e "${YEL}[WARN]${RST}  $*"; }
fail()  { echo -e "${RED}[ALERT]${RST} $*"; }
step()  { echo -e "${MAG}[STEP]${RST}  $*"; }
cmd()   { echo -e "${DIM}\$ $*${RST}"; }

# =========================
# Logging helpers
# =========================
ts() { date '+%Y-%m-%d %H:%M:%S'; }

log_event() {
  echo "[$(ts)] $*" >> "${EVENT_LOG}"
}

log_status() {
  echo "[$(ts)] $*" >> "${STATUS_LOG}"
}

log_alert() {
  echo "[$(ts)] ALERT: $*" | tee -a "${ALERT_LOG}" >/dev/null
}

json_escape() {
  python3 - <<'PY' "$1"
import json, sys
print(json.dumps(sys.argv[1]))
PY
}

notify() {
  local title="$1"
  local body="$2"
  if [[ "${ENABLE_NOTIFICATIONS}" == "1" ]]; then
    /usr/bin/osascript -e "display notification \"${body//\"/\\\"}\" with title \"${title//\"/\\\"}\"" >/dev/null 2>&1 || true
  fi
}

send_webhook() {
  local body="$1"
  [[ "${ENABLE_WEBHOOKS}" == "1" ]] || return 0
  [[ -n "${WEBHOOK_URL}" ]] || return 0

  local payload
  payload=$(printf '{"text":%s}' "$(json_escape "[${APP_NAME}] ${body}")")

  curl -fsS -m 10 -H 'Content-Type: application/json' -d "$payload" "$WEBHOOK_URL" >/dev/null 2>&1 || \
    log_event "Webhook delivery failed: ${body}"
}

alert() {
  local msg="$*"
  fail "$msg"
  log_alert "$msg"
  notify "${APP_NAME}" "$msg"
  send_webhook "$msg"
}

# =========================
# Generic helpers
# =========================
have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

have_sudo() {
  sudo -n true >/dev/null 2>&1
}

checksum_file() {
  local target="$1"
  [[ -f "$target" ]] || return 0
  shasum -a 256 "$target" 2>/dev/null | awk '{print $1}'
}

is_whitelisted() {
  local value="$1"
  [[ -s "${WHITELIST_FILE}" ]] || return 1
  grep -E -q -f "${WHITELIST_FILE}" <<< "$value"
}

emit_alert_unless_whitelisted() {
  local msg="$1"
  if is_whitelisted "$msg"; then
    log_event "Whitelisted event suppressed: $msg"
  else
    alert "$msg"
  fi
}

safe_copy() {
  local src="$1" dst="$2"
  [[ -f "$src" ]] && cp "$src" "$dst"
}

# =========================
# Baseline collection
# =========================
snapshot_persistence() {
  local outfile="$1"
  : > "$outfile"

  local p f hash
  for p in "${WATCH_PATHS[@]}"; do
    [[ -e "$p" ]] || continue
    while IFS= read -r f; do
      [[ -f "$f" || -L "$f" ]] || continue
      hash="$(checksum_file "$f" || true)"
      printf '%s|%s\n' "$f" "$hash" >> "$outfile"
    done < <(find "$p" -maxdepth 3 \( -type f -o -type l \) 2>/dev/null | sort)
  done
}

snapshot_login_items() {
  local outfile="$1"
  if have_cmd osascript; then
    osascript <<'OSA' > "$outfile" 2>/dev/null || true
tell application "System Events"
  set itemNames to the name of every login item
  repeat with n in itemNames
    log n
  end repeat
end tell
OSA
    sort -u "$outfile" -o "$outfile" 2>/dev/null || true
  else
    : > "$outfile"
  fi
}

snapshot_ports() {
  local outfile="$1"
  : > "$outfile"

  if ! [[ "${ENABLE_PORT_CHECKS}" == "1" ]]; then
    return 0
  fi

  if have_cmd lsof; then
    lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null | awk 'NR>1 {printf "%s|%s|%s|%s\n", $1, $2, $9, $10}' | sort -u > "$outfile"
  elif have_cmd netstat; then
    netstat -anv -p tcp 2>/dev/null | awk '/LISTEN/ {print $0}' | sort -u > "$outfile"
  fi
}

snapshot_launchctl_services() {
  local outfile="$1"
  : > "$outfile"

  if have_sudo; then
    sudo launchctl print system 2>/dev/null | grep -E '^[[:space:]]+"?[A-Za-z0-9._-]+' | sed 's/^[[:space:]]*//' | sort -u > "$outfile" || true
  else
    launchctl print system 2>/dev/null | grep -E '^[[:space:]]+"?[A-Za-z0-9._-]+' | sed 's/^[[:space:]]*//' | sort -u > "$outfile" || true
  fi
}

create_baseline() {
  step "Creating baseline"
  snapshot_persistence "${STATE_DIR}/persistence.baseline"
  snapshot_login_items "${STATE_DIR}/loginitems.baseline"
  snapshot_ports "${STATE_DIR}/ports.baseline"
  snapshot_launchctl_services "${STATE_DIR}/launchctl.baseline"
  log_event "Baseline created"
  ok "Baseline written to ${STATE_DIR}"
}

# =========================
# Drift detection
# =========================
compare_path_hash_snapshots() {
  local baseline="$1" current="$2"
  [[ -f "$baseline" ]] || return 0

  local added removed path oldhash newhash
  added="$(comm -13 <(cut -d'|' -f1 "$baseline" | sort) <(cut -d'|' -f1 "$current" | sort) || true)"
  removed="$(comm -23 <(cut -d'|' -f1 "$baseline" | sort) <(cut -d'|' -f1 "$current" | sort) || true)"

  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    emit_alert_unless_whitelisted "New persistence-related file detected: $path"
  done <<< "$added"

  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    if [[ "${STRICT_MODE}" == "1" ]]; then
      emit_alert_unless_whitelisted "Persistence-related file removed: $path"
    else
      warn "Persistence-related file removed: $path"
      log_event "Persistence-related file removed: $path"
    fi
  done <<< "$removed"

  join -t '|' -j 1 <(sort "$baseline") <(sort "$current") 2>/dev/null | \
  while IFS='|' read -r path oldhash newhash; do
    [[ -n "$path" ]] || continue
    if [[ -n "${oldhash:-}" && -n "${newhash:-}" && "$oldhash" != "$newhash" ]]; then
      emit_alert_unless_whitelisted "Persistence-related file changed: $path"
    fi
  done
}

compare_simple_snapshots() {
  local baseline="$1" current="$2" prefix="$3" severity="${4:-alert}"
  [[ -f "$baseline" ]] || return 0

  local added removed line
  added="$(comm -13 <(sort "$baseline") <(sort "$current") || true)"
  removed="$(comm -23 <(sort "$baseline") <(sort "$current") || true)"

  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    if [[ "$severity" == "alert" ]]; then
      emit_alert_unless_whitelisted "$prefix added: $line"
    else
      warn "$prefix added: $line"
      log_event "$prefix added: $line"
    fi
  done <<< "$added"

  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    if [[ "${STRICT_MODE}" == "1" && "$severity" == "alert" ]]; then
      emit_alert_unless_whitelisted "$prefix removed: $line"
    else
      warn "$prefix removed: $line"
      log_event "$prefix removed: $line"
    fi
  done <<< "$removed"
}

check_persistence_drift() {
  local current="${STATE_DIR}/persistence.current"
  snapshot_persistence "$current"
  compare_path_hash_snapshots "${STATE_DIR}/persistence.baseline" "$current"
}

check_login_item_drift() {
  local current="${STATE_DIR}/loginitems.current"
  snapshot_login_items "$current"
  compare_simple_snapshots "${STATE_DIR}/loginitems.baseline" "$current" "Login item" alert
}

check_port_drift() {
  [[ "${ENABLE_PORT_CHECKS}" == "1" ]] || return 0
  local current="${STATE_DIR}/ports.current"
  snapshot_ports "$current"
  compare_simple_snapshots "${STATE_DIR}/ports.baseline" "$current" "Listening port" alert
}

check_launchctl_drift() {
  local current="${STATE_DIR}/launchctl.current"
  snapshot_launchctl_services "$current"
  compare_simple_snapshots "${STATE_DIR}/launchctl.baseline" "$current" "launchctl service" warn
}

# =========================
# State checks
# =========================
check_firewall() {
  local status
  status="$(defaults read /Library/Preferences/com.apple.alf globalstate 2>/dev/null || echo "unknown")"

  case "$status" in
    1|2)
      ok "Firewall enabled (globalstate=$status)"
      log_status "Firewall enabled (globalstate=$status)"
      ;;
    0)
      emit_alert_unless_whitelisted "Firewall appears disabled"
      ;;
    *)
      warn "Could not determine firewall state"
      log_status "Firewall state unknown"
      ;;
  esac
}

check_ssh() {
  local out=""
  if have_sudo; then
    out="$(sudo systemsetup -getremotelogin 2>/dev/null || true)"
  else
    out="$(systemsetup -getremotelogin 2>/dev/null || true)"
  fi

  if grep -qi 'On' <<< "$out"; then
    emit_alert_unless_whitelisted "Remote Login (SSH) is ON"
  elif grep -qi 'Off' <<< "$out"; then
    ok "Remote Login (SSH) is OFF"
    log_status "Remote Login (SSH) is OFF"
  else
    warn "Could not determine SSH state"
    log_status "Remote Login (SSH) unknown"
  fi
}

check_filevault() {
  local out
  out="$(fdesetup status 2>/dev/null || true)"

  if grep -qi 'FileVault is On' <<< "$out"; then
    ok "FileVault is ON"
    log_status "FileVault is ON"
  elif grep -qi 'FileVault is Off' <<< "$out"; then
    emit_alert_unless_whitelisted "FileVault is OFF"
  else
    warn "Could not determine FileVault state"
    log_status "FileVault unknown"
  fi
}

check_gatekeeper() {
  local out
  out="$(spctl --status 2>/dev/null || true)"

  if grep -qi 'assessments enabled' <<< "$out"; then
    ok "Gatekeeper is ON"
    log_status "Gatekeeper ON"
  elif grep -qi 'assessments disabled' <<< "$out"; then
    emit_alert_unless_whitelisted "Gatekeeper appears disabled"
  else
    warn "Could not determine Gatekeeper state"
    log_status "Gatekeeper unknown"
  fi
}

check_sip() {
  local out
  out="$(csrutil status 2>/dev/null || true)"
  if grep -qi 'enabled' <<< "$out"; then
    ok "SIP is enabled"
    log_status "SIP enabled"
  elif grep -qi 'disabled' <<< "$out"; then
    emit_alert_unless_whitelisted "System Integrity Protection (SIP) is disabled"
  else
    warn "Could not determine SIP state"
    log_status "SIP unknown"
  fi
}

run_state_checks() {
  check_firewall
  check_ssh
  check_filevault
  check_gatekeeper
  check_sip
}

# =========================
# Unified log watcher
# =========================
start_log_stream() {
  [[ "${ENABLE_UNIFIED_LOG}" == "1" ]] || {
    warn "Unified log watcher disabled by config"
    return 0
  }

  if [[ -f "${LOG_STREAM_PID}" ]] && kill -0 "$(cat "${LOG_STREAM_PID}")" >/dev/null 2>&1; then
    warn "Unified log watcher already running (PID $(cat "${LOG_STREAM_PID}"))"
    return 0
  fi

  step "Starting unified log watcher"

  log stream --style compact \
    --predicate '
      process == "launchd" OR
      process == "sshd" OR
      process == "sudo" OR
      process == "loginwindow" OR
      subsystem == "com.apple.alf" OR
      subsystem == "com.apple.securityd" OR
      eventMessage CONTAINS[c] "xprotect" OR
      eventMessage CONTAINS[c] "gatekeeper" OR
      eventMessage CONTAINS[c] "malware" OR
      eventMessage CONTAINS[c] "launch agent" OR
      eventMessage CONTAINS[c] "launch daemon" OR
      eventMessage CONTAINS[c] "failed password" OR
      eventMessage CONTAINS[c] "authentication failed" OR
      eventMessage CONTAINS[c] "remote login" OR
      eventMessage CONTAINS[c] "screen sharing" OR
      eventMessage CONTAINS[c] "TCC" OR
      eventMessage CONTAINS[c] "Full Disk Access"
    ' 2>/dev/null | while IFS= read -r line; do
      echo "[$(ts)] $line" >> "${EVENT_LOG}"
      case "$line" in
        *failed\ password*|*authentication\ failed*|*xprotect*|*gatekeeper*|*malware*|*launch\ agent*|*launch\ daemon*|*remote\ login*|*screen\ sharing*|*Full\ Disk\ Access*|*TCC*)
          emit_alert_unless_whitelisted "Unified log hit: $line"
          ;;
        *)
          ;;
      esac
    done &

  echo $! > "${LOG_STREAM_PID}"
  ok "Unified log watcher started (PID $(cat "${LOG_STREAM_PID}"))"
}

stop_log_stream() {
  if [[ -f "${LOG_STREAM_PID}" ]]; then
    local pid
    pid="$(cat "${LOG_STREAM_PID}")"
    if kill -0 "$pid" >/dev/null 2>&1; then
      kill "$pid" >/dev/null 2>&1 || true
      ok "Stopped unified log watcher (PID $pid)"
    fi
    rm -f "${LOG_STREAM_PID}"
  else
    warn "No unified log watcher PID file found"
  fi
}

# =========================
# Main execution modes
# =========================
run_once() {
  step "Running checks"
  run_state_checks
  check_persistence_drift
  check_login_item_drift
  check_port_drift
  check_launchctl_drift
  ok "Checks complete"
}

run_watch_loop() {
  if [[ -f "${WATCHDOG_PID}" ]] && kill -0 "$(cat "${WATCHDOG_PID}")" >/dev/null 2>&1; then
    warn "Watch loop already running (PID $(cat "${WATCHDOG_PID}"))"
    return 0
  fi

  echo $$ > "${WATCHDOG_PID}"
  trap 'rm -f "${WATCHDOG_PID}"; stop_log_stream; exit 0' INT TERM EXIT

  start_log_stream
  while true; do
    run_once
    sleep "${POLL_SECONDS}"
  done
}

stop_watch_loop() {
  if [[ -f "${WATCHDOG_PID}" ]]; then
    local pid
    pid="$(cat "${WATCHDOG_PID}")"
    if kill -0 "$pid" >/dev/null 2>&1; then
      kill "$pid" >/dev/null 2>&1 || true
      ok "Stopped watch loop (PID $pid)"
    fi
    rm -f "${WATCHDOG_PID}"
  else
    warn "No watch loop PID file found"
  fi

  stop_log_stream
}

# =========================
# LaunchAgent install
# =========================
install_launchagent() {
  step "Installing user LaunchAgent"
  cat > "${LAUNCH_AGENT_PATH}" <<EOF_PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${LAUNCH_AGENT_LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${PWD}/$(basename "$0")</string>
    <string>watch</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>HOME</key>
    <string>${HOME}</string>
    <key>PATH</key>
    <string>/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>${LOG_DIR}/launchagent.stdout.log</string>
  <key>StandardErrorPath</key>
  <string>${LOG_DIR}/launchagent.stderr.log</string>
</dict>
</plist>
EOF_PLIST

  launchctl unload "${LAUNCH_AGENT_PATH}" >/dev/null 2>&1 || true
  launchctl load "${LAUNCH_AGENT_PATH}" >/dev/null 2>&1 || true
  ok "Installed LaunchAgent at ${LAUNCH_AGENT_PATH}"
  info "It will start automatically when you log in."
}

uninstall_launchagent() {
  step "Removing user LaunchAgent"
  launchctl unload "${LAUNCH_AGENT_PATH}" >/dev/null 2>&1 || true
  rm -f "${LAUNCH_AGENT_PATH}"
  ok "Removed LaunchAgent"
}

# =========================
# Whitelist helpers
# =========================
show_whitelist_help() {
  cat <<EOF_WHITELIST
Whitelist file:
  ${WHITELIST_FILE}

Each line is an extended regex. If an alert message matches, it is suppressed.
Examples:
  ^New persistence-related file detected: /Users/.*/Library/LaunchAgents/com\.microsoft\.
  ^Listening port added: ControlCenter\|
  ^Unified log hit: .*TCC.*Photos
EOF_WHITELIST
}

# =========================
# Status / usage
# =========================
status() {
  echo ""
  echo -e "${WHT}Version:${RST}              ${VERSION}"
  echo -e "${WHT}Base dir:${RST}             ${BASE_DIR}"
  echo -e "${WHT}Config file:${RST}          ${ENV_FILE}"
  echo -e "${WHT}Whitelist file:${RST}       ${WHITELIST_FILE}"
  echo -e "${WHT}Alerts log:${RST}           ${ALERT_LOG}"
  echo -e "${WHT}Events log:${RST}           ${EVENT_LOG}"
  echo -e "${WHT}Status log:${RST}           ${STATUS_LOG}"
  echo -e "${WHT}Poll seconds:${RST}         ${POLL_SECONDS}"
  echo -e "${WHT}Notifications:${RST}        ${ENABLE_NOTIFICATIONS}"
  echo -e "${WHT}Webhooks:${RST}             ${ENABLE_WEBHOOKS}"
  echo -e "${WHT}Port checks:${RST}          ${ENABLE_PORT_CHECKS}"
  echo -e "${WHT}Unified log:${RST}          ${ENABLE_UNIFIED_LOG}"
  echo -e "${WHT}Strict mode:${RST}          ${STRICT_MODE}"

  if [[ -f "${WATCHDOG_PID}" ]]; then
    echo -e "${WHT}Watch PID:${RST}            $(cat "${WATCHDOG_PID}")"
  else
    echo -e "${WHT}Watch PID:${RST}            not running"
  fi

  if [[ -f "${LOG_STREAM_PID}" ]]; then
    echo -e "${WHT}Log stream PID:${RST}       $(cat "${LOG_STREAM_PID}")"
  else
    echo -e "${WHT}Log stream PID:${RST}       not running"
  fi

  echo ""
}

usage() {
  cat <<EOF_USAGE
Usage:
  $0 baseline               Create or refresh baseline
  $0 once                   Run checks one time
  $0 watch                  Run continuously
  $0 stop                   Stop watch loop and log stream
  $0 status                 Show runtime status
  $0 install-launchagent    Auto-start at login
  $0 uninstall-launchagent  Remove auto-start
  $0 whitelist-help         Show whitelist examples

Config file:
  ${ENV_FILE}

Supported env vars in ${ENV_FILE}:
  POLL_SECONDS=30
  ENABLE_NOTIFICATIONS=1
  ENABLE_WEBHOOKS=0
  WEBHOOK_URL=
  ENABLE_PORT_CHECKS=1
  ENABLE_UNIFIED_LOG=1
  STRICT_MODE=0
EOF_USAGE
}

main() {
  banner
  local action="${1:-}"

  case "$action" in
    baseline)
      create_baseline
      ;;
    once)
      [[ -f "${STATE_DIR}/persistence.baseline" ]] || create_baseline
      run_once
      ;;
    watch)
      [[ -f "${STATE_DIR}/persistence.baseline" ]] || create_baseline
      run_watch_loop
      ;;
    stop)
      stop_watch_loop
      ;;
    status)
      status
      ;;
    install-launchagent)
      install_launchagent
      ;;
    uninstall-launchagent)
      uninstall_launchagent
      ;;
    whitelist-help)
      show_whitelist_help
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
