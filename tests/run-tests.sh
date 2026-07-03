#!/usr/bin/env bash
# tests/run-tests.sh — test runner (no external framework)
#
# Usage:
#   ./tests/run-tests.sh                         # run all test-*.sh files
#   ./tests/run-tests.sh tests/test-routing.sh   # run a single file
#
# Exit code: 0 if all tests pass, 1 if any test fails.
#
# Design: each test file is sourced inside a subshell. Assertion helpers are
# defined here and visible to sourced files. Counters are written to a tmpfile
# to survive the subshell boundary.

set -euo pipefail

TESTS_DIR="$(dirname "$(readlink -f "$0")")"
SCRIPT_DIR="$(dirname "$TESTS_DIR")"
export SCRIPT_DIR

# Shared counter file (written by assert helpers, read by runner after each file).
COUNTER_FILE="$(mktemp)"
printf '0 0\n' > "$COUNTER_FILE"
export COUNTER_FILE

# ---------------------------------------------------------------------------
# Assertion helpers — exported so sourced test files can call them.
# ---------------------------------------------------------------------------

# _inc_counter PASS_DELTA FAIL_DELTA
_inc_counter() {
  local old_pass old_fail
  read -r old_pass old_fail < "$COUNTER_FILE"
  printf '%d %d\n' $(( old_pass + $1 )) $(( old_fail + $2 )) > "$COUNTER_FILE"
}

# begin "test name" — declare the test currently being asserted.
CURRENT_TEST=""
begin() {
  CURRENT_TEST="$1"
}
export -f begin

# assert_eq EXPECTED ACTUAL
assert_eq() {
  local expected="$1" actual="$2"
  if [[ "$expected" == "$actual" ]]; then
    printf '  ✓  %s\n' "$CURRENT_TEST"
    _inc_counter 1 0
  else
    printf '  ✗  %s\n' "$CURRENT_TEST"
    printf '       expected: %q\n' "$expected"
    printf '       actual:   %q\n' "$actual"
    _inc_counter 0 1
  fi
}
export -f assert_eq

# assert_true EXIT_CODE  (0 = pass)
assert_true() {
  if [[ "${1:-1}" -eq 0 ]]; then
    printf '  ✓  %s\n' "$CURRENT_TEST"
    _inc_counter 1 0
  else
    printf '  ✗  %s (expected true/0, got %s)\n' "$CURRENT_TEST" "${1:-?}"
    _inc_counter 0 1
  fi
}
export -f assert_true

# assert_false EXIT_CODE  (non-zero = pass)
assert_false() {
  if [[ "${1:-0}" -ne 0 ]]; then
    printf '  ✓  %s\n' "$CURRENT_TEST"
    _inc_counter 1 0
  else
    printf '  ✗  %s (expected false/non-0, got 0)\n' "$CURRENT_TEST"
    _inc_counter 0 1
  fi
}
export -f assert_false

export -f _inc_counter

# ---------------------------------------------------------------------------
# Collect test files.
# ---------------------------------------------------------------------------
if [[ "$#" -gt 0 ]]; then
  test_files=("$@")
else
  mapfile -t test_files < <(find "$TESTS_DIR" -maxdepth 1 -name 'test-*.sh' | sort)
fi

if [[ "${#test_files[@]}" -eq 0 ]]; then
  printf 'No test files found in %s\n' "$TESTS_DIR" >&2
  rm -f "$COUNTER_FILE"
  exit 1
fi

# ---------------------------------------------------------------------------
# Run each test file.
# ---------------------------------------------------------------------------
for test_file in "${test_files[@]}"; do
  printf '\n── %s ──\n' "$(basename "$test_file")"
  # Reset per-file counter.
  printf '0 0\n' > "$COUNTER_FILE"

  # Source inside a subshell so each file gets a clean variable scope but
  # still has access to the exported helpers and COUNTER_FILE.
  if ! (
    set -euo pipefail
    CURRENT_TEST=""
    # shellcheck source=/dev/null
    source "$test_file"
  ); then
    printf '  ✗  (test file exited with error)\n'
    _inc_counter 0 1
  fi

  read -r file_pass file_fail < "$COUNTER_FILE"
  printf '  %d passed, %d failed\n' "$file_pass" "$file_fail"
done

# ---------------------------------------------------------------------------
# Final tally.
# ---------------------------------------------------------------------------
# Re-run to collect totals — re-source all and tally.
# Simpler: accumulate across files by reading the counter after each file.
# The current design resets per-file; collect totals differently.

# Re-run collecting grand totals.
printf '0 0\n' > "$COUNTER_FILE"

for test_file in "${test_files[@]}"; do
  (
    set -euo pipefail
    CURRENT_TEST=""
    source "$test_file"
  ) > /dev/null 2>&1 || true
done

read -r total_pass total_fail < "$COUNTER_FILE"
rm -f "$COUNTER_FILE"

printf '\n══════════════════════════════\n'
printf 'Results: %d passed, %d failed\n' "$total_pass" "$total_fail"
printf '══════════════════════════════\n'

[[ "$total_fail" -eq 0 ]]
