#!/usr/bin/env bash

TESTS_RUN=0
TESTS_FAILED=0
TESTS_TMP_PARENT="${TMPDIR:-/tmp}"
TESTS_TMP_PARENT="${TESTS_TMP_PARENT%/}"
TESTS_TMP_ROOT="$(mktemp -d "$TESTS_TMP_PARENT/portables-tests.XXXXXX")"

cleanup_tests() {
  [[ -n "${TESTS_TMP_ROOT:-}" && -d "$TESTS_TMP_ROOT" ]] && rm -rf "$TESTS_TMP_ROOT"
}

trap cleanup_tests EXIT

fail() {
  printf '    %s\n' "$*" >&2
  return 1
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local message="${3:-values differ}"

  if [[ "$actual" != "$expected" ]]; then
    fail "$message: expected [$expected], got [$actual]"
  fi
}

assert_exists() {
  local path="$1"
  [[ -e "$path" || -L "$path" ]] || fail "expected path to exist: $path"
}

assert_not_exists() {
  local path="$1"
  [[ ! -e "$path" && ! -L "$path" ]] || fail "expected path not to exist: $path"
}

assert_symlink_to() {
  local path="$1"
  local expected_target="$2"
  local actual_target

  [[ -L "$path" ]] || fail "expected symlink: $path"
  actual_target="$(readlink "$path")"
  assert_eq "$expected_target" "$actual_target" "unexpected symlink target for $path"
}

assert_file_contents() {
  local path="$1"
  local expected="$2"
  local actual

  [[ -f "$path" ]] || fail "expected file: $path"
  actual="$(cat "$path")"
  assert_eq "$expected" "$actual" "unexpected contents for $path"
}

test_case() {
  local name="$1"
  local fn="$2"
  local test_tmp
  local output
  local rc

  TESTS_RUN=$((TESTS_RUN + 1))
  test_tmp="$TESTS_TMP_ROOT/test-$TESTS_RUN"
  mkdir -p "$test_tmp"

  set +e
  output="$(
    {
      set -euo pipefail
      export TEST_TMPDIR="$test_tmp"
      "$fn"
    } 2>&1
  )"
  rc=$?
  set -e

  if [[ $rc -eq 0 ]]; then
    printf 'ok %d - %s\n' "$TESTS_RUN" "$name"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    printf 'not ok %d - %s\n' "$TESTS_RUN" "$name"
    [[ -z "$output" ]] || printf '%s\n' "$output" | sed 's/^/    /'
  fi
}

finish_tests() {
  printf '\n%d test(s), %d failure(s)\n' "$TESTS_RUN" "$TESTS_FAILED"
  [[ $TESTS_FAILED -eq 0 ]]
}
