#!/usr/bin/env bash
# organize-downloads.sh — Linux-native Downloads folder organizer
#
# Moves files from the root of ~/Downloads into categorised subfolders
# based on extension. Subfolders are created on demand.
#
# Usage:
#   ./organize-downloads.sh [OPTIONS]
#   ./organize-downloads.sh undo [--last N] [--dry-run]
#
# See --help for full option reference.

set -euo pipefail

# ---------------------------------------------------------------------------
# Resolve script location (symlink-safe).
# ---------------------------------------------------------------------------
SCRIPT_PATH="$(readlink -f "$0")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"

# ---------------------------------------------------------------------------
# Configurable defaults — all overridable via environment variables.
# ---------------------------------------------------------------------------
DOWNLOADS_DIR="${DOWNLOADS_DIR:-$(xdg-user-dir DOWNLOAD 2>/dev/null || printf '%s/Downloads' "$HOME")}"
LOG_DIR="${LOG_DIR:-$SCRIPT_DIR/logs}"
EXTENSIONS_CONF="${EXTENSIONS_CONF:-$SCRIPT_DIR/config/extensions.conf}"

# Derived paths — not overridable individually (depend on LOG_DIR).
LOG_FILE="$LOG_DIR/organize-$(date '+%Y-%m').log"
RENAME_MAP="$LOG_DIR/rename-map.csv"

# Runtime flags — set by argument parser below.
DRY_RUN=0
VERBOSE=0
MIN_AGE_MINUTES="${MIN_AGE_MINUTES:-10}"
KEEP_LOGS_MONTHS="${KEEP_LOGS_MONTHS:-3}"

# Lock file — prevents concurrent runs.
LOCK_FILE="${XDG_RUNTIME_DIR:-/tmp}/download-organizer-$(id -u).lock"

# ---------------------------------------------------------------------------
# Source libraries (order matters: core first, then routing, then undo).
# ---------------------------------------------------------------------------
# shellcheck source=lib/core.sh
source "$SCRIPT_DIR/lib/core.sh"
# shellcheck source=lib/routing.sh
source "$SCRIPT_DIR/lib/routing.sh"
# shellcheck source=lib/undo.sh
source "$SCRIPT_DIR/lib/undo.sh"

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
  cat <<'EOF'
Usage:
  organize-downloads.sh [OPTIONS]
  organize-downloads.sh undo [--last N] [--dry-run] [--verbose]

Subcommands:
  undo           Reverse the last N "moved" actions (default: all).

Options:
  --dry-run              Preview moves without changing files.
  --verbose              Print every skipped file (default: skips are silent).
  --downloads-dir PATH   Override Downloads folder. Default: xdg-user-dir DOWNLOAD.
  --min-age-minutes N    Skip files modified in the last N minutes. Default: 10.
  --keep-logs-months N   Rotate logs older than N months. Default: 3. Set 0 to disable.
  --last N               (undo only) Reverse only the last N moved files.
  -h, --help             Show this help.

Environment variables (lowest precedence):
  DOWNLOADS_DIR          Same as --downloads-dir.
  MIN_AGE_MINUTES        Same as --min-age-minutes.
  KEEP_LOGS_MONTHS       Same as --keep-logs-months.
  LOG_DIR                Override log directory. Default: <script_dir>/logs.
  EXTENSIONS_CONF        Override extension config. Default: <script_dir>/config/extensions.conf.

Examples:
  organize-downloads.sh --dry-run
  organize-downloads.sh --dry-run --verbose
  organize-downloads.sh --downloads-dir /tmp/test-downloads
  organize-downloads.sh undo --last 5 --dry-run
EOF
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
SUBCOMMAND=""
UNDO_LAST=0

# Capture subcommand if present.
if [[ "${1:-}" == "undo" ]]; then
  SUBCOMMAND="undo"
  shift
fi

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --verbose)
      VERBOSE=1
      shift
      ;;
    --downloads-dir)
      [[ "$#" -lt 2 ]] && { printf 'Missing value for --downloads-dir\n' >&2; exit 2; }
      DOWNLOADS_DIR="$2"
      shift 2
      ;;
    --min-age-minutes)
      [[ "$#" -lt 2 ]] && { printf 'Missing value for --min-age-minutes\n' >&2; exit 2; }
      MIN_AGE_MINUTES="$2"
      shift 2
      ;;
    --keep-logs-months)
      [[ "$#" -lt 2 ]] && { printf 'Missing value for --keep-logs-months\n' >&2; exit 2; }
      KEEP_LOGS_MONTHS="$2"
      shift 2
      ;;
    --last)
      [[ "$#" -lt 2 ]] && { printf 'Missing value for --last\n' >&2; exit 2; }
      UNDO_LAST="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown option: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Input validation
# ---------------------------------------------------------------------------
if ! [[ "$MIN_AGE_MINUTES" =~ ^[0-9]+$ ]]; then
  printf -- '--min-age-minutes must be a non-negative integer\n' >&2
  exit 2
fi

if ! [[ "$KEEP_LOGS_MONTHS" =~ ^[0-9]+$ ]]; then
  printf -- '--keep-logs-months must be a non-negative integer\n' >&2
  exit 2
fi

if ! [[ "$UNDO_LAST" =~ ^[0-9]+$ ]]; then
  printf -- '--last must be a non-negative integer\n' >&2
  exit 2
fi

# ---------------------------------------------------------------------------
# Bootstrap: create log dir, initialise CSV.
# ---------------------------------------------------------------------------
mkdir -p "$LOG_DIR"
init_rename_map

