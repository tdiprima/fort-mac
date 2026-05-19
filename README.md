# fort-mac 🏰

macOS security hardening, monitoring, and maintenance automation for MacBook Pro (macOS 13+).
<p align="center">⚠️ <strong>Important: Read warning below </strong>⬇️</p>

## The Threat Surface Nobody Thinks About

A stock macOS install is friendly — maybe too friendly. Remote Apple Events, mDNS multicast, AirDrop broadcasting, guest accounts, no stealth mode. Fine for a home desk. Not fine on a conference Wi-Fi, a shared office network, or anywhere you'd rather not be discovered.

## What This Does

`fort-mac` is a collection of focused scripts that lock down, monitor, and maintain a Mac:

- **Harden** — applies ~40 security settings across firewall, Gatekeeper, sharing services, login window, Safari, telemetry, and network behavior. Backs up every setting it touches so rollback is exact.
- **Rollback** — restores only what was changed. Two variants: a full rollback and a safe-mode rollback that never re-enables attack surface (SSH, Remote Apple Events stay off).
- **Watchdog** — polls LaunchAgents/LaunchDaemons for new or modified persistence files, checks firewall/SSH/FileVault state drift, streams unified logs for auth failures, Gatekeeper events, and malware signals. Sends desktop notifications on any hit.
- **AirDrop toggle** — one command to open AirDrop for a file transfer (visibility auto-reverts to Contacts Only after 10 minutes), and one command to lock it back down.
- **Homebrew + Rust updater** — daily scheduled maintenance. Pulls the sudo password from the macOS Keychain; no plaintext credentials anywhere.

## Quick Example

```bash
# Harden the machine (backs up current state first)
bash src/harden-macos.sh

# Watch for persistence changes and security drift
bash src/mac-watchdog.sh watch

# Need to AirDrop something? Open for 10 min, then auto-revert
bash src/airdrop_toggle_v2.sh 1

# Undo hardening (restores your exact pre-harden state)
bash src/rollback-macos-v2.sh
```

## Usage

| Script | Purpose |
|--------|---------|
| `src/harden-macos.sh` | Apply all hardening settings |
| `src/rollback-macos-v2.sh` | Restore pre-harden state (safe mode) |
| `src/mac-watchdog.sh baseline` | Snapshot current persistence state |
| `src/mac-watchdog.sh watch` | Continuous monitoring loop |
| `src/mac-watchdog.sh once` | Single-pass check |
| `src/airdrop_toggle_v2.sh 1` | Enable AirDrop (auto-reverts in 10 min) |
| `src/airdrop_toggle_v2.sh 2` | Disable AirDrop + harden |
| `src/reset-watchdog.sh` | Stop watchdog and reset network/firewall state |

**Python updater (requires `uv`):**

```bash
uv run src/update_mac.py          # run once
uv run src/daily_scheduler.py     # run on schedule (3 PM daily)
```

The updater reads your sudo password from the macOS Keychain. Store it once:

```bash
security add-generic-password -a "$USER" -s mac_update_conga -w "<your password>"
```

## ⚠️ Disclaimer / "You Were Warned" Section

If you run this code and your server catches fire, your cat learns Kubernetes, your prod database achieves enlightenment, or your toaster somehow joins the cluster — that's on you.

I am not responsible for:

* broken systems
* deleted data
* corrupted configs
* emotional damage
* spontaneous outages
* DNS-related psychological warfare
* your boss asking "who approved this?"
* any incident tickets created at 3:17 AM
* keyboards launched across the room
* or literally anything else

Some of this code can absolutely break your stuff.  
Do not copy-paste random commands unless you genuinely understand what they do.

Seriously.

You've been warned. ☠️

<br>
