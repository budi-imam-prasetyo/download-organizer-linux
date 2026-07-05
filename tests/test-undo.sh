#!/usr/bin/env bash
# tests/test-undo.sh — unit tests for the undo subcommand
#
# Creates a real temp directory, simulates moves by writing entries to a
# CSV, then verifies that run_undo correctly reverses them.

set -euo pipefail

VERBOSE=0
DRY_RUN=0

# Set up a temp log dir.
TMPDIR_UNDO="$(mktemp -d)"
LOG_DIR="$TMPDIR_UNDO"
LOG_FILE="$TMPDIR_UNDO/test.log"
RENAME_MAP="$TMPDIR_UNDO/rename-map.csv"

# shellcheck source=../lib/core.sh
source "$SCRIPT_DIR/lib/core.sh"

EXTENSIONS_CONF="$SCRIPT_DIR/config/extensions.conf"
# shellcheck source=../lib/routing.sh
source "$SCRIPT_DIR/lib/routing.sh"
# shellcheck source=../lib/undo.sh
source "$SCRIPT_DIR/lib/undo.sh"

init_rename_map

# ---------------------------------------------------------------------------
# Helper: write a CSV row directly (simulates what record_move does).
# ---------------------------------------------------------------------------
csv_row() {
  local action="$1" src="$2" dst="$3"
  local esc_action esc_src esc_dst
  esc_action="${action//\"/\"\"}"
  esc_src="${src//\"/\"\"}"
  esc_dst="${dst//\"/\"\"}"
  printf '"%s","%s","%s","%s"\n' \
    "$(date '+%Y-%m-%d %H:%M:%S')" "$esc_action" "$esc_src" "$esc_dst" >> "$RENAME_MAP"
}

# ---------------------------------------------------------------------------
# Test 1: undo a single move — file goes back to original location.
# ---------------------------------------------------------------------------
begin "undo: single move is reversed"

SRC="$TMPDIR_UNDO/original.pdf"
DST="$TMPDIR_UNDO/04 Documents/pdf/original.pdf"
mkdir -p "$(dirname "$DST")"

# Simulate: file was moved from SRC → DST.
printf 'content' > "$DST"
csv_row "moved" "$SRC" "$DST"

run_undo 0   # undo all

assert_true $([ -f "$SRC" ]; echo $?)

# ---------------------------------------------------------------------------
# Test 1b: quoted CSV fields round-trip correctly through the parser.
# ---------------------------------------------------------------------------
begin "undo: quoted CSV fields with embedded double-quotes are parsed"

rm -f "$RENAME_MAP"; init_rename_map

SRC_QUOTED="$TMPDIR_UNDO/original\"quote.pdf"
DST_QUOTED="$TMPDIR_UNDO/04 Documents/pdf/original\"quote.pdf"
mkdir -p "$(dirname "$DST_QUOTED")"

printf 'content' > "$DST_QUOTED"
csv_row "moved" "$SRC_QUOTED" "$DST_QUOTED"

run_undo 0

assert_true $([ -f "$SRC_QUOTED" ]; echo $?)

# ---------------------------------------------------------------------------
# Test 2: file at destination is gone — undo should skip, not fail.
# ---------------------------------------------------------------------------
begin "undo: missing destination is skipped gracefully"

# Fresh CSV.
rm -f "$RENAME_MAP"; init_rename_map

GHOST_SRC="$TMPDIR_UNDO/ghost.txt"
GHOST_DST="$TMPDIR_UNDO/07 Misc/unknown/ghost.txt"
mkdir -p "$(dirname "$GHOST_DST")"
# Do NOT create GHOST_DST — simulate file was already deleted.

csv_row "moved" "$GHOST_SRC" "$GHOST_DST"
run_undo 0   # should not crash

assert_false $([ -f "$GHOST_SRC" ]; echo $?)

# ---------------------------------------------------------------------------
# Test 3: --last N limits reversals.
# ---------------------------------------------------------------------------
begin "undo --last 1: only reverses the most recent move"

rm -f "$RENAME_MAP"; init_rename_map

SRC_A="$TMPDIR_UNDO/first.pdf"
DST_A="$TMPDIR_UNDO/04 Documents/pdf/first.pdf"
SRC_B="$TMPDIR_UNDO/second.pdf"
DST_B="$TMPDIR_UNDO/04 Documents/pdf/second.pdf"

mkdir -p "$(dirname "$DST_A")"
printf 'a' > "$DST_A"
printf 'b' > "$DST_B"

csv_row "moved" "$SRC_A" "$DST_A"
csv_row "moved" "$SRC_B" "$DST_B"

run_undo 1   # only undo the last one

# second.pdf (most recent) should be back at SRC_B.
assert_true $([ -f "$SRC_B" ]; echo $?)

# ---------------------------------------------------------------------------
# Test 4: dry-run undo does not move anything.
# ---------------------------------------------------------------------------
begin "undo --dry-run: nothing is moved"

rm -f "$RENAME_MAP"; init_rename_map
DRY_RUN=1

SRC_DRY="$TMPDIR_UNDO/dryfile.txt"
DST_DRY="$TMPDIR_UNDO/04 Documents/text/dryfile.txt"
mkdir -p "$(dirname "$DST_DRY")"
printf 'x' > "$DST_DRY"

csv_row "moved" "$SRC_DRY" "$DST_DRY"
run_undo 0

# File should still be at DST (not moved back).
assert_true $([ -f "$DST_DRY" ]; echo $?)
assert_false $([ -f "$SRC_DRY" ]; echo $?)

DRY_RUN=0

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------
rm -rf "$TMPDIR_UNDO"
