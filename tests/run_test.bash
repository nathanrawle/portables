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

  output="$(RUNNER_MARKER="$marker" "$RUNNER_UNDER_TEST" --report all \
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

  if output="$("$RUNNER_UNDER_TEST" --report all --jobs 2 "$test_file" 2>&1)"; then
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
  [[ -z "${TESTS_PROGRESS_DIR+x}" && -z "${TESTS_PROGRESS_MANIFEST+x}" \
    && -z "${TESTS_FILE_INDEX+x}" ]] || fail 'progress controls leaked into test case'
}

test_case 'fixture: runner controls are isolated' test_fixture_no_job_override
EOF

  output="$(TEST_JOBS=2 "$RUNNER_UNDER_TEST" --report all "$test_file")"
  assert_runner_output_contains "$output" \
    'ok 1 - fixture: runner controls are isolated'
}

test_runner_report_modes_preserve_failure_status() {
  local test_file="$TEST_TMPDIR/reports_test.bash" output mode rc
  cat >"$test_file" <<'EOF'
test_fixture_pass() { printf 'successful output stays captured\n'; }
test_fixture_fail() { fail 'failure detail stays visible'; }
test_case 'fixture: passing result' test_fixture_pass
test_case 'fixture: failing result' test_fixture_fail
EOF
  rc=0
  output="$("$RUNNER_UNDER_TEST" "$test_file" 2>&1)" || rc=$?
  assert_eq 1 "$rc"
  assert_runner_output_contains "$output" 'not ok 2 - fixture: failing result'
  [[ "$output" != *'ok 1 -'* && "$output" != *$'\033'* ]] || fail 'default captured report is noisy'
  for mode in failed passed all none; do
    rc=0
    output="$("$RUNNER_UNDER_TEST" --jobs 2 --report="$mode" "$test_file" 2>&1)" || rc=$?
    assert_eq 1 "$rc" "report $mode must preserve failure status"
    assert_runner_output_contains "$output" '2 test(s), 1 failure(s)'
    [[ "$output" != *'successful output stays captured'* ]] || fail 'passing output escaped capture'
    case "$mode" in
      failed|all) assert_runner_output_contains "$output" 'failure detail stays visible' ;;
      passed|none) [[ "$output" != *'not ok'* && "$output" != *'failure detail'* ]] || fail 'failure report was not suppressed' ;;
    esac
    case "$mode" in
      passed|all) assert_runner_output_contains "$output" 'ok 1 - fixture: passing result' ;;
      failed|none) [[ "$output" != *'ok 1 -'* ]] || fail 'passing report was not suppressed' ;;
    esac
  done
}

test_runner_validates_report_and_keeps_list_plain() {
  local test_file="$TEST_TMPDIR/options_test.bash" output rc argument
  make_runner_test_file "$test_file"
  for argument in --report --report= --report=invalid; do
    rc=0
    output="$(RUNNER_MARKER="$TEST_TMPDIR/executed" "$RUNNER_UNDER_TEST" \
      "$argument" 2>&1)" || rc=$?
    assert_eq 2 "$rc"
  done
  assert_not_exists "$TEST_TMPDIR/executed"
  output="$("$RUNNER_UNDER_TEST" --list --report none --no-progress --filter beta "$test_file")"
  assert_eq 'fixture: beta passes' "$output"
}

run_runner_terminal() {
  local log="$1" rows="$2" launcher command argument
  shift 2
  launcher="$TEST_TMPDIR/terminal-launcher"
  cat >"$launcher" <<'EOF'
#!/usr/bin/env bash
stty rows "$RUNNER_TERMINAL_ROWS" cols 100
if [[ -n "${RUNNER_TERMINAL_PID_FILE:-}" ]]; then
  printf '%d\n' "$$" >"$RUNNER_TERMINAL_PID_FILE"
fi
exec "$RUNNER_UNDER_TEST" "$@"
EOF
  if [[ "$(uname -s)" == Darwin ]]; then
    TERM=xterm RUNNER_TERMINAL_ROWS="$rows" RUNNER_UNDER_TEST="$RUNNER_UNDER_TEST" \
      script -q -F /dev/null bash "$launcher" "$@" </dev/null >"$log"
  else
    printf -v command '%q %q' bash "$launcher"
    for argument in "$@"; do
      printf -v argument '%q' "$argument"
      command="$command $argument"
    done
    TERM=xterm RUNNER_TERMINAL_ROWS="$rows" RUNNER_UNDER_TEST="$RUNNER_UNDER_TEST" \
      script -q -f -c "$command" /dev/null </dev/null >"$log"
  fi
}

