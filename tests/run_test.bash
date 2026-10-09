#!/usr/bin/env bash

RUNNER_UNDER_TEST="$REPO_ROOT/tests/run"

test_runner_preserves_results_across_skill_module() {
  local test_file output jobs
  test_file="$TEST_TMPDIR/earlier_test.bash"
  cat >"$test_file" <<'EOF'
test_fixture_failure() { fail 'earlier failure must remain visible'; }
test_case 'fixture: earlier failure' test_fixture_failure
EOF
  for jobs in 1 2; do
    if output="$("$RUNNER_UNDER_TEST" --jobs "$jobs" --filter 'fixture:' \
      "$test_file" "$REPO_ROOT/tests/pr_review_followup_skill_test.bash" 2>&1)"; then
      fail 'loading the skill test module erased an earlier failure'
    fi
    assert_runner_output_contains "$output" 'earlier failure must remain visible'
    assert_runner_output_contains "$output" '1 test(s), 1 failure(s)'
  done
}

runner_fixture_is_running() {
  local pid="$1" state

  kill -0 "$pid" 2>/dev/null || return 1
  state="$(ps -o stat= -p "$pid" 2>/dev/null)" || return 0
  # Orphaned zombies have exited even when their parent has not reaped them.
  [[ ! "$state" =~ ^[[:space:]]*Z ]]
}

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

test_runner_interrupts_parallel_workers() {
  local test_file fixture_file marker output rc kind pid deadline
  local -a pids survivors

  test_file="$TEST_TMPDIR/interrupt_test.bash"
  fixture_file="$TEST_TMPDIR/interrupt_fixture.bash"
  marker="$TEST_TMPDIR/interrupt-marker"
  cat >"$fixture_file" <<'EOF'
trap 'exit 143' TERM
# Natural completion must outlast the readiness and termination deadlines.
sleep 30 &
sleeper=$!
printf 'pid\t%s\npid\t%s\nready\n' "$$" "$sleeper" >>"$RUNNER_MARKER"
wait "$sleeper"
EOF
  cat >"$test_file" <<'EOF'
test_fixture_wait() {
  bash "$RUNNER_FIXTURE"
}

test_case 'fixture: first worker waits' test_fixture_wait
test_case 'fixture: second worker waits' test_fixture_wait
EOF

  if output="$(
    RUNNER_UNDER_TEST="$RUNNER_UNDER_TEST" TEST_FILE="$test_file" \
      RUNNER_MARKER="$marker" RUNNER_FIXTURE="$fixture_file" bash -c '
        target=$$
        (
          attempts=0
          while [[ $(grep -c "^ready$" "$RUNNER_MARKER" 2>/dev/null || true) -lt 2 ]] \
            && [[ $attempts -lt 500 ]]; do
            sleep 0.01
            attempts=$((attempts + 1))
          done
          kill -INT "$target"
        ) &
        exec "$RUNNER_UNDER_TEST" --jobs 2 "$TEST_FILE"
      ' 2>&1
  )"; then
    rc=0
  else
    rc=$?
  fi

  pids=()
  while IFS=$'\t' read -r kind pid; do
    [[ "$kind" != pid ]] || pids+=( "$pid" )
  done <"$marker"
  deadline=$((SECONDS + 5))
  while :; do
    survivors=()
    for pid in "${pids[@]}"; do
      if runner_fixture_is_running "$pid"; then
        survivors+=( "$pid" )
      fi
    done
    [[ ${#survivors[@]} -gt 0 && $SECONDS -lt $deadline ]] || break
    sleep 0.01
  done
  if [[ ${#survivors[@]} -gt 0 ]]; then
    for pid in "${survivors[@]}"; do
      kill -TERM "$pid" 2>/dev/null || true
    done
    fail "fixture processes survived interruption: ${survivors[*]}"
  fi
  assert_eq 2 "$(grep -c '^ready$' "$marker")" "fixtures did not reach readiness"
  assert_eq 4 "${#pids[@]}" "fixture process IDs were not recorded"
  assert_eq 130 "$rc" "unexpected interrupted runner status"
  case "$output" in
    *'test(s),'*) fail "interrupted runner reported a completed suite" ;;
  esac
}

test_runner_fixture_liveness_handles_zombies() {
  local fixture_state

  ps() {
    [[ "$*" == "-o stat= -p $$" ]] || return 2
    [[ "$fixture_state" != unavailable ]] || return 1
    printf '%s\n' "$fixture_state"
  }

  fixture_state=' Z+'
  if runner_fixture_is_running "$$"; then
    fail 'zombie fixture treated as running'
  fi
  for fixture_state in S unavailable; do
    runner_fixture_is_running "$$" || fail "live fixture ignored: $fixture_state"
  done
}

test_runner_does_not_leak_job_override() {
  local test_file output

  test_file="$TEST_TMPDIR/jobs_test.bash"
  cat >"$test_file" <<'EOF'
test_fixture_no_job_override() {
  [[ -z "${TEST_JOBS+x}" ]] || fail 'TEST_JOBS leaked into test case'
}

test_case 'fixture: runner controls are isolated' test_fixture_no_job_override
EOF

  output="$(TEST_JOBS=2 "$RUNNER_UNDER_TEST" "$test_file")"
  assert_runner_output_contains "$output" \
    'ok 1 - fixture: runner controls are isolated'
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
test_case 'test runner: interrupts parallel workers' \
  test_runner_interrupts_parallel_workers
test_case 'test runner: fixture liveness distinguishes zombies' \
  test_runner_fixture_liveness_handles_zombies
test_case 'test runner: does not leak job override' \
  test_runner_does_not_leak_job_override
test_case 'test runner: skill module preserves earlier failures and counts' \
  test_runner_preserves_results_across_skill_module
