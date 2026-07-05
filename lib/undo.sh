#!/usr/bin/env bash
# lib/undo.sh — undo subcommand
#
# Sourced and called by organize-downloads.sh when the first argument is
# "undo". Do NOT execute directly.
#
# Required globals (must be set before sourcing):
#   RENAME_MAP  — path to rename-map.csv
#   DRY_RUN     — 1 = preview only, 0 = actually reverse moves
#   VERBOSE     — passed through to log helpers from core.sh
#
# Exports:
#   run_undo LAST_N
#     Read rename-map.csv in reverse (LIFO), reverse up to LAST_N
#     "moved" actions. 0 means all.

# ---------------------------------------------------------------------------
# _undo_parse_csv
#   Parse rename-map.csv into parallel arrays (pure bash, no awk/python).
#   Populates:
#     _CSV_TIMESTAMPS[]
#     _CSV_ACTIONS[]
#     _CSV_SOURCES[]
#     _CSV_DESTINATIONS[]
# ---------------------------------------------------------------------------
_undo_parse_csv() {
  _CSV_TIMESTAMPS=()
  _CSV_ACTIONS=()
  _CSV_SOURCES=()
  _CSV_DESTINATIONS=()

  if [[ ! -f "$RENAME_MAP" ]]; then
    die 1 "rename-map.csv not found: $RENAME_MAP"
  fi

  local line_no=0
  local ts action src dst raw
  while IFS= read -r raw; do
    line_no=$(( line_no + 1 ))
    # Skip header.
    [[ "$line_no" -eq 1 ]] && continue
    # Skip blank lines.
    [[ -z "$raw" ]] && continue
    raw="${raw%$'\r'}"

    # Strip surrounding quotes from each field (RFC 4180 quoted CSV).
    # Pattern: "val","val","val","val"
    # Allow doubled quotes inside each field by matching repeated "" or
    # non-quote characters, then unescape after capture.
    if [[ "$raw" =~ ^\"((\"\"|[^\"])*)\",\"((\"\"|[^\"])*)\",\"((\"\"|[^\"])*)\",\"((\"\"|[^\"])*)\"$ ]]; then
      ts="${BASH_REMATCH[1]}"
      action="${BASH_REMATCH[3]}"
      src="${BASH_REMATCH[5]}"
      dst="${BASH_REMATCH[7]}"

      # Unescape doubled double-quotes → single double-quote.
      ts="${ts//\"\"/\"}"
      action="${action//\"\"/\"}"
      src="${src//\"\"/\"}"
      dst="${dst//\"\"/\"}"

      _CSV_TIMESTAMPS+=("$ts")
      _CSV_ACTIONS+=("$action")
      _CSV_SOURCES+=("$src")
      _CSV_DESTINATIONS+=("$dst")
    else
      log_warn "undo: skipping malformed CSV line $line_no: $raw"
    fi
  done < "$RENAME_MAP"
}

# ---------------------------------------------------------------------------
# run_undo LAST_N
#   Reverse up to LAST_N "moved" entries from rename-map.csv, LIFO order.
#   LAST_N=0 means reverse all "moved" entries.
# ---------------------------------------------------------------------------
run_undo() {
  local last_n="${1:-0}"
  local reversed=0
  local skipped=0

  _undo_parse_csv

  local total="${#_CSV_ACTIONS[@]}"
  if [[ "$total" -eq 0 ]]; then
    log_info "undo: rename-map.csv is empty, nothing to undo."
    return 0
  fi

  # Iterate in reverse (LIFO).
  local i
  for (( i = total - 1; i >= 0; i-- )); do
    local action="${_CSV_ACTIONS[$i]}"
    local src="${_CSV_SOURCES[$i]}"
    local dst="${_CSV_DESTINATIONS[$i]}"
    local ts="${_CSV_TIMESTAMPS[$i]}"

    # Only reverse actual moves (not dry-run records).
    if [[ "$action" != "moved" ]]; then
      continue
    fi

    # Stop if we've reversed the requested count.
    if [[ "$last_n" -gt 0 && "$reversed" -ge "$last_n" ]]; then
      break
    fi

    # Validate: destination (where file was moved TO) must exist now.
    if [[ ! -f "$dst" ]]; then
      log_warn "undo: destination no longer exists, skipping: $dst"
      skipped=$(( skipped + 1 ))
      continue
    fi

    # Validate: original source location must be free (or at least not a file).
    if [[ -f "$src" ]]; then
      log_warn "undo: source path already occupied, skipping: $src"
      skipped=$(( skipped + 1 ))
      continue
    fi

    # Ensure source directory still exists (e.g. ~/Downloads).
    local src_dir
    src_dir="$(dirname "$src")"
    if [[ ! -d "$src_dir" ]]; then
      log_warn "undo: source directory gone, skipping: $src_dir"
      skipped=$(( skipped + 1 ))
      continue
    fi

    if [[ "$DRY_RUN" -eq 1 ]]; then
      log_dryrun "UNDO would move: $dst → $src  (originally moved at $ts)"
      reversed=$(( reversed + 1 ))
    else
      if mv "$dst" "$src"; then
        log_info "UNDO moved: $dst → $src"
        record_move "undone" "$dst" "$src"
        reversed=$(( reversed + 1 ))
      else
        log_error "undo: mv failed for $dst → $src"
        skipped=$(( skipped + 1 ))
      fi
    fi
  done

  log_info "undo: reversed=$reversed skipped=$skipped dry_run=$DRY_RUN"
}
