#!/bin/bash

set -u

DOWNLOADS_DIR="${DOWNLOADS_DIR:-$HOME/Downloads}"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_DIR="${LOG_DIR:-$PROJECT_DIR/logs}"
LOG_FILE="$LOG_DIR/organize-$(date '+%Y-%m').log"
RENAME_MAP="$LOG_DIR/rename-map.csv"
DRY_RUN=0
MIN_AGE_MINUTES="${MIN_AGE_MINUTES:-10}"

usage() {
  cat <<'USAGE'
Usage: ./organize-downloads.sh [--dry-run] [--downloads-dir PATH] [--min-age-minutes N]

Options:
  --dry-run              Preview moves without changing files.
  --downloads-dir PATH   Override the Downloads folder. Default: ~/Downloads.
  --min-age-minutes N    Skip files modified in the last N minutes. Default: 10.
  -h, --help             Show this help.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --downloads-dir)
      if [ "$#" -lt 2 ]; then
        echo "Missing value for --downloads-dir" >&2
        exit 2
      fi
      DOWNLOADS_DIR="$2"
      shift 2
      ;;
    --min-age-minutes)
      if [ "$#" -lt 2 ]; then
        echo "Missing value for --min-age-minutes" >&2
        exit 2
      fi
      MIN_AGE_MINUTES="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if ! [[ "$MIN_AGE_MINUTES" =~ ^[0-9]+$ ]]; then
  echo "--min-age-minutes must be a non-negative integer" >&2
  exit 2
fi

mkdir -p "$LOG_DIR"

if [ ! -f "$RENAME_MAP" ]; then
  printf 'timestamp,action,source,destination\n' > "$RENAME_MAP"
fi

log() {
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG_FILE"
}

csv_escape() {
  printf '%s' "$1" | sed 's/"/""/g'
}

record_move() {
  local action="$1"
  local source="$2"
  local destination="$3"
  printf '"%s","%s","%s","%s"\n' \
    "$(date '+%Y-%m-%d %H:%M:%S')" \
    "$(csv_escape "$action")" \
    "$(csv_escape "$source")" \
    "$(csv_escape "$destination")" >> "$RENAME_MAP"
}

ensure_directories() {
  mkdir -p \
    "$DOWNLOADS_DIR/00 Baru - Inbox" \
    "$DOWNLOADS_DIR/01 Images/png" \
    "$DOWNLOADS_DIR/01 Images/jpg-jpeg" \
    "$DOWNLOADS_DIR/01 Images/heic" \
    "$DOWNLOADS_DIR/01 Images/gif-webp-avif" \
    "$DOWNLOADS_DIR/02 Videos/mov" \
    "$DOWNLOADS_DIR/02 Videos/mp4" \
    "$DOWNLOADS_DIR/03 Documents/pdf" \
    "$DOWNLOADS_DIR/03 Documents/docx" \
    "$DOWNLOADS_DIR/03 Documents/csv" \
    "$DOWNLOADS_DIR/04 Audio/mp3" \
    "$DOWNLOADS_DIR/04 Audio/wav" \
    "$DOWNLOADS_DIR/05 Design/psd" \
    "$DOWNLOADS_DIR/05 Design/svg" \
    "$DOWNLOADS_DIR/06 Installers/dmg" \
    "$DOWNLOADS_DIR/06 Installers/pkg" \
    "$DOWNLOADS_DIR/07 Misc/no-extension" \
    "$DOWNLOADS_DIR/07 Misc/pkpass" \
    "$DOWNLOADS_DIR/07 Misc/unknown"
}

destination_for_extension() {
  local extension="$1"

  case "$extension" in
    png) echo "01 Images/png" ;;
    jpg|jpeg) echo "01 Images/jpg-jpeg" ;;
    heic) echo "01 Images/heic" ;;
    gif|webp|avif) echo "01 Images/gif-webp-avif" ;;
    mov) echo "02 Videos/mov" ;;
    mp4) echo "02 Videos/mp4" ;;
    pdf) echo "03 Documents/pdf" ;;
    docx) echo "03 Documents/docx" ;;
    csv) echo "03 Documents/csv" ;;
    mp3) echo "04 Audio/mp3" ;;
    wav) echo "04 Audio/wav" ;;
    psd) echo "05 Design/psd" ;;
    svg) echo "05 Design/svg" ;;
    dmg) echo "06 Installers/dmg" ;;
    pkg) echo "06 Installers/pkg" ;;
    pkpass) echo "07 Misc/pkpass" ;;
    "") echo "07 Misc/no-extension" ;;
    *) echo "07 Misc/unknown" ;;
  esac
}

safe_destination_path() {
  local destination_dir="$1"
  local filename="$2"
  local base extension candidate counter

  candidate="$destination_dir/$filename"
  if [ ! -e "$candidate" ]; then
    printf '%s\n' "$candidate"
    return
  fi

  if [[ "$filename" == *.* && "$filename" != .* ]]; then
    base="${filename%.*}"
    extension=".${filename##*.}"
  else
    base="$filename"
    extension=""
  fi

  counter=1
  while true; do
    candidate="$destination_dir/$base ($counter)$extension"
    if [ ! -e "$candidate" ]; then
      printf '%s\n' "$candidate"
      return
    fi
    counter=$((counter + 1))
  done
}

file_age_minutes() {
  local file="$1"
  local now modified

  now="$(date +%s)"
  modified="$(stat -f %m "$file")"
  echo $(((now - modified) / 60))
}

if [ ! -d "$DOWNLOADS_DIR" ]; then
  echo "Downloads directory not found: $DOWNLOADS_DIR" >&2
  exit 1
fi

ensure_directories

if [ "$DRY_RUN" -eq 1 ]; then
  log "Starting dry run for $DOWNLOADS_DIR"
else
  log "Starting organizer for $DOWNLOADS_DIR"
fi

moved_count=0
skipped_count=0

while IFS= read -r -d '' file; do
  filename="$(basename "$file")"

  if [ ! -f "$file" ]; then
    skipped_count=$((skipped_count + 1))
    continue
  fi

  if [[ "$filename" == .* ]]; then
    log "SKIP hidden file: $filename"
    skipped_count=$((skipped_count + 1))
    continue
  fi

  age="$(file_age_minutes "$file")"
  if [ "$age" -lt "$MIN_AGE_MINUTES" ]; then
    log "SKIP recent file: $filename (${age}m old)"
    skipped_count=$((skipped_count + 1))
    continue
  fi

  if [[ "$filename" == *.* && "$filename" != .* ]]; then
    extension="$(printf '%s' "${filename##*.}" | tr '[:upper:]' '[:lower:]')"
  else
    extension=""
  fi

  relative_dir="$(destination_for_extension "$extension")"
  destination_dir="$DOWNLOADS_DIR/$relative_dir"
  destination_path="$(safe_destination_path "$destination_dir" "$filename")"

  if [ "$DRY_RUN" -eq 1 ]; then
    log "DRY-RUN move: $file -> $destination_path"
    record_move "dry-run" "$file" "$destination_path"
  else
    mv "$file" "$destination_path"
    log "MOVED: $file -> $destination_path"
    record_move "moved" "$file" "$destination_path"
  fi

  moved_count=$((moved_count + 1))
done < <(find "$DOWNLOADS_DIR" -maxdepth 1 -type f -print0)

log "Finished. candidates=$moved_count skipped=$skipped_count dry_run=$DRY_RUN"
