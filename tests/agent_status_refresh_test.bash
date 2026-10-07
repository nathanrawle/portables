#!/usr/bin/env bash

. "$TESTS_DIR/lib/taw_test_helpers.bash"

REFRESH_STATUS="$REPO_ROOT/home/.zfuns/taw-agent-status"

prepare_status_refresh() {
  REFRESH_BIN="$TEST_TMPDIR/bin"
  REFRESH_CONFIG="$TEST_TMPDIR/claude config"
  REFRESH_SESSION=b666ce8b-aadb-45ec-8e51-95e5bc28e985
  mkdir -p "$REFRESH_BIN" "$REFRESH_CONFIG/sessions"
  printf 'thinking\n' >"$TEST_TMPDIR/state"
  printf '{}\n' >"$TEST_TMPDIR/meta"
  : >"$TEST_TMPDIR/tmux.log"
  cat >"$REFRESH_BIN/tmux" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$REFRESH_DIR/tmux.log"
case "$1" in
  show-option)
    case "${5:-${3:-}}" in
      @taw_claude_status) cat "$REFRESH_DIR/meta" ;;
      @taw_agent_refresh_at) cat "$REFRESH_DIR/last" 2>/dev/null || true ;;
    esac
    ;;
  list-panes) printf '%%7\n%%7\n' ;;
  display-message)
    case "$5" in
      '#{pane_pid}') printf '%s\n' "${REFRESH_ROOT:-1111}" ;;
      *'#{@taw_agent_state}'*)
        printf '%s\t%s\t%s\t%s\n' "${REFRESH_AGENT:-claude}" \
          "${REFRESH_ROOT:-1111}" "${REFRESH_SAVED_ROOT:-1111}" "$(cat "$REFRESH_DIR/state")"
        ;;
      *)
        printf '%%7\t%s\t%s\t%s\t%s\n' "${REFRESH_WINDOW:-@4}" \
          "${REFRESH_ROOT:-1111}" "${REFRESH_AGENT:-claude}" "${REFRESH_SAVED_ROOT:-1111}"
        if [[ "${REFRESH_CHANGE_RECORD:-}" == 1 ]]; then
          printf '{}\n' >"$REFRESH_CONFIG/sessions/1234.json"
        fi
        ;;
    esac
    ;;
  set-option)
    if [[ "$2" == -g ]]; then
      printf '%s\n' "$4" >"$REFRESH_DIR/last"
    else
      case "$5" in
        @taw_claude_status) printf '%s\n' "${6:-}" >"$REFRESH_DIR/meta" ;;
        @taw_agent_state) printf '%s\n' "${6:-}" >"$REFRESH_DIR/state" ;;
      esac
    fi
    ;;
  if-shell)
    [[ "${REFRESH_CHANGED_SNAPSHOT:-}" != 1 ]] || exit 0
    IFS=';' read -ra commands <<<"$6"
    for command in "${commands[@]}"; do
      read -ra args <<<"$command"
      [[ "${#args[@]}" -gt 0 ]] || continue
      "$0" "${args[@]}"
    done
    ;;
  list-sessions) exit 1 ;;
  *) ;;
esac
MOCK
  cat >"$REFRESH_BIN/ps" <<'MOCK'
#!/usr/bin/env bash
case "$4" in
  lstart=)
    [[ "${REFRESH_DEAD:-}" != 1 ]] || exit 1
    printf '%s\n' "${REFRESH_STARTED:-Thu Oct  1 19:26:43 2026}"
    ;;
  ppid=) printf '1111\n' ;;
esac
MOCK
  cat >"$REFRESH_BIN/uname" <<'MOCK'
#!/usr/bin/env bash
printf 'Darwin\n'
MOCK
  chmod +x "$REFRESH_BIN/"*
  write_refresh_record idle 2000
}

write_refresh_record() {
  jq -n --arg state "$1" --argjson at "$2" --arg session "$REFRESH_SESSION" '{
    pid: 1234, kind: "interactive", pidDomain: "darwin", sessionId: $session,
    tmux: "project:@4.%7", procStart: "Thu Oct  1 19:26:43 2026",
    status: $state, statusUpdatedAt: $at
  }' >"$REFRESH_CONFIG/sessions/1234.json"
}

write_refresh_meta() {
  jq -n --arg config "$REFRESH_CONFIG" --arg session "$REFRESH_SESSION" \
    --argjson at "${1:-1000}" '{
      root: "1111", config_dir: $config, session_id: $session, event_at: $at,
      route: "1234\tproject:@4.%7\tThu Oct  1 19:26:43 2026"
    }' >"$TEST_TMPDIR/meta"
}

run_status_refresh() {
  local output

  output="$(TMUX=/tmp/isolated TMUX_PANE=%7 PATH="$REFRESH_BIN:$PATH" \
    CLAUDE_CONFIG_DIR="$REFRESH_CONFIG" REFRESH_CONFIG="$REFRESH_CONFIG" \
    REFRESH_DIR="$TEST_TMPDIR" "$REFRESH_STATUS" refresh 2>&1)" || fail "$output"
  assert_eq '' "$output" 'expected quiet status recovery'
}

reset_status_refresh() {
  rm -f "$TEST_TMPDIR/last"
  : >"$TEST_TMPDIR/tmux.log"
}