test_runner_terminal_groups_publish_before_completion() {
  local first="$TEST_TMPDIR/first_test.bash" second="$TEST_TMPDIR/second_test.bash"
  local excluded="$TEST_TMPDIR/excluded_test.bash" log="$TEST_TMPDIR/terminal.log"
  local release="$TEST_TMPDIR/release" terminal_pid attempt output cleanup
  command -v script >/dev/null 2>&1 || return 0
  cat >"$first" <<'EOF'
test_fixture_wait() {
  local attempt
  for ((attempt = 0; attempt < 300; attempt++)); do
    [[ ! -f "$RUNNER_RELEASE" ]] || return 0
    sleep 0.02
  done
  fail 'progress did not release the fixture'
}
test_fixture_fail() { fail 'expected fixture failure'; }
test_case 'fixture: selected waiting' test_fixture_wait
test_case 'fixture: selected failure' test_fixture_fail
EOF
  cat >"$second" <<'EOF'
test_fixture_pass() { return 0; }
test_case 'fixture: selected passing' test_fixture_pass
EOF
  cat >"$excluded" <<'EOF'
test_fixture_excluded() { fail 'excluded test executed'; }
test_case 'fixture: unrelated case' test_fixture_excluded
EOF
  RUNNER_RELEASE="$release" run_runner_terminal "$log" 24 --jobs 2 --report none \
    --filter selected "$first" "$second" "$excluded" >"$TEST_TMPDIR/script.log" 2>&1 &
  terminal_pid=$!
  printf -v cleanup 'touch %q; kill %q 2>/dev/null || true; wait %q 2>/dev/null || true' \
    "$release" "$terminal_pid" "$terminal_pid"
  trap "$cleanup" EXIT
  for ((attempt = 0; attempt < 200; attempt++)); do
    output="$(cat "$log" 2>/dev/null || true)"
    [[ "$output" != *RUNNING* || "$output" != *second_test.bash* ]] || break
    sleep 0.02
  done
  assert_runner_output_contains "$output" 'first_test.bash (0/2) QUEUED'
  assert_runner_output_contains "$output" 'second_test.bash (0/1) QUEUED'
  assert_runner_output_contains "$output" RUNNING || {
    fail "terminal capture: $output; script output: $(cat "$TEST_TMPDIR/script.log")"
    return 1
  }
  [[ "$output" != *excluded_test.bash* && "$output" != *'test(s),'* ]] || fail 'selection or live completion is wrong'
  touch "$release"
  wait "$terminal_pid" || true
  trap - EXIT
  output="$(cat "$log")"
  assert_runner_output_contains "$output" 'first_test.bash (2/2) FAIL, 1 failed'
  assert_runner_output_contains "$output" 'second_test.bash (1/1) PASS'
  assert_runner_output_contains "$output" '3 test(s), 1 failure(s)'
  [[ "$output" != *'fixture: selected'* && "$output" != *'expected fixture failure'* ]] || fail '--report none printed individual results'
}

