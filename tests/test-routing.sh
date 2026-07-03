#!/usr/bin/env bash
# tests/test-routing.sh — unit tests for destination_for and is_partial_download
#
# Sources lib/routing.sh directly. Requires EXTENSIONS_CONF and a minimal
# LOG_FILE/VERBOSE to satisfy core.sh logging.

set -euo pipefail

# Minimal stubs so core.sh logging doesn't fail.
LOG_FILE="/dev/null"
VERBOSE=0
RENAME_MAP="/dev/null"

# shellcheck source=../lib/core.sh
source "$SCRIPT_DIR/lib/core.sh"

EXTENSIONS_CONF="$SCRIPT_DIR/config/extensions.conf"
# shellcheck source=../lib/routing.sh
source "$SCRIPT_DIR/lib/routing.sh"

load_extension_map

# ---------------------------------------------------------------------------
# is_partial_download
# ---------------------------------------------------------------------------
begin "is_partial_download: .crdownload"
is_partial_download "video.crdownload"; assert_true $?

begin "is_partial_download: .part"
is_partial_download "archive.tar.gz.part"; assert_true $?

begin "is_partial_download: .download"
is_partial_download "file.download"; assert_true $?

begin "is_partial_download: .tmp"
is_partial_download "something.tmp"; assert_true $?

begin "is_partial_download: normal file is NOT partial"
is_partial_download "report.pdf"; assert_false $?

begin "is_partial_download: .mp4 is NOT partial"
is_partial_download "movie.mp4"; assert_false $?

# ---------------------------------------------------------------------------
# destination_for — images
# ---------------------------------------------------------------------------
begin "destination_for: png"
assert_eq "01 Images/png" "$(destination_for "screenshot.png")"

begin "destination_for: jpg"
assert_eq "01 Images/jpg-jpeg" "$(destination_for "photo.jpg")"

begin "destination_for: jpeg"
assert_eq "01 Images/jpg-jpeg" "$(destination_for "photo.jpeg")"

begin "destination_for: webp"
assert_eq "01 Images/webp" "$(destination_for "image.webp")"

begin "destination_for: heic"
assert_eq "01 Images/heic" "$(destination_for "iphone.heic")"

begin "destination_for: UPPERCASE extension normalised"
assert_eq "01 Images/png" "$(destination_for "IMAGE.PNG")"

# ---------------------------------------------------------------------------
# destination_for — videos
# ---------------------------------------------------------------------------
begin "destination_for: mkv"
assert_eq "02 Videos/mkv" "$(destination_for "movie.mkv")"

begin "destination_for: mp4"
assert_eq "02 Videos/mp4" "$(destination_for "clip.mp4")"

begin "destination_for: avi"
assert_eq "02 Videos/avi" "$(destination_for "old.avi")"

# ---------------------------------------------------------------------------
# destination_for — audio
# ---------------------------------------------------------------------------
begin "destination_for: mp3"
assert_eq "03 Audio/mp3" "$(destination_for "song.mp3")"

begin "destination_for: flac"
assert_eq "03 Audio/flac" "$(destination_for "lossless.flac")"

begin "destination_for: opus"
assert_eq "03 Audio/opus" "$(destination_for "podcast.opus")"

# ---------------------------------------------------------------------------
# destination_for — documents
# ---------------------------------------------------------------------------
begin "destination_for: pdf"
assert_eq "04 Documents/pdf" "$(destination_for "report.pdf")"

begin "destination_for: docx"
assert_eq "04 Documents/word" "$(destination_for "letter.docx")"

begin "destination_for: xlsx"
assert_eq "04 Documents/spreadsheet" "$(destination_for "budget.xlsx")"

begin "destination_for: epub"
assert_eq "04 Documents/ebooks" "$(destination_for "book.epub")"

begin "destination_for: md"
assert_eq "04 Documents/text" "$(destination_for "notes.md")"

# ---------------------------------------------------------------------------
# destination_for — archives & installers
# ---------------------------------------------------------------------------
begin "destination_for: zip"
assert_eq "05 Archives/zip" "$(destination_for "assets.zip")"

begin "destination_for: tar.gz → gz mapping"
assert_eq "05 Archives/tar" "$(destination_for "source.tar.gz")"

begin "destination_for: deb"
assert_eq "06 Installers/deb" "$(destination_for "package.deb")"

begin "destination_for: AppImage"
assert_eq "06 Installers/appimage" "$(destination_for "App.AppImage")"

begin "destination_for: iso"
assert_eq "06 Installers/iso" "$(destination_for "ubuntu.iso")"

# ---------------------------------------------------------------------------
# destination_for — special cases
# ---------------------------------------------------------------------------
begin "destination_for: no extension"
assert_eq "07 Misc/no-extension" "$(destination_for "Makefile")"

begin "destination_for: unknown extension"
assert_eq "07 Misc/unknown" "$(destination_for "weird.xyz123")"

begin "destination_for: dotfile has no extension"
assert_eq "07 Misc/no-extension" "$(destination_for ".bashrc")"

begin "destination_for: partial .crdownload routed to partial"
assert_eq "07 Misc/partial" "$(destination_for "video.crdownload")"

# ---------------------------------------------------------------------------
# safe_dest_path — collision resolution
# ---------------------------------------------------------------------------
begin "safe_dest_path: no collision returns original path"
TMPDIR_TEST="$(mktemp -d)"
result="$(safe_dest_path "$TMPDIR_TEST" "file.pdf")"
assert_eq "$TMPDIR_TEST/file.pdf" "$result"
rm -rf "$TMPDIR_TEST"

begin "safe_dest_path: one collision → (1) suffix"
TMPDIR_TEST="$(mktemp -d)"
touch "$TMPDIR_TEST/file.pdf"
result="$(safe_dest_path "$TMPDIR_TEST" "file.pdf")"
assert_eq "$TMPDIR_TEST/file (1).pdf" "$result"
rm -rf "$TMPDIR_TEST"

begin "safe_dest_path: two collisions → (2) suffix"
TMPDIR_TEST="$(mktemp -d)"
touch "$TMPDIR_TEST/file.pdf" "$TMPDIR_TEST/file (1).pdf"
result="$(safe_dest_path "$TMPDIR_TEST" "file.pdf")"
assert_eq "$TMPDIR_TEST/file (2).pdf" "$result"
rm -rf "$TMPDIR_TEST"

begin "safe_dest_path: no-extension file collision"
TMPDIR_TEST="$(mktemp -d)"
touch "$TMPDIR_TEST/Makefile"
result="$(safe_dest_path "$TMPDIR_TEST" "Makefile")"
assert_eq "$TMPDIR_TEST/Makefile (1)" "$result"
rm -rf "$TMPDIR_TEST"
