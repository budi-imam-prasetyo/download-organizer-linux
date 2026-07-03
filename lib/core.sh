#!/usr/bin/env bash
# lib/core.sh — shared primitives: logging, error handling, CSV audit trail
#
# Sourced by organize-downloads.sh and lib/undo.sh.
# Do NOT execute directly.
#
# Required globals (must be set before sourcing):
#   LOG_FILE      — path to current monthly log file
#   RENAME_MAP    — path to rename-map.csv
#   VERBOSE       — 1 = print verbose messages, 0 = quiet
#   DRY_RUN       — 1 = dry-run mode, 0 = live mode

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

# log LEVEL message...
#   Appends a timestamped line to LOG_FILE and prints to stdout.
#   LEVEL = INFO | WARN | ERROR | VERBOSE | DRY-RUN
#   VERBOSE lines are suppressed when VERBOSE=0.
log() {
  local level="$1"
  shift
  local message="$*"
  local timestamp
  timestamp="$(date '+%Y-%m-%d %H:%M:%S')"

  if [[ "$level" == "VERBOSE" && "${VERBOSE:-0}" -eq 0 ]]; then
    # Still write verbose entries to log file for full audit, but don't print.
    printf '%s [%s] %s\n' "$timestamp" "$level" "$message" >> "$LOG_FILE"
    return
  fi

  local line
  line="$(printf '%s [%s] %s' "$timestamp" "$level" "$message")"
  printf '%s\n' "$line" | tee -a "$LOG_FILE"
}

# Convenience wrappers.
log_info()    { log "INFO"    "$@"; }
log_warn()    { log "WARN"    "$@"; }
log_error()   { log "ERROR"   "$@"; }
log_verbose() { log "VERBOSE" "$@"; }
log_dryrun()  { log "DRY-RUN" "$@"; }

# ---------------------------------------------------------------------------
# Fatal error — log, print to stderr, exit non-zero.
# Usage: die [exit_code] message
#   If first arg is a number it is used as exit code; default is 1.
# ---------------------------------------------------------------------------
die() {
  local code=1
  if [[ "$1" =~ ^[0-9]+$ ]]; then
    code="$1"
    shift
  fi
  log_error "$*"
  exit "$code"
}

# ---------------------------------------------------------------------------
# CSV audit trail helpers
# ---------------------------------------------------------------------------

# csv_escape VALUE — double-quote any double-quotes (RFC 4180).
csv_escape() {
  printf '%s' "$1" | sed 's/"/""/g'
}

# record_move ACTION SOURCE DESTINATION
#   Appends one row to rename-map.csv.
#   Uses a temp file + atomic mv so a mid-write kill never corrupts the CSV.
record_move() {
  local action="$1"
  local source="$2"
  local destination="$3"
  local tmpfile

  tmpfile="$(mktemp "${RENAME_MAP}.XXXXXX")"

  # Copy existing content then append new row.
  if [[ -f "$RENAME_MAP" ]]; then
    cat "$RENAME_MAP" > "$tmpfile"
  else
    printf 'timestamp,action,source,destination\n' > "$tmpfile"
  fi

  printf '"%s","%s","%s","%s"\n' \
    "$(date '+%Y-%m-%d %H:%M:%S')" \
    "$(csv_escape "$action")" \
    "$(csv_escape "$source")" \
    "$(csv_escape "$destination")" >> "$tmpfile"

  # Atomic replace — mv on the same filesystem is a single syscall.
  mv "$tmpfile" "$RENAME_MAP"
}

# init_rename_map — create rename-map.csv with header if it does not exist.
init_rename_map() {
  if [[ ! -f "$RENAME_MAP" ]]; then
    printf 'timestamp,action,source,destination\n' > "$RENAME_MAP"
  fi
}