test_runner_terminal_suppression_and_small_panel() {
  local first="$TEST_TMPDIR/first_test.bash" second="$TEST_TMPDIR/second_test.bash"
  local log="$TEST_TMPDIR/terminal.log" output
  command -v script >/dev/null 2>&1 || return 0
  make_runner_test_file "$first"
  make_runner_test_file "$second"
  RUNNER_MARKER="$TEST_TMPDIR/marker" run_runner_terminal "$log" 24 \
    --no-progress --report none "$first" >"$TEST_TMPDIR/script.log" 2>&1
  output="$(cat "$log")"
  assert_runner_output_contains "$output" '3 test(s), 0 failure(s)'
  [[ "$output" != *first_test.bash* && "$output" != *$'\033'* ]] || fail '--no-progress emitted terminal progress'
  RUNNER_MARKER="$TEST_TMPDIR/marker" run_runner_terminal "$log" 1 \
    --report none "$first" "$second" >"$TEST_TMPDIR/script.log" 2>&1
  output="$(cat "$log")"
  assert_runner_output_contains "$output" 'first_test.bash (0/3) QUEUED'
  assert_runner_output_contains "$output" 'first_test.bash (3/3) PASS'
  assert_runner_output_contains "$output" 'second_test.bash (3/3) PASS'
  [[ "$output" != *$'\033'* ]] || fail 'small terminal attempted cursor updates'
  RUNNER_MARKER="$TEST_TMPDIR/marker" run_runner_terminal "$log" 1 \
    --report none "$first" "$TEST_TMPDIR/./first_test.bash" >"$TEST_TMPDIR/script.log" 2>&1
  output="$(cat "$log")"
  assert_runner_output_contains "$output" 'first_test.bash (0/6) QUEUED'
  assert_runner_output_contains "$output" 'first_test.bash (6/6) PASS'
  assert_eq 1 "$(grep -c QUEUED "$log")" 'the same file must form one group'
}

test_runner_terminal_worker_crash_finishes_groups() {
  local test_file="$TEST_TMPDIR/crash_test.bash" log="$TEST_TMPDIR/terminal.log" output
  command -v script >/dev/null 2>&1 || return 0
  cat >"$test_file" <<'EOF'
[[ "${TESTS_LIST_ONLY:-0}" -eq 1 ]] || return 7
test_fixture_pass() { return 0; }
test_case 'fixture: unreachable case' test_fixture_pass
EOF
  run_runner_terminal "$log" 24 --report none "$test_file" >"$TEST_TMPDIR/script.log" 2>&1 || true
  output="$(cat "$log")"
  assert_runner_output_contains "$output" 'crash_test.bash (0/1) ERROR'
  assert_runner_output_contains "$output" 'test worker 0 did not report results'
}

test_runner_progress_resize_and_cancellation() {
  local output
  . "$TESTS_DIR/lib/progress.bash"
  TESTS_PROGRESS_ENABLED=1
  TESTS_PARALLEL_TMP="$TEST_TMPDIR"
  mkdir -p "$TEST_TMPDIR/other"
  test_files=( "$TEST_TMPDIR/same_test.bash" "$TEST_TMPDIR/other/same_test.bash" )
  printf '1\t0\n2\t1\n' >"$TEST_TMPDIR/manifest"
  progress_dimensions() { PROGRESS_HEIGHT=24; PROGRESS_WIDTH=100; }
  progress_initialize "$TEST_TMPDIR/manifest" >/dev/null
  assert_eq "$TEST_TMPDIR/same_test.bash" "${PROGRESS_LABELS[0]}"
  progress_dimensions() { PROGRESS_HEIGHT=1; PROGRESS_WIDTH=40; }
  PROGRESS_RESIZED=1
  output="$(progress_finish cancelled)"
  assert_runner_output_contains "$output" CANCELLED
  [[ "$output" != *PASS* && "$output" != *$'\033'* ]] || fail 'resize or cancellation left an unsafe display'
}