test_refresh_recovers_idle_and_deduplicates() {
  prepare_status_refresh
  write_refresh_meta
  run_status_refresh
  assert_eq idle "$(cat "$TEST_TMPDIR/state")" 'expected interrupted turn to recover'
  assert_eq 1 "$(rg -c '^set-option.*@taw_agent_state idle$' "$TEST_TMPDIR/tmux.log")" \
    'expected linked panes to be recovered once'
  : >"$TEST_TMPDIR/tmux.log"
  run_status_refresh
  assert_file_not_contains "$TEST_TMPDIR/tmux.log" list-panes
}

test_refresh_preserves_active_and_prompt_states() {
  local state

  prepare_status_refresh
  write_refresh_meta
  for state in waiting acknowledged idle; do
    printf '%s\n' "$state" >"$TEST_TMPDIR/state"
    reset_status_refresh
    run_status_refresh
    assert_eq "$state" "$(cat "$TEST_TMPDIR/state")" 'expected prompt state preserved'
  done
  for state in busy unknown; do
    printf 'thinking\n' >"$TEST_TMPDIR/state"
    write_refresh_record "$state" 2000
    reset_status_refresh
    run_status_refresh
    assert_eq thinking "$(cat "$TEST_TMPDIR/state")" 'expected active state preserved'
  done
  write_refresh_record idle 1000
  reset_status_refresh
  run_status_refresh
  assert_eq thinking "$(cat "$TEST_TMPDIR/state")" 'expected older idle record ignored'
}

test_refresh_tracks_owner_and_recovers_exit() {
  prepare_status_refresh
  run_status_refresh
  assert_eq idle "$(cat "$TEST_TMPDIR/state")" 'expected legacy pane recovery'
  assert_eq 1234 "$(jq -r '.route | split("\t")[0]' "$TEST_TMPDIR/meta")" \
    'expected validated descendant identity to be remembered'
  reset_status_refresh
  REFRESH_DEAD=1 run_status_refresh
  assert_eq '' "$(cat "$TEST_TMPDIR/state")" 'expected exited child metadata cleared'
  assert_file_contains "$TEST_TMPDIR/tmux.log" 'set-option -pu -t %7 @taw_agent'

  write_refresh_meta
  printf 'thinking\n' >"$TEST_TMPDIR/state"
  reset_status_refresh
  REFRESH_STARTED=reused run_status_refresh
  assert_eq '' "$(cat "$TEST_TMPDIR/state")" 'expected reused PID metadata cleared'
}

test_refresh_rejects_invalid_and_changed_records() {
  prepare_status_refresh
  write_refresh_meta
  REFRESH_WINDOW=@9 run_status_refresh
  assert_eq thinking "$(cat "$TEST_TMPDIR/state")" 'expected moved pane skipped'
  reset_status_refresh
  REFRESH_SAVED_ROOT=999 run_status_refresh
  assert_eq thinking "$(cat "$TEST_TMPDIR/state")" 'expected replacement pane skipped'
  reset_status_refresh
  REFRESH_AGENT=codex run_status_refresh
  assert_eq thinking "$(cat "$TEST_TMPDIR/state")" 'expected Codex untouched'
  reset_status_refresh
  REFRESH_CHANGED_SNAPSHOT=1 run_status_refresh
  assert_eq thinking "$(cat "$TEST_TMPDIR/state")" 'expected newer pane snapshot preserved'
  reset_status_refresh
  REFRESH_CHANGE_RECORD=1 run_status_refresh
  assert_eq thinking "$(cat "$TEST_TMPDIR/state")" 'expected changed record skipped'
  reset_status_refresh
  run_status_refresh
  assert_eq thinking "$(cat "$TEST_TMPDIR/state")" 'expected malformed record skipped'
  rm "$REFRESH_CONFIG/sessions/1234.json"
  reset_status_refresh
  run_status_refresh
  assert_eq thinking "$(cat "$TEST_TMPDIR/state")" 'expected missing record skipped'
}

test_refresh_rejects_ambiguous_and_replacement_sessions() {
  prepare_status_refresh
  jq '.pid = 2345' "$REFRESH_CONFIG/sessions/1234.json" >"$REFRESH_CONFIG/sessions/2345.json"
  run_status_refresh
  assert_eq thinking "$(cat "$TEST_TMPDIR/state")" 'expected ambiguous owners skipped'
  rm "$REFRESH_CONFIG/sessions/2345.json"
  write_refresh_meta
  REFRESH_SESSION=cccccccc-aadb-45ec-8e51-95e5bc28e985
  write_refresh_record idle 2000
  reset_status_refresh
  run_status_refresh
  assert_eq thinking "$(cat "$TEST_TMPDIR/state")" 'expected another session skipped'
}

test_case 'agent refresh: recovers interrupted turns and deduplicates linked panes' \
  test_refresh_recovers_idle_and_deduplicates
test_case 'agent refresh: preserves active turns, prompts, and newer hooks' \
  test_refresh_preserves_active_and_prompt_states
test_case 'agent refresh: tracks descendant owners and recovers abrupt exits' \
  test_refresh_tracks_owner_and_recovers_exit
test_case 'agent refresh: rejects invalid and changing records' \
  test_refresh_rejects_invalid_and_changed_records
test_case 'agent refresh: rejects ambiguous owners and replacement sessions' \
  test_refresh_rejects_ambiguous_and_replacement_sessions
