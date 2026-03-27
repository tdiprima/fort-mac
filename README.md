# mac-update

Automated macOS maintenance scripts that keep Homebrew packages, Rust toolchains, and system software current — hands-free, every day.

## The Maintenance Tax Every macOS Developer Pays

Keeping a development machine healthy means repeatedly running the same commands: `brew update`, `brew upgrade`, `rustup update`, `softwareupdate`. Miss a few days and you're debugging version skew instead of shipping code. Do it manually and you're burning attention on something a script can own.

## Set It and Forget It

This project gives you two tools: a one-shot script you can run any time, and a persistent daily scheduler that fires automatically at 3:00 PM. Both update Homebrew and the Rust toolchain, clean up stale packages, and run `brew doctor` to catch issues early. The scheduler logs every run to a rotating file so you always have an audit trail.

## What a Typical Run Looks Like

Running the one-shot updater:

```bash
python update_mac.py
```

```
📦 Updating Cargo...
✅ Cargo updated.
🍺 Updating Homebrew...
✅ Homebrew updated.
```

Running the scheduler (stays alive, fires daily at 15:00):

```bash
python daily_scheduler.py
```

```
2026-03-27 09:00:00 | INFO | Scheduler started. Waiting for 3:00 PM each day...
2026-03-27 15:00:00 | INFO | 📦 Updating Cargo...
2026-03-27 15:00:04 | INFO | ✅ Cargo updated.
2026-03-27 15:00:04 | INFO | 🍺 Updating Homebrew...
2026-03-27 15:00:30 | INFO | ✅ Homebrew updated.
```

Logs rotate at 5 MB and the last 3 files are retained automatically.

## Usage

**Prerequisites**

- Python 3.11+
- [uv](https://github.com/astral-sh/uv) (recommended) or pip
- Homebrew and rustup installed

**Install dependencies**

```bash
uv sync
```

**Run a one-time update**

```bash
python update_mac.py
```

**Run the daily scheduler**

```bash
python daily_scheduler.py
```

To run it persistently in the background, consider wrapping it in a `launchd` plist or a `tmux` session.

**Update macOS system software** (optional, standalone bash script):

```bash
bash update_software_mac
```

This lists and installs all pending Apple software updates via `softwareupdate`.

<br>
