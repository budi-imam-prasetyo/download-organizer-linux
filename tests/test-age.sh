#!/usr/bin/env bash
# tests/test-age.sh — unit tests for file age / partial-download skip logic
#
# Uses touch -t to set specific mtimes on temp files, then verifies that
# file_age_minutes returns the right value and that the main loop skips
# or processes accordingly.

set -euo pipefail

LOG_FILE="/dev/null"
VERBOSE=0
RENAME_MAP="/dev/null"

# shellcheck source=../lib/core.sh
source "$SCRIPT_DIR/lib/core.sh"

EXTENSIONS_CONF="$SCRIPT_DIR/config/extensions.conf"
# shellcheck source=../lib/routing.sh
source "$SCRIPT_DIR/lib/routing.sh"

# Inline the same file_age_minutes definition used by the main script.
file_age_minutes() {
  local file="$1"
  local now mtime
  now="$(date +%s)"
  mtime="$(stat -c '%Y' "$file")"
  printf '%d\n' $(( (now - mtime) / 60 ))
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# touch_ago FILE MINUTES_AGO — set file mtime to N minutes in the past.
touch_ago() {
  local file="$1"
  local minutes_ago="$2"
  # Calculate epoch N minutes ago, format as [[CC]YY]MMDDhhmm[.ss]
  local ts
  ts="$(date -d "${minutes_ago} minutes ago" '+%Y%m%d%H%M.%S')"
  touch -t "$ts" "$file"
}

# ---------------------------------------------------------------------------
# Tests: file_age_minutes accuracy
# ---------------------------------------------------------------------------
TMPDIR_AGE="$(mktemp -d)"

begin "file_age_minutes: file set to 30 minutes ago returns ≥ 30"
touch "$TMPDIR_AGE/old.txt"
touch_ago "$TMPDIR_AGE/old.txt" 30
age="$(file_age_minutes "$TMPDIR_AGE/old.txt")"
# Allow ±1 minute for test execution time.
if [[ "$age" -ge 29 && "$age" -le 31 ]]; then
  assert_true 0
else
  assert_true 1
fi

begin "file_age_minutes: file set to 5 minutes ago returns ~5"
touch "$TMPDIR_AGE/recent.txt"
touch_ago "$TMPDIR_AGE/recent.txt" 5
age="$(file_age_minutes "$TMPDIR_AGE/recent.txt")"
if [[ "$age" -ge 4 && "$age" -le 6 ]]; then
  assert_true 0
else
  assert_true 1
fi

begin "file_age_minutes: file set to 0 minutes ago returns 0"
touch "$TMPDIR_AGE/brand-new.txt"
age="$(file_age_minutes "$TMPDIR_AGE/brand-new.txt")"
# Brand new file: age should be 0 or 1.
if [[ "$age" -le 1 ]]; then
  assert_true 0
else
  assert_true 1
fi

rm -rf "$TMPDIR_AGE"

# ---------------------------------------------------------------------------
# Tests: end-to-end skip behaviour (simulate the main loop logic inline)
# ---------------------------------------------------------------------------
TMPDIR_E2E="$(mktemp -d)"

# Pretend this is the Downloads directory.
DOWNLOADS_DIR="$TMPDIR_E2E"
DRY_RUN=1
MIN_AGE_MINUTES=10

load_extension_map

# Create a file that is 20 minutes old → should be moved.
touch "$TMPDIR_E2E/old-document.pdf"
touch_ago "$TMPDIR_E2E/old-document.pdf" 20

# Create a file that is 5 minutes old → should be skipped.
touch "$TMPDIR_E2E/fresh-image.png"
touch_ago "$TMPDIR_E2E/fresh-image.png" 5

# Create a partial download → should be skipped.
touch "$TMPDIR_E2E/downloading.crdownload"
touch_ago "$TMPDIR_E2E/downloading.crdownload" 60

moved=0
skipped=0

while IFS= read -r -d '' file; do
  filename="$(basename -- "$file")"

  [[ "$filename" == .* ]] && { skipped=$(( skipped + 1 )); continue; }

  if is_partial_download "$filename"; then
    skipped=$(( skipped + 1 )); continue
  fi

  age="$(file_age_minutes "$file")"
  if [[ "$age" -lt "$MIN_AGE_MINUTES" ]]; then
    skipped=$(( skipped + 1 )); continue
  fi

  moved=$(( moved + 1 ))
done < <(find "$TMPDIR_E2E" -maxdepth 1 -type f -print0)

begin "end-to-end: 1 old file should be a candidate for move"
assert_eq "1" "$moved"

begin "end-to-end: 2 files should be skipped (fresh + partial)"
assert_eq "2" "$skipped"

rm -rf "$TMPDIR_E2E"
