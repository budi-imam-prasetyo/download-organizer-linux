#!/usr/bin/env bash
# lib/routing.sh — extension-to-folder routing
#
# Sourced by organize-downloads.sh. Do NOT execute directly.
#
# Required globals (must be set before sourcing):
#   EXTENSIONS_CONF  — absolute path to config/extensions.conf
#
# Populates the associative array EXT_MAP after sourcing.
# Provides:
#   load_extension_map   — parse EXTENSIONS_CONF into EXT_MAP
#   destination_for      — map a filename to a relative destination path
#   ensure_dest_dir      — mkdir -p the destination dir on demand
#
# Partial-download filename patterns (browser/downloader suffixes).
# Files matching these are skipped before extension routing.
readonly PARTIAL_PATTERNS=(
  '*.crdownload'   # Chrome
  '*.part'         # Firefox / wget / aria2
  '*.download'     # various
  '*.tmp'          # generic temp
  '*.opdownload'   # Opera
  '*.!ut'          # uTorrent
)

# Associative array: lowercase_extension → relative_path
# Populated by load_extension_map.
declare -gA EXT_MAP=()

# ---------------------------------------------------------------------------
# load_extension_map
#   Parse EXTENSIONS_CONF and populate EXT_MAP.
#   Format: extension=Category/subfolder  (# comments and blank lines ignored)
#   Last-entry-wins for duplicate extensions (matches documented behaviour).
# ---------------------------------------------------------------------------
load_extension_map() {
  if [[ ! -f "$EXTENSIONS_CONF" ]]; then
    die 1 "extensions.conf not found: $EXTENSIONS_CONF"
  fi

  local line ext folder
  while IFS= read -r line; do
    # Strip inline comments and leading/trailing whitespace.
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" ]] && continue

    # Must contain exactly one '='.
    if [[ "$line" != *=* ]]; then
      log_warn "routing: malformed line in extensions.conf, skipping: '$line'"
      continue
    fi

    ext="${line%%=*}"
    folder="${line#*=}"

    # Normalize: lowercase extension, no leading dot.
    ext="${ext,,}"
    ext="${ext#.}"

    if [[ -z "$ext" || -z "$folder" ]]; then
      log_warn "routing: empty key or value in extensions.conf, skipping: '$line'"
      continue
    fi

    EXT_MAP["$ext"]="$folder"
  done < "$EXTENSIONS_CONF"
}

# ---------------------------------------------------------------------------
# is_partial_download FILENAME
#   Returns 0 (true) if the filename matches a known partial-download pattern.
# ---------------------------------------------------------------------------
is_partial_download() {
  local filename="$1"
  local pattern
  for pattern in "${PARTIAL_PATTERNS[@]}"; do
    # Use bash glob matching (case-insensitive).
    if [[ "${filename,,}" == ${pattern,,} ]]; then
      return 0
    fi
  done
  return 1
}

# ---------------------------------------------------------------------------
# destination_for FILENAME
#   Prints the relative destination path for FILENAME.
#   Callers prepend DOWNLOADS_DIR to get the absolute destination dir.
#
#   Resolution order:
#     1. Partial-download pattern  → "07 Misc/partial"  (never moved)
#     2. No extension              → "07 Misc/no-extension"
#     3. EXT_MAP lookup            → value from config
#     4. Unknown extension         → "07 Misc/unknown"
# ---------------------------------------------------------------------------
destination_for() {
  local filename="$1"
  local ext=""
  local lower_filename="${filename,,}"

  # Partial downloads are identified before extension routing.
  if is_partial_download "$filename"; then
    printf '%s\n' "07 Misc/partial"
    return
  fi

  # Extract the longest configured extension suffix.
  # This supports compound extensions such as pkg.tar.zst before falling
  # back to the last dot segment.
  if [[ "$lower_filename" == *.* && "$lower_filename" != .* ]]; then
    ext="${lower_filename#*.}"
    while true; do
      if [[ -n "${EXT_MAP[$ext]+set}" ]]; then
        printf '%s\n' "${EXT_MAP[$ext]}"
        return
      fi

      [[ "$ext" != *.* ]] && break
      ext="${ext#*.}"
    done
  fi

  if [[ -z "$ext" ]]; then
    printf '%s\n' "07 Misc/no-extension"
    return
  fi

  printf '%s\n' "07 Misc/unknown"
}

# ---------------------------------------------------------------------------
# ensure_dest_dir ABSOLUTE_DIR
#   Create the directory if it does not exist.
#   On-demand creation: no empty folders are pre-created.
# ---------------------------------------------------------------------------
ensure_dest_dir() {
  local dir="$1"
  if [[ ! -d "$dir" ]]; then
    mkdir -p "$dir" || die 1 "Failed to create directory: $dir"
  fi
}

# ---------------------------------------------------------------------------
# safe_dest_path DEST_DIR FILENAME
#   Prints a collision-free absolute path inside DEST_DIR for FILENAME.
#   If FILENAME already exists, appends " (N)" before the extension:
#     report.pdf → report (1).pdf → report (2).pdf → ...
#   No files are created or moved here — only the path is computed.
# ---------------------------------------------------------------------------
safe_dest_path() {
  local dest_dir="$1"
  local filename="$2"
  local base ext candidate counter

  candidate="$dest_dir/$filename"
  if [[ ! -e "$candidate" ]]; then
    printf '%s\n' "$candidate"
    return
  fi

  # Split into base and extension.
  if [[ "$filename" == *.* && "$filename" != .* ]]; then
    base="${filename%.*}"
    ext=".${filename##*.}"
  else
    base="$filename"
    ext=""
  fi

  counter=1
  while true; do
    candidate="$dest_dir/$base ($counter)$ext"
    if [[ ! -e "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return
    fi
    counter=$(( counter + 1 ))
  done
}