test_runner_terminal_interrupt_cancels_and_reaps() {
  local test_file="$TEST_TMPDIR/wait_test.bash" fixture="$TEST_TMPDIR/wait-fixture"
  local marker="$TEST_TMPDIR/pids" pid_file="$TEST_TMPDIR/runner-pid"
  local log="$TEST_TMPDIR/terminal.log" terminal_pid target attempt output cleanup pid kind
  command -v script >/dev/null 2>&1 || return 0
  cat >"$fixture" <<'EOF'
#!/usr/bin/env bash
sleep 30 &
sleeper=$!
printf 'pid\t%s\npid\t%s\nready\n' "$$" "$sleeper" >>"$RUNNER_MARKER"
wait "$sleeper"
EOF
  cat >"$test_file" <<'EOF'
test_fixture_wait() { bash "$RUNNER_FIXTURE"; }
test_case 'fixture: waiting case' test_fixture_wait
EOF
  RUNNER_TERMINAL_PID_FILE="$pid_file" RUNNER_FIXTURE="$fixture" RUNNER_MARKER="$marker" \
    run_runner_terminal "$log" 24 --report none "$test_file" >"$TEST_TMPDIR/script.log" 2>&1 &
  terminal_pid=$!
  printf -v cleanup 'kill %q 2>/dev/null || true; wait %q 2>/dev/null || true' "$terminal_pid" "$terminal_pid"
  trap "$cleanup" EXIT
  for ((attempt = 0; attempt < 200; attempt++)); do
    [[ ! -f "$marker" ]] || [[ "$(cat "$marker")" != *ready* ]] || break
    sleep 0.02
  done
  assert_runner_output_contains "$(cat "$marker" 2>/dev/null || true)" ready
  target="$(cat "$pid_file")"
  kill -TERM "$target"
  wait "$terminal_pid" || true
  trap - EXIT
  output="$(cat "$log")"
  assert_runner_output_contains "$output" 'wait_test.bash (0/1) CANCELLED'
  [[ "$output" != *'test(s),'* ]] || fail 'interrupted terminal run reported completion'
  while IFS=$'\t' read -r kind pid; do
    [[ "$kind" == pid ]] || continue
    for ((attempt = 0; attempt < 100; attempt++)); do
      runner_fixture_is_running "$pid" || break
      sleep 0.02
    done
    if runner_fixture_is_running "$pid"; then
      kill -TERM "$pid" 2>/dev/null || true
      fail "fixture survived terminal interruption: $pid"
    fi
  done <"$marker"
}

test_runner_isolates_worker_stdin() {
  local test_file="$TEST_TMPDIR/stdin_test.bash" output remaining jobs
  local log="$TEST_TMPDIR/terminal.log"

  cat >"$test_file" <<'EOF'
test_fixture_stdin() {
  [[ ! -t 0 ]] || fail 'test inherited the terminal stdin'
  if IFS= read -r input; then
    fail "test consumed caller input: $input"
  fi
}
test_case 'fixture: isolated stdin' test_fixture_stdin
EOF
  printf 'caller input\n' >"$TEST_TMPDIR/input"
  for jobs in 1 2; do
    {
      output="$("$RUNNER_UNDER_TEST" --jobs "$jobs" "$test_file" <&3)"
      IFS= read -r remaining <&3
    } 3<"$TEST_TMPDIR/input"
    assert_eq 'caller input' "$remaining" 'runner consumed caller stdin'
    assert_runner_output_contains "$output" '1 test(s), 0 failure(s)'
  done
  if command -v script >/dev/null 2>&1; then
    run_runner_terminal "$log" 24 "$test_file"
    assert_runner_output_contains "$(cat "$log")" '1 test(s), 0 failure(s)'
  fi
}

test_case 'test runner: isolates worker stdin' \
  test_runner_isolates_worker_stdin
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
test_case 'test runner: report modes preserve failure status' \
  test_runner_report_modes_preserve_failure_status
test_case 'test runner: validates report and keeps lists plain' \
  test_runner_validates_report_and_keeps_list_plain
test_case 'test runner: terminal groups publish before completion' \
  test_runner_terminal_groups_publish_before_completion
test_case 'test runner: terminal suppression and small panel' \
  test_runner_terminal_suppression_and_small_panel
test_case 'test runner: terminal worker crash finishes groups' \
  test_runner_terminal_worker_crash_finishes_groups
test_case 'test runner: progress resize and cancellation' \
  test_runner_progress_resize_and_cancellation
test_case 'test runner: terminal interrupt cancels and reaps' \
  test_runner_terminal_interrupt_cancels_and_reaps