# ---------------------------------------------------------------------------
# Instance locking — prevent concurrent runs via flock.
# The lock is released automatically when the script exits (fd 200 closes).
# ---------------------------------------------------------------------------
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
  printf 'Another instance of organize-downloads is already running (lock: %s)\n' "$LOCK_FILE" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Undo subcommand — run and exit early.
# ---------------------------------------------------------------------------
if [[ "$SUBCOMMAND" == "undo" ]]; then
  log_info "Starting undo (last=$UNDO_LAST dry_run=$DRY_RUN)"
  run_undo "$UNDO_LAST"
  exit 0
fi

# ---------------------------------------------------------------------------
# Validate downloads directory.
# ---------------------------------------------------------------------------
if [[ ! -d "$DOWNLOADS_DIR" ]]; then
  die 1 "Downloads directory not found: $DOWNLOADS_DIR"
fi

# ---------------------------------------------------------------------------
# Load extension map from config.
# ---------------------------------------------------------------------------
load_extension_map

# ---------------------------------------------------------------------------
# file_age_minutes FILE
#   Returns the file's age in whole minutes using Linux stat (GNU coreutils).
# ---------------------------------------------------------------------------
file_age_minutes() {
  local file="$1"
  local now mtime
  now="$(date +%s)"
  mtime="$(stat -c '%Y' "$file")"   # GNU stat: %Y = mtime as epoch seconds
  printf '%d\n' $(( (now - mtime) / 60 ))
}

# ---------------------------------------------------------------------------
# cleanup_old_logs
#   Remove monthly log files older than KEEP_LOGS_MONTHS.
#   Skips when KEEP_LOGS_MONTHS=0.
#   Uses GNU date: date -d "N months ago".
# ---------------------------------------------------------------------------
cleanup_old_logs() {
  [[ "$KEEP_LOGS_MONTHS" -eq 0 ]] && return

  local cutoff log_file file_month
  cutoff="$(date -d "${KEEP_LOGS_MONTHS} months ago" '+%Y-%m')"

  for log_file in "$LOG_DIR"/organize-*.log; do
    [[ -f "$log_file" ]] || continue
    file_month="$(basename "$log_file" .log)"
    file_month="${file_month#organize-}"

    # Validate format before comparing (guard against unexpected files).
    if ! [[ "$file_month" =~ ^[0-9]{4}-[0-9]{2}$ ]]; then
      continue
    fi

    # Lexicographic comparison works because YYYY-MM is ISO-sortable.
    if [[ "$file_month" < "$cutoff" ]]; then
      rm -- "$log_file"
      log_info "CLEANUP removed old log: $(basename "$log_file")"
    fi
  done
}

# ---------------------------------------------------------------------------
# Main processing loop
# ---------------------------------------------------------------------------
if [[ "$DRY_RUN" -eq 1 ]]; then
  log_info "Starting dry-run for $DOWNLOADS_DIR (min_age=${MIN_AGE_MINUTES}m)"
else
  log_info "Starting organizer for $DOWNLOADS_DIR (min_age=${MIN_AGE_MINUTES}m)"
fi

moved_count=0
skipped_count=0

# find -maxdepth 1 -type f: only plain files at root level.
# -print0 / read -d '': safe against filenames with spaces, newlines, tabs.
while IFS= read -r -d '' file; do
  filename="$(basename -- "$file")"

  # Skip dotfiles (.gitkeep, .DS_Store, etc.).
  if [[ "$filename" == .* ]]; then
    log_verbose "SKIP dotfile: $filename"
    skipped_count=$(( skipped_count + 1 ))
    continue
  fi

  # Skip partial downloads — never move an in-progress file.
  if is_partial_download "$filename"; then
    log_verbose "SKIP partial: $filename"
    skipped_count=$(( skipped_count + 1 ))
    continue
  fi

  # Skip files too recently modified (still downloading / being written).
  age="$(file_age_minutes "$file")"
  if [[ "$age" -lt "$MIN_AGE_MINUTES" ]]; then
    log_verbose "SKIP recent: $filename (${age}m old, threshold=${MIN_AGE_MINUTES}m)"
    skipped_count=$(( skipped_count + 1 ))
    continue
  fi

  # Resolve destination.
  relative_dir="$(destination_for "$filename")"
  dest_dir="$DOWNLOADS_DIR/$relative_dir"
  dest_path="$(safe_dest_path "$dest_dir" "$filename")"

  # Skip files routing to "partial" (shouldn't reach here, belt-and-suspenders).
  if [[ "$relative_dir" == "07 Misc/partial" ]]; then
    log_verbose "SKIP partial (routing): $filename"
    skipped_count=$(( skipped_count + 1 ))
    continue
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    log_dryrun "MOVE $file → $dest_path"
    record_move "dry-run" "$file" "$dest_path"
  else
    ensure_dest_dir "$dest_dir"
    if mv -- "$file" "$dest_path"; then
      log_info "MOVED $file → $dest_path"
      record_move "moved" "$file" "$dest_path"
    else
      log_error "mv failed: $file → $dest_path"
      skipped_count=$(( skipped_count + 1 ))
      continue
    fi
  fi

  moved_count=$(( moved_count + 1 ))

done < <(find "$DOWNLOADS_DIR" -maxdepth 1 -type f -print0)

log_info "Finished: candidates=$moved_count skipped=$skipped_count dry_run=$DRY_RUN"

cleanup_old_logs
