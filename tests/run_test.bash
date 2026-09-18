#!/usr/bin/env bash

RUNNER_UNDER_TEST="$REPO_ROOT/tests/run"

assert_runner_output_contains() {
  local output="$1"
  local expected="$2"

  case "$output" in
    *"$expected"*) ;;
    *) fail "expected runner output to contain: $expected" ;;
  esac
}

make_runner_test_file() {
  local path="$1"

  cat >"$path" <<'EOF'
test_fixture_alpha() {
  printf 'alpha\n' >>"$RUNNER_MARKER"
}

test_fixture_beta() {
  printf 'beta\n' >>"$RUNNER_MARKER"
}

test_fixture_gamma() {
  printf 'gamma\n' >>"$RUNNER_MARKER"
}

test_case 'fixture: alpha passes' test_fixture_alpha
test_case 'fixture: beta passes' test_fixture_beta
test_case 'fixture: gamma passes' test_fixture_gamma
EOF
}

test_runner_lists_without_executing() {
  local test_file marker output

  test_file="$TEST_TMPDIR/fixture_test.bash"
  marker="$TEST_TMPDIR/executed"
  make_runner_test_file "$test_file"

  output="$(RUNNER_MARKER="$marker" "$RUNNER_UNDER_TEST" \
    --list --filter 'beta passes' "$test_file")"

  assert_eq 'fixture: beta passes' "$output" "unexpected listed tests"
  assert_not_exists "$marker"
}

test_runner_combines_literal_filters() {
  local test_file marker output

  test_file="$TEST_TMPDIR/fixture_test.bash"
  marker="$TEST_TMPDIR/executed"
  make_runner_test_file "$test_file"

  output="$(RUNNER_MARKER="$marker" "$RUNNER_UNDER_TEST" \
    --filter alpha --filter gamma "$test_file")"

  assert_runner_output_contains "$output" 'ok 1 - fixture: alpha passes'
  assert_runner_output_contains "$output" 'ok 2 - fixture: gamma passes'
  assert_runner_output_contains "$output" '2 test(s), 0 failure(s)'
  assert_file_contents "$marker" $'alpha\ngamma'
}

test_runner_rejects_empty_selections_and_bad_jobs() {
  local test_file marker output

  test_file="$TEST_TMPDIR/fixture_test.bash"
  marker="$TEST_TMPDIR/executed"
  make_runner_test_file "$test_file"

  if output="$(RUNNER_MARKER="$marker" "$RUNNER_UNDER_TEST" \
    --filter absent "$test_file" 2>&1)"; then
    fail "expected an unmatched filter to fail"
  fi
  assert_runner_output_contains "$output" 'no tests matched the requested selection'

  if output="$("$RUNNER_UNDER_TEST" --jobs 0 "$test_file" 2>&1)"; then
    fail "expected an invalid job count to fail"
  fi
  assert_runner_output_contains "$output" 'invalid test job count: 0'
  assert_not_exists "$marker"
}

test_runner_orders_parallel_results_and_failures() {
  local test_file output expected

  test_file="$TEST_TMPDIR/parallel_test.bash"
  cat >"$test_file" <<'EOF'
test_fixture_slow() {
  sleep 0.1
}

test_fixture_failure() {
  fail 'intentional failure'
}

test_fixture_fast() {
  return 0
}

test_case 'fixture: slow passes' test_fixture_slow
test_case 'fixture: failure reports' test_fixture_failure
test_case 'fixture: fast passes' test_fixture_fast
EOF

  if output="$("$RUNNER_UNDER_TEST" --jobs 2 "$test_file" 2>&1)"; then
    fail "expected the parallel fixture failure to fail the run"
  fi

  expected=$'ok 1 - fixture: slow passes\nnot ok 2 - fixture: failure reports'
  assert_runner_output_contains "$output" "$expected"
  assert_runner_output_contains "$output" 'ok 3 - fixture: fast passes'
  assert_runner_output_contains "$output" 'intentional failure'
  assert_runner_output_contains "$output" '3 test(s), 1 failure(s)'
}

test_runner_reports_worker_crashes() {
  local test_file output

  test_file="$TEST_TMPDIR/crash_test.bash"
  printf 'return 7\n' >"$test_file"

  if output="$("$RUNNER_UNDER_TEST" --jobs 2 "$test_file" 2>&1)"; then
    fail "expected worker crashes to fail the run"
  fi
  assert_runner_output_contains "$output" 'did not report results'
}

test_case 'test runner: lists without executing tests' \
  test_runner_lists_without_executing
test_case 'test runner: combines literal filters' \
  test_runner_combines_literal_filters
test_case 'test runner: rejects empty selections and bad jobs' \
  test_runner_rejects_empty_selections_and_bad_jobs
test_case 'test runner: orders parallel results and failures' \
  test_runner_orders_parallel_results_and_failures
test_case 'test runner: reports worker crashes' \
  test_runner_reports_worker_crashes
