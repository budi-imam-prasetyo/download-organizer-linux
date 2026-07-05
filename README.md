# Download-Organizer-Linux

[![Baca dalam Bahasa Indonesia](https://img.shields.io/badge/Dokumentasi-Bahasa%20Indonesia-blue?style=flat-square)](README.id.md)

A Linux-native bash script that automatically sorts files in your Downloads folder into categorised subfolders based on file extension.

This project is forked from the original macOS implementation, [download-organizer-mac](https://github.com/m4sbay/download-organizer?utm_source=chatgpt.com). It removes all macOS-specific tooling and has been rewritten from the ground up for modern Linux distributions (Arch, Fedora, Ubuntu, Debian, and openSUSE).

---

## How it works

- Scans only the **root** of your Downloads folder — existing subfolders are never touched.
- Skips **dotfiles**, **partial downloads** (`.crdownload`, `.part`, `.tmp`, etc.), and **recently modified files** (default: modified within the last 10 minutes).
- Routes each file to the correct subfolder based on its extension, using a **configurable mapping** in `config/extensions.conf`.
- Creates destination subfolders **on demand** — nothing is pre-created.
- Prevents **filename collisions** by appending ` (1)`, ` (2)`, etc.
- Records every move in `logs/rename-map.csv` — a permanent audit trail.
- Supports **undo**: reverse the last N moves from the audit trail.
- Uses **flock** to prevent two concurrent runs from racing each other.

---

## Folder structure

After the first run, Downloads will look like this (only categories that received files are created):

```
Downloads/
├── 01 Images/
│   ├── png/
│   ├── jpg-jpeg/
│   ├── webp/
│   ├── heic/
│   ├── raw/
│   └── ...
├── 02 Videos/
│   ├── mkv/
│   ├── mp4/
│   ├── webm/
│   └── ...
├── 03 Audio/
│   ├── mp3/
│   ├── flac/
│   ├── opus/
│   └── ...
├── 04 Documents/
│   ├── pdf/
│   ├── word/
│   ├── spreadsheet/
│   ├── ebooks/
│   └── ...
├── 05 Archives/
│   ├── zip/
│   ├── tar/
│   └── ...
├── 06 Installers/
│   ├── deb/
│   ├── rpm/
│   ├── appimage/
│   ├── iso/
│   └── ...
├── 07 Misc/
│   ├── no-extension/
│   ├── unknown/
│   └── partial/
├── 08 Design/
│   ├── svg/
│   ├── photoshop/
│   └── ...
├── 09 Code/
│   ├── scripts/
│   ├── python/
│   └── ...
├── 10 Fonts/
└── 11 Certs/

```

Full extension list: see `config/extensions.conf`.

---

## Requirements

- bash ≥ 4.0 (associative arrays)
- GNU coreutils: `stat`, `date`, `find`, `mktemp`, `realpath`
- `flock` (part of util-linux, installed by default on all target distros)
- `xdg-user-dirs` (for resolving `~/Downloads` via XDG)

All requirements are present by default on Arch, CachyOS, Fedora, Ubuntu, Debian, and openSUSE.

---

## Setup

```sh
git clone https://github.com/budi-imam-prasetyo/download-organizer-linux
cd download-organizer-linux
chmod +x organize-downloads.sh tests/run-tests.sh
```

Arch package users can also install the packaged script, documentation, and user units from the included `PKGBUILD`. The packaged command is `/usr/bin/download-organizer-linux`, and the editable config file is `/etc/download-organizer/extensions.conf`.

Run the test suite to verify everything works on your system:

```sh
bash tests/run-tests.sh
```

---

## Manual usage

Preview what would be moved (nothing is changed):

```sh
./organize-downloads.sh --dry-run
```

Preview with verbose output (shows every skipped file too):

```sh
./organize-downloads.sh --dry-run --verbose
```

Run the organizer:

```sh
./organize-downloads.sh
```

Optional shell aliases (`~/.bashrc` or `~/.zshrc`):

```sh
alias d-o='/path/to/organize-downloads.sh'
alias d-p='/path/to/organize-downloads.sh --dry-run'
```

---

## Options

| Option | Default | Description |
|---|---|---|
| `--dry-run` | — | Preview moves, nothing is changed |
| `--verbose` | — | Print every skipped file (default: silent) |
| `--downloads-dir PATH` | `xdg-user-dir DOWNLOAD` | Override target folder |
| `--min-age-minutes N` | `10` | Skip files modified within the last N minutes |
| `--keep-logs-months N` | `3` | Rotate monthly logs older than N months. `0` disables cleanup |
| `-h, --help` | — | Show help |

### Environment variables

All flags have a corresponding environment variable (lowest precedence):

| Variable | Equivalent flag |
|---|---|
| `DOWNLOADS_DIR` | `--downloads-dir` |
| `MIN_AGE_MINUTES` | `--min-age-minutes` |
| `KEEP_LOGS_MONTHS` | `--keep-logs-months` |
| `LOG_DIR` | Log directory (default: `<repo>/logs`) |
| `EXTENSIONS_CONF` | Extension config file (default: `<repo>/config/extensions.conf`) |

---

## Undo

Every move is recorded in `logs/rename-map.csv`. To reverse moves:

```sh
# Undo all moves from the last run (LIFO order):
./organize-downloads.sh undo

# Preview undo without changing anything:
./organize-downloads.sh undo --dry-run

# Undo only the last 5 moves:
./organize-downloads.sh undo --last 5

# Preview the last 3 undos:
./organize-downloads.sh undo --last 3 --dry-run
```

Undo validates each move before reversing: if the file is no longer at the destination, or the original path is already occupied, it skips that entry and logs a warning.

---

## Adding or changing extension mappings

Edit `config/extensions.conf` — no shell scripting required:

```
# Format: extension=Category/subfolder
mkv=02 Videos/mkv
flac=03 Audio/flac
```

Rules:
- Extension must be lowercase, without a leading dot.
- The path is relative to your Downloads folder.
- Lines starting with `#` are comments.
- Last entry wins for duplicate extensions.
- Restart or re-run the script to pick up changes — no reload needed.

---

## Automation with systemd

The `systemd/` directory contains a user service and timer that run the organizer daily at 06:00. If the machine was off at 06:00, the timer catches up on next boot.

When installed from the Arch package, the user units are placed in `/usr/lib/systemd/user/` and are not enabled automatically. The packaged service runs `/usr/bin/download-organizer-linux`, uses `/etc/download-organizer/extensions.conf` when present, and falls back to the shipped default config under `/usr/share/download-organizer/config/extensions.conf`.

### Install

If you are running the repository directly, edit `systemd/download-organizer.service` only if you cloned the repo somewhere other than `~/Projects/download-organizer-linux`. Then:

If you installed the package, enable the packaged timer instead:

```sh
systemctl --user enable --now download-organizer.timer
```

For a source checkout, copy the units to your user systemd directory:

```sh
# Copy units to the user systemd directory.
mkdir -p ~/.config/systemd/user
cp systemd/download-organizer.service ~/.config/systemd/user/
cp systemd/download-organizer.timer   ~/.config/systemd/user/

# Enable and start the timer.
systemctl --user daemon-reload
systemctl --user enable --now download-organizer.timer
```

### Check status

```sh
# Is the timer active?
systemctl --user status download-organizer.timer

# When does it fire next?
systemctl --user list-timers download-organizer.timer

# View logs from the last run:
journalctl --user -u download-organizer -n 50

# Follow logs live:
journalctl --user -u download-organizer -f
```

### Run once manually via systemd

```sh
systemctl --user start download-organizer.service
```

### Uninstall

```sh
systemctl --user disable --now download-organizer.timer
rm ~/.config/systemd/user/download-organizer.service
rm ~/.config/systemd/user/download-organizer.timer
systemctl --user daemon-reload
```

---

## Logs

| File | Description |
|---|---|
| `logs/organize-YYYY-MM.log` | Monthly human-readable log (auto-rotated) |
| `logs/rename-map.csv` | Permanent audit trail of every move (never deleted) |

Monthly logs older than `--keep-logs-months` (default: 3) are deleted on each run. The CSV is never deleted automatically.

---

## Project structure

```
download-organizer/
├── organize-downloads.sh     # Main entry point
├── lib/
│   ├── core.sh               # Logging, die, CSV primitives
│   ├── routing.sh            # Extension → folder routing
│   └── undo.sh               # Undo subcommand
├── config/
│   └── extensions.conf       # Editable extension-to-folder mapping
├── systemd/
│   ├── download-organizer.service
│   └── download-organizer.timer
├── tests/
│   ├── run-tests.sh
│   ├── test-routing.sh
│   ├── test-age.sh
│   └── test-undo.sh
└── logs/                     # Created on first run
    ├── organize-YYYY-MM.log
    └── rename-map.csv
```

---

## Notes

- Files are only **moved**, never deleted.
- Subfolders in the root of Downloads are never touched.
- If a destination filename already exists, a counter is appended: `file (1).pdf`, `file (2).pdf`, etc.
- Partial downloads (`.crdownload`, `.part`, `.tmp`, etc.) are always skipped.
- Files modified within the last `--min-age-minutes` are skipped to avoid moving files that are still being written.
- The lock file lives in `$XDG_RUNTIME_DIR` (usually `/run/user/$(id -u)/`) so it is automatically cleaned up on logout.
