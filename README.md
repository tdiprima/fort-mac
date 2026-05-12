# Fort Mac 💻

One-command macOS hardening, continuous security monitoring, and automated maintenance.

## Your Mac Ships Wide Open

Out of the box, macOS leaves the firewall off, AirDrop broadcasting to everyone, guest accounts enabled, crash reports phoning home, and Bonjour advertising your machine to the network. Every setting you should change lives in a different panel, behind a different toggle, documented in a different support article. Most developers never touch them. The ones who do spend an afternoon clicking through System Settings and hope they didn't miss anything.

Meanwhile, `brew update && brew upgrade && brew cleanup && brew doctor` gets old fast. Skip it for a week and you're debugging stale dependencies instead of writing code.

## Harden, Watch, Maintain

**fort-mac** handles all three in one toolkit:

**Harden** locks down 12 categories of macOS security settings in a single run — firewall with stealth mode, FileVault encryption, Gatekeeper enforcement, disabled sharing services, Safari privacy, telemetry suppression, and more. Every change is backed up first, and a rollback script restores your previous state if needed.

**Watch** runs continuous security monitoring. A watchdog daemon detects new LaunchAgents and LaunchDaemons, tracks firewall/SSH/FileVault state drift, tails the unified log for authentication failures and malware signals, and pushes desktop notifications when something changes.

**Maintain** keeps Homebrew and Rust toolchains current with a one-shot updater or a persistent daily scheduler that fires at 3:00 PM, logs every run, and rotates its own log files.

## What It Looks Like

Hardening a fresh machine:

```bash
bash src/harden-macos.sh
```

```
🔒  macOS Hardening Script

━━━ 1 · Firewall ━━━
  ✔  Enable application-layer firewall
  ✔  Enable stealth mode (drop unsolicited packets)
  ✔  Enable logging on the firewall
  ✔  Block all incoming connections (signed apps still allowed)

━━━ 2 · Gatekeeper & Code Signing ━━━
  ✔  Restrict app sources to App Store + identified developers
  ✔  SIP is already enabled

━━━ 3 · FileVault Disk Encryption ━━━
  ✔  FileVault is already enabled
  ...

✅  Hardening complete
  Backup saved to: ~/.macos_harden_backup
  ⚠  A restart is recommended to apply all changes.
  ⚠  Run the rollback script to undo these changes.
```

Running the watchdog:

```bash
bash src/mac-watchdog.sh watch
```

```
👀  mac-watchdog

[STEP]  Creating baseline
[OK]    Baseline created
[OK]    Firewall enabled (globalstate=1)
[OK]    Remote Login (SSH) is OFF
[OK]    FileVault is ON
[ALERT] New persistence-related file detected: ~/Library/LaunchAgents/suspicious.plist
```

## Usage

### Prerequisites

- macOS 13+
- Python 3.11+ and [uv](https://github.com/astral-sh/uv)
- Homebrew and rustup installed

### Install dependencies

```bash
uv sync
```

### Security hardening

```bash
# Harden the system (backs up current state first)
bash src/harden-macos.sh

# Undo all hardening changes
bash src/rollback-macos.sh

# Rebuild backup from current system state
bash src/default_state_backup.sh
```

### Continuous monitoring

```bash
# Create baseline and start watching
bash src/mac-watchdog.sh watch

# Run checks once without looping
bash src/mac-watchdog.sh once

# Stop background log watcher
bash src/mac-watchdog.sh stop
```

### Automated updates

```bash
# One-time Homebrew + Rust update
python src/update_mac.py

# Daily scheduler (fires at 3:00 PM, logs to scheduler.log)
python src/daily_scheduler.py

# Apple system software updates
bash src/update_software_mac
```

### AirDrop toggle

```bash
# Enable AirDrop (auto-reverts visibility after 10 min)
bash src/airdrop_toggle_v2.sh 1

# Disable AirDrop and re-harden
bash src/airdrop_toggle_v2.sh 2
```

### Keychain setup

The update scripts retrieve credentials from the macOS Keychain. Store yours first:

```bash
security add-generic-password -a "$USER" -s "mac_update_conga" -w "<your-value>"
```

## License

[MIT](LICENSE)

<br>
