#!/usr/bin/env bash

TESTS_DISCOVERED=0
TESTS_MATCHED=0
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

test_name_matches_filters() {
  local name="$1"
  local filter

  [[ ${#TEST_FILTERS[@]} -gt 0 ]] || return 0
  for filter in "${TEST_FILTERS[@]}"; do
    case "$name" in
      *"$filter"*) return 0 ;;
    esac
  done
  return 1
}

write_test_result() {
  local ordinal="$1"
  local status="$2"
  local name="$3"
  local output="$4"
  local result_path

  printf -v result_path '%s/result-%06d' "$TESTS_RESULTS_DIR" "$ordinal"
  {
    printf '%s\t%s\n' "$status" "$name"
    [[ -z "$output" ]] || printf '%s\n' "$output"
  } >"$result_path"
}

test_case() {
  local name="$1"
  local fn="$2"
  local test_tmp output rc status

  TESTS_DISCOVERED=$((TESTS_DISCOVERED + 1))
  test_name_matches_filters "$name" || return 0
  TESTS_MATCHED=$((TESTS_MATCHED + 1))

  if [[ "${TESTS_LIST_ONLY:-0}" -eq 1 ]]; then
    printf '%s\n' "$name"
    return 0
  fi

  if [[ -n "${TESTS_SHARD_COUNT:-}" ]] \
    && (( (TESTS_MATCHED - 1) % TESTS_SHARD_COUNT != TESTS_SHARD_INDEX )); then
    return 0
  fi

  TESTS_RUN=$((TESTS_RUN + 1))
  test_tmp="$TESTS_TMP_ROOT/test-$TESTS_DISCOVERED"
  mkdir -p "$test_tmp"

  set +e
  output="$(
    {
      set -euo pipefail
      export TEST_TMPDIR="$test_tmp"
      unset TESTS_WORKER TESTS_SHARD_COUNT TESTS_SHARD_INDEX TESTS_RESULTS_DIR
      "$fn"
    } 2>&1
  )"
  rc=$?
  set -e

  if [[ $rc -eq 0 ]]; then
    status=ok
  else
    status=failed
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi

  if [[ -n "${TESTS_RESULTS_DIR:-}" ]]; then
    write_test_result "$TESTS_MATCHED" "$status" "$name" "$output"
  elif [[ "$status" = ok ]]; then
    printf 'ok %d - %s\n' "$TESTS_RUN" "$name"
  else
    printf 'not ok %d - %s\n' "$TESTS_RUN" "$name"
    [[ -z "$output" ]] || printf '%s\n' "$output" | sed 's/^/    /'
  fi
}

finish_tests() {
  if [[ "${TESTS_LIST_ONLY:-0}" -eq 1 ]]; then
    if [[ $TESTS_MATCHED -eq 0 ]]; then
      printf 'no tests matched the requested selection\n' >&2
      return 1
    fi
    return 0
  fi

  if [[ -n "${TESTS_RESULTS_DIR:-}" ]]; then
    printf '%d %d %d %d\n' \
      "$TESTS_DISCOVERED" "$TESTS_MATCHED" "$TESTS_RUN" "$TESTS_FAILED" \
      >"$TESTS_RESULTS_DIR/stats-$TESTS_SHARD_INDEX"
    [[ $TESTS_FAILED -eq 0 ]]
    return
  fi

  if [[ $TESTS_MATCHED -eq 0 ]]; then
    printf 'no tests matched the requested selection\n' >&2
    return 1
  fi
  printf '\n%d test(s), %d failure(s)\n' "$TESTS_RUN" "$TESTS_FAILED"
  [[ $TESTS_FAILED -eq 0 ]]
}
