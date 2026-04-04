Here's what they cover across 12 categories:

**Hardening script** — prompts for confirmation, backs up your current defaults to `~/.macos_harden_backup/`, then applies changes across: firewall (stealth mode, block-all, logging), Gatekeeper enforcement, FileVault enablement, disabling sharing services (Remote Login, Remote Apple Events, Bluetooth Sharing, Wake-on-LAN), immediate screen lock on sleep, login window lockdown (no guest, no user list, no hints), Safari privacy (kill search suggestions, enable DNT, block popups), diagnostics/telemetry reduction, network hardening (captive portal probe off, AirDrop off), Finder visibility (show extensions, show hidden files, suppress .DS_Store on network/USB), secure hibernation (destroy FV keys on standby, hibernatemode 25), forced auto-updates, and Terminal secure keyboard entry.

**Rollback script** — reads the backup file to restore your original defaults where possible, and reverts everything else to macOS factory defaults. FileVault and Gatekeeper are intentionally left alone (you'd want to disable those manually if at all). Auto-updates are also left on since that's always a good idea.

To run them:

```bash
chmod +x harden-macos.sh rollback-macos.sh
./harden-macos.sh        # harden
./rollback-macos.sh      # undo
```

One heads-up — the hardening script disables Remote Login (SSH), so if you're managing this MacBook remotely, you may want to comment out that line before running it.
