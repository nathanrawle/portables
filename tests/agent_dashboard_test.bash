#!/usr/bin/env bash

DASHBOARD_SCRIPT="$REPO_ROOT/home/.zfuns/taw-agent-dashboard"
DASHBOARD_STATUS="$REPO_ROOT/home/.zfuns/taw-agent-status"

make_dashboard_tmux_wrapper() {
  local root="$1" bin="$1/bin"

  mkdir -p "$bin"
  cat >"$bin/tmux" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

{
  first=1
  for arg in "$@"; do
    if [[ $first -eq 1 ]]; then
      printf '%s' "$arg"
      first=0
    else
      printf '\t%s' "$arg"
    fi
  done
  printf '\n'
} >>"$TAW_DASHBOARD_TMUX_LOG"
if [[ "${TAW_DASHBOARD_FAIL_LINK_WINDOW:-0}" = 1 && "$1" = link-window \
  && ! -e "$TAW_DASHBOARD_LINK_FAILURE_MARKER" ]]; then
  : >"$TAW_DASHBOARD_LINK_FAILURE_MARKER"
  exit 1
fi
if [[ "${TAW_DASHBOARD_FAIL_DISPLAY_MESSAGE:-0}" = 1 \
  && "$1" = display-message ]]; then
  display_count=0
  [[ -f "$TAW_DASHBOARD_DISPLAY_FAILURE_MARKER" ]] \
    && display_count="$(<"$TAW_DASHBOARD_DISPLAY_FAILURE_MARKER")"
  display_count=$((display_count + 1))
  printf '%s\n' "$display_count" >"$TAW_DASHBOARD_DISPLAY_FAILURE_MARKER"
  ((display_count == ${TAW_DASHBOARD_FAIL_DISPLAY_AT:-2})) && exit 1
fi
if [[ "${TAW_DASHBOARD_FAIL_LIST_WINDOWS:-0}" = 1 \
  && "$1" = list-windows && ! -e "$TAW_DASHBOARD_LIST_FAILURE_MARKER" ]]; then
  : >"$TAW_DASHBOARD_LIST_FAILURE_MARKER"
  exit 1
fi
if [[ "${TAW_DASHBOARD_FAIL_KILL_SESSION:-0}" = 1 \
  && "$1" = kill-session ]]; then
  exit 1
fi
exec "$TAW_DASHBOARD_REAL_TMUX" -L "$TAW_DASHBOARD_SOCKET" -f /dev/null "$@"
EOF
  chmod +x "$bin/tmux"
  printf '%s\n' "$bin"
}

make_dashboard_osascript() {
  local root="$1" bin

  bin="$root/bin"

  mkdir -p "$bin"
  cat >"$bin/osascript" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

script="$(cat)"
mode="${2:-}"
{
  printf 'mode=%s\n' "$mode"
  [[ "$mode" = close-terminal ]] && printf 'target=%s\n' "${3:-}"
  printf '%s\n' "$script"
} >>"$TAW_DASHBOARD_OSASCRIPT_LOG"

case "$mode" in
  health)
    [[ "${TAW_FAKE_GHOSTTY_HEALTH_ERROR:-0}" = 1 ]] && exit 1
    printf '%s\n' "${TAW_FAKE_GHOSTTY_HEALTH:-1}"
    ;;
  terminals-health)
    printf '%s\n' "$([[ "${TAW_FAKE_GHOSTTY_MISSING_TERMINAL:-0}" = 1 ]] \
      && printf 0 || printf 1)"
    ;;
  build)
    [[ "${TAW_FAKE_GHOSTTY_BUILD_ERROR:-0}" = 1 ]] && exit 1
    printf '%s' "${TAW_FAKE_GHOSTTY_BUILD:?}"
    ;;
  close-terminal)
    [[ "${TAW_FAKE_GHOSTTY_CLOSE_TERMINAL_ERROR:-0}" = 1 ]] && exit 1
    printf '1\n'
    ;;
  close|focus)
    if [[ "$mode" = close && "${TAW_FAKE_GHOSTTY_CLOSE_ERROR_ONCE:-0}" = 1 \
      && ! -e "$TAW_FAKE_GHOSTTY_CLOSE_ERROR_MARKER" ]]; then
      : >"$TAW_FAKE_GHOSTTY_CLOSE_ERROR_MARKER"
      exit 1
    fi
    printf 'target=%s\n' "${3:-}"
    printf '1\n'
    ;;
  *)
    exit 2
    ;;
esac
EOF
  chmod +x "$bin/osascript"
  printf '%s\n' "$bin"
}

cleanup_dashboard_server() {
  if [[ -n "${DASHBOARD_REAL_TMUX:-}" && -n "${DASHBOARD_SOCKET:-}" ]]; then
    "$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" kill-server >/dev/null 2>&1 || true
  fi
}

run_dashboard() {
  local bin="$1"
  shift

  TMUX=/tmp PATH="$bin:$PATH" \
    TAW_DASHBOARD_REAL_TMUX="$DASHBOARD_REAL_TMUX" \
    TAW_DASHBOARD_SOCKET="$DASHBOARD_SOCKET" \
    TAW_DASHBOARD_TMUX_LOG="$TEST_TMPDIR/tmux.log" \
    TAW_DASHBOARD_OSASCRIPT_LOG="$TEST_TMPDIR/osascript.log" \
    TAW_AGENT_DASHBOARD_STATE_FILE="${TAW_AGENT_DASHBOARD_STATE_FILE:-$TEST_TMPDIR/dashboard.state}" \
    TAW_AGENT_DASHBOARD_OSASCRIPT="$bin/osascript" \
    TAW_DASHBOARD_FAIL_LINK_WINDOW="${TAW_DASHBOARD_FAIL_LINK_WINDOW:-0}" \
    TAW_DASHBOARD_LINK_FAILURE_MARKER="$TEST_TMPDIR/link-window-failure" \
    TAW_DASHBOARD_FAIL_DISPLAY_MESSAGE="${TAW_DASHBOARD_FAIL_DISPLAY_MESSAGE:-0}" \
    TAW_DASHBOARD_DISPLAY_FAILURE_MARKER="$TEST_TMPDIR/display-message-failure" \
    TAW_DASHBOARD_FAIL_LIST_WINDOWS="${TAW_DASHBOARD_FAIL_LIST_WINDOWS:-0}" \
    TAW_DASHBOARD_LIST_FAILURE_MARKER="$TEST_TMPDIR/list-windows-failure" \
    TAW_DASHBOARD_FAIL_KILL_SESSION="${TAW_DASHBOARD_FAIL_KILL_SESSION:-0}" \
    TAW_FAKE_GHOSTTY_BUILD_ERROR="${TAW_FAKE_GHOSTTY_BUILD_ERROR:-0}" \
    TAW_FAKE_GHOSTTY_BUILD="${TAW_FAKE_GHOSTTY_BUILD:-}" \
    TAW_FAKE_GHOSTTY_HEALTH="${TAW_FAKE_GHOSTTY_HEALTH:-1}" \
    TAW_FAKE_GHOSTTY_HEALTH_ERROR="${TAW_FAKE_GHOSTTY_HEALTH_ERROR:-0}" \
    TAW_FAKE_GHOSTTY_MISSING_TERMINAL="${TAW_FAKE_GHOSTTY_MISSING_TERMINAL:-0}" \
    TAW_FAKE_GHOSTTY_CLOSE_TERMINAL_ERROR="${TAW_FAKE_GHOSTTY_CLOSE_TERMINAL_ERROR:-0}" \
    TAW_FAKE_GHOSTTY_CLOSE_ERROR_ONCE="${TAW_FAKE_GHOSTTY_CLOSE_ERROR_ONCE:-0}" \
    TAW_FAKE_GHOSTTY_CLOSE_ERROR_MARKER="$TEST_TMPDIR/ghostty-close-failure" \
    TAW_DASHBOARD_FAIL_DISPLAY_AT="${TAW_DASHBOARD_FAIL_DISPLAY_AT:-2}" \
    "$DASHBOARD_SCRIPT" "$@"
}

run_dashboard_status() {
  local bin="$1" home="$2" pane="$3" agent="$4"

  TMUX=/tmp TMUX_PANE="$pane" HOME="$home" PATH="$bin:$PATH" \
    TAW_DASHBOARD_REAL_TMUX="$DASHBOARD_REAL_TMUX" \
    TAW_DASHBOARD_SOCKET="$DASHBOARD_SOCKET" \
    TAW_DASHBOARD_TMUX_LOG="$TEST_TMPDIR/tmux.log" \
    TAW_DASHBOARD_OSASCRIPT_LOG="$TEST_TMPDIR/osascript.log" \
    TAW_AGENT_DASHBOARD_STATE_FILE="$TEST_TMPDIR/dashboard.state" \
    TAW_AGENT_DASHBOARD_OSASCRIPT="$bin/osascript" \
    TAW_AGENT_LINK_REAL_TMUX="$DASHBOARD_REAL_TMUX" \
    TAW_AGENT_LINK_SOCKET="$DASHBOARD_SOCKET" \
    "$DASHBOARD_STATUS" start "$agent" "$pane"
}

run_dashboard_status_unlink() {
  local bin="$1" home="$2" window="$3"

  TMUX=/tmp HOME="$home" PATH="$bin:$PATH" \
    TAW_DASHBOARD_REAL_TMUX="$DASHBOARD_REAL_TMUX" \
    TAW_DASHBOARD_SOCKET="$DASHBOARD_SOCKET" \
    TAW_DASHBOARD_TMUX_LOG="$TEST_TMPDIR/tmux.log" \
    TAW_DASHBOARD_OSASCRIPT_LOG="$TEST_TMPDIR/osascript.log" \
    TAW_AGENT_DASHBOARD_STATE_FILE="$TEST_TMPDIR/dashboard.state" \
    TAW_AGENT_DASHBOARD_OSASCRIPT="$bin/osascript" \
    TAW_AGENT_LINK_REAL_TMUX="$DASHBOARD_REAL_TMUX" \
    TAW_AGENT_LINK_SOCKET="$DASHBOARD_SOCKET" \
    "$DASHBOARD_STATUS" unlink "$window"
}

assert_dashboard_file_contains() {
  local path="$1" expected="$2"

  grep -Fq -- "$expected" "$path" \
    || fail "expected $path to contain: $expected"
}

test_dashboard_uses_private_views_and_does_not_reopen() {
  local project home wrapper source_window pane session linked
  local -a source_windows view_sessions
  local kind terminal source

  DASHBOARD_REAL_TMUX="$(command -v tmux || true)"
  [[ -n "$DASHBOARD_REAL_TMUX" ]] || return 0
  DASHBOARD_SOCKET="portables-agent-dashboard-$$-$RANDOM"
  trap cleanup_dashboard_server EXIT
  project="$TEST_TMPDIR/project"
  home="$TEST_TMPDIR/home"
  mkdir -p "$project" "$home/.zfuns"
  ln -s "$DASHBOARD_SCRIPT" "$home/.zfuns/taw-agent-dashboard"
  wrapper="$(make_dashboard_tmux_wrapper "$TEST_TMPDIR/tmux-wrapper")"
  make_dashboard_osascript "$TEST_TMPDIR/tmux-wrapper" >/dev/null
  : >"$TEST_TMPDIR/tmux.log"
  : >"$TEST_TMPDIR/osascript.log"

  "$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" -f /dev/null \
    new-session -d -s source -n first -c "$project" 'sleep 300'
  for session in second third; do
    "$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" -f /dev/null \
      new-window -d -t source: -n "$session" -c "$project" 'sleep 300'
  done

  for session in first second third; do
    pane="$("$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" display-message \
      -p -t "source:$session" '#{pane_id}')"
    run_dashboard_status "$wrapper" "$home" "$pane" codex
  done

  source_window="$("$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" list-windows \
    -t agents -F '#{window_id}' | head -n 1)"
  TAW_FAKE_GHOSTTY_BUILD=$'dashboard-window-1\nterminal-1\nterminal-2\nterminal-3' \
    run_dashboard "$wrapper" open

  [[ -s "$TEST_TMPDIR/dashboard.state" ]] || fail "expected dashboard state"
  assert_dashboard_file_contains "$TEST_TMPDIR/osascript.log" 'direction right'
  assert_dashboard_file_contains "$TEST_TMPDIR/osascript.log" 'direction down'
  assert_dashboard_file_contains "$TEST_TMPDIR/osascript.log" 'equalize_splits'

  source_windows=()
  while IFS= read -r source; do
    source_windows+=( "$source" )
  done < <("$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" list-windows \
    -t agents -F '#{window_id}')
  assert_eq 3 "${#source_windows[@]}" "expected three managed source windows"

  view_sessions=()
  while IFS=$'\t' read -r kind terminal session source; do
    [[ "$kind" = terminal ]] || continue
    view_sessions+=( "$session" )
    linked="$("$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" list-windows \
      -t "=$session" -F '#{window_id}')"
    assert_eq "$source" "$linked" "expected one source window in each private view"
    assert_eq 1 "$("$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" show-option \
      -qv -t "$session" @taw_agent_dashboard_session)" \
      "expected private view ownership marker"
  done <"$TEST_TMPDIR/dashboard.state"
  assert_eq 3 "${#view_sessions[@]}" "expected three private view sessions"
  "$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" has-session -t source

  TAW_FAKE_GHOSTTY_HEALTH=0 run_dashboard "$wrapper" sync
  assert_not_exists "$TEST_TMPDIR/dashboard.state"
  for session in "${view_sessions[@]}"; do
    if "$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" has-session -t "=$session"; then
      fail "expected stale private view session to be removed: $session"
    fi
  done
  "$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" has-session -t source

  if grep -Fq 'mode=build' "$TEST_TMPDIR/osascript.log"; then
    :
  else
    fail "expected Ghostty build request"
  fi
  TAW_FAKE_GHOSTTY_HEALTH=0 run_dashboard "$wrapper" sync
  assert_eq 1 "$(grep -Fc 'mode=build' "$TEST_TMPDIR/osascript.log")" \
    "expected sync without state not to reopen Ghostty"
}

test_dashboard_closes_private_views_but_keeps_source_alive() {
  local project home wrapper first_window pane session

  DASHBOARD_REAL_TMUX="$(command -v tmux || true)"
  [[ -n "$DASHBOARD_REAL_TMUX" ]] || return 0
  DASHBOARD_SOCKET="portables-agent-dashboard-close-$$-$RANDOM"
  trap cleanup_dashboard_server EXIT
  project="$TEST_TMPDIR/project"
  home="$TEST_TMPDIR/home"
  mkdir -p "$project" "$home/.zfuns"
  ln -s "$DASHBOARD_SCRIPT" "$home/.zfuns/taw-agent-dashboard"
  wrapper="$(make_dashboard_tmux_wrapper "$TEST_TMPDIR/tmux-wrapper")"
  make_dashboard_osascript "$TEST_TMPDIR/tmux-wrapper" >/dev/null
  : >"$TEST_TMPDIR/tmux.log"
  : >"$TEST_TMPDIR/osascript.log"

  "$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" -f /dev/null \
    new-session -d -s source -n work -c "$project" 'sleep 300'
  pane="$("$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" display-message \
    -p -t source:work '#{pane_id}')"
  run_dashboard_status "$wrapper" "$home" "$pane" claude
  first_window="$("$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" list-windows \
    -t agents -F '#{window_id}')"
  TAW_FAKE_GHOSTTY_BUILD=$'dashboard-window-2\nterminal-4' \
    run_dashboard "$wrapper" open
  session="$(awk -F '\t' '$1 == "terminal" { print $3 }' "$TEST_TMPDIR/dashboard.state")"
  run_dashboard "$wrapper" close

  assert_not_exists "$TEST_TMPDIR/dashboard.state"
  if "$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" has-session -t "=$session"; then
    fail "expected close to remove the private view session"
  fi
  "$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" has-session -t source
  assert_eq "$first_window" "$($DASHBOARD_REAL_TMUX -L "$DASHBOARD_SOCKET" \
    list-windows -t agents -F '#{window_id}')" \
    "expected close to preserve the managed source link"
}

test_dashboard_unlink_resolves_session_id() {
  local project home wrapper source_window pane session session_id terminal

  DASHBOARD_REAL_TMUX="$(command -v tmux || true)"
  [[ -n "$DASHBOARD_REAL_TMUX" ]] || return 0
  DASHBOARD_SOCKET="portables-agent-dashboard-unlink-$$-$RANDOM"
  trap cleanup_dashboard_server EXIT
  project="$TEST_TMPDIR/project"
  home="$TEST_TMPDIR/home"
  mkdir -p "$project" "$home/.zfuns"
  ln -s "$DASHBOARD_SCRIPT" "$home/.zfuns/taw-agent-dashboard"
  wrapper="$(make_dashboard_tmux_wrapper "$TEST_TMPDIR/tmux-wrapper")"
  make_dashboard_osascript "$TEST_TMPDIR/tmux-wrapper" >/dev/null
  : >"$TEST_TMPDIR/tmux.log"
  : >"$TEST_TMPDIR/osascript.log"

  "$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" -f /dev/null \
    new-session -d -s source -n work -c "$project" 'sleep 300'
  pane="$("$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" display-message \
    -p -t source:work '#{pane_id}')"
  run_dashboard_status "$wrapper" "$home" "$pane" codex
  source_window="$("$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" list-windows \
    -t agents -F '#{window_id}')"
  TAW_FAKE_GHOSTTY_BUILD=$'dashboard-window-3\nterminal-5' \
    run_dashboard "$wrapper" open
  session="$(awk -F '\t' '$1 == "terminal" { print $3 }' \
    "$TEST_TMPDIR/dashboard.state")"
  terminal="$(awk -F '\t' '$1 == "terminal" { print $2 }' \
    "$TEST_TMPDIR/dashboard.state")"
  session_id="$("$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" list-sessions \
    -F $'#{session_id}\t#{session_name}' \
    | awk -F '\t' -v name="$session" '$2 == name { print $1 }')"
  [[ -n "$session_id" ]] || fail "expected a tmux session ID for $session"

  run_dashboard "$wrapper" unlink "$session_id" "$source_window"

  assert_not_exists "$TEST_TMPDIR/dashboard.state"
  if "$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" has-session \
    -t "=$session" 2>/dev/null; then
    fail "expected unlink to remove the private view session"
  fi
  "$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" has-session -t source
  assert_dashboard_file_contains "$TEST_TMPDIR/osascript.log" \
    "mode=close-terminal"
  assert_dashboard_file_contains "$TEST_TMPDIR/osascript.log" "target=$terminal"
}

test_dashboard_preserves_explicitly_closed_views() {
  local project home wrapper pane session session_id source_window build_count

  DASHBOARD_REAL_TMUX="$(command -v tmux || true)"
  [[ -n "$DASHBOARD_REAL_TMUX" ]] || return 0
  DASHBOARD_SOCKET="portables-agent-dashboard-closed-view-$$-$RANDOM"
  trap cleanup_dashboard_server EXIT
  project="$TEST_TMPDIR/project"
  home="$TEST_TMPDIR/home"
  mkdir -p "$project" "$home/.zfuns"
  ln -s "$DASHBOARD_SCRIPT" "$home/.zfuns/taw-agent-dashboard"
  wrapper="$(make_dashboard_tmux_wrapper "$TEST_TMPDIR/tmux-wrapper")"
  make_dashboard_osascript "$TEST_TMPDIR/tmux-wrapper" >/dev/null
  : >"$TEST_TMPDIR/tmux.log"
  : >"$TEST_TMPDIR/osascript.log"

  "$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" -f /dev/null \
    new-session -d -s source -n first -c "$project" 'sleep 300'
  "$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" -f /dev/null \
    new-window -d -t source: -n second -c "$project" 'sleep 300'
  while IFS= read -r pane; do
    run_dashboard_status "$wrapper" "$home" "$pane" codex
  done < <("$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" list-panes -a \
    -t source -F '#{pane_id}')

  TAW_FAKE_GHOSTTY_BUILD=$'dashboard-window-5\nterminal-7\nterminal-8' \
    run_dashboard "$wrapper" open
  session="$(awk -F '\t' '$1 == "terminal" { print $3; exit }' \
    "$TEST_TMPDIR/dashboard.state")"
  source_window="$(awk -F '\t' '$1 == "terminal" { print $4; exit }' \
    "$TEST_TMPDIR/dashboard.state")"
  session_id="$("$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" list-sessions \
    -F $'#{session_id}\t#{session_name}' \
    | awk -F '\t' -v name="$session" '$2 == name { print $1 }')"
  [[ -n "$session_id" ]] || fail "expected a tmux session ID for $session"

  run_dashboard "$wrapper" unlink "$session_id" "$source_window"
  assert_dashboard_file_contains "$TEST_TMPDIR/dashboard.state" \
    $'exclude\t'"$source_window"
  build_count="$(grep -Fc 'mode=build' "$TEST_TMPDIR/osascript.log")"
  run_dashboard "$wrapper" sync
  assert_eq "$build_count" "$(grep -Fc 'mode=build' "$TEST_TMPDIR/osascript.log")" \
    "expected sync not to reopen an explicitly closed view"
  if "$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" has-session \
    -t "=$session" 2>/dev/null; then
    fail "expected the explicitly closed view session to stay closed"
  fi
  assert_eq 2 "$($DASHBOARD_REAL_TMUX -L "$DASHBOARD_SOCKET" \
    list-windows -t agents -F '#{window_id}' | wc -l | tr -d ' ')" \
    "expected source windows to remain managed"

  "$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" unlink-window \
    -t "agents:$source_window"
  run_dashboard "$wrapper" sync
  if grep -Fq $'exclude\t' "$TEST_TMPDIR/dashboard.state"; then
    fail "expected expired exclusion to be removed from dashboard state"
  fi
  assert_eq "$build_count" "$(grep -Fc 'mode=build' "$TEST_TMPDIR/osascript.log")" \
    "expected pruning an expired exclusion not to rebuild the dashboard"

  "$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" link-window -d \
    -s "source:$source_window" -t agents:
  TAW_FAKE_GHOSTTY_BUILD=$'dashboard-window-6\nterminal-9\nterminal-10' \
    run_dashboard "$wrapper" sync
  assert_eq $((build_count + 1)) \
    "$(grep -Fc 'mode=build' "$TEST_TMPDIR/osascript.log")" \
    "expected a managed source window to return after its exclusion expired"
  if ! awk -F '\t' -v source="$source_window" \
    '$1 == "terminal" && $4 == source { found = 1 } END { exit !found }' \
    "$TEST_TMPDIR/dashboard.state"; then
    fail "expected the re-managed source window to return to dashboard state"
  fi
}

test_dashboard_cleans_failed_new_view_session() {
  local project home wrapper pane session_count

  DASHBOARD_REAL_TMUX="$(command -v tmux || true)"
  [[ -n "$DASHBOARD_REAL_TMUX" ]] || return 0
  DASHBOARD_SOCKET="portables-agent-dashboard-failed-view-$$-$RANDOM"
  trap cleanup_dashboard_server EXIT
  project="$TEST_TMPDIR/project"
  home="$TEST_TMPDIR/home"
  mkdir -p "$project" "$home/.zfuns"
  ln -s "$DASHBOARD_SCRIPT" "$home/.zfuns/taw-agent-dashboard"
  wrapper="$(make_dashboard_tmux_wrapper "$TEST_TMPDIR/tmux-wrapper")"
  make_dashboard_osascript "$TEST_TMPDIR/tmux-wrapper" >/dev/null
  : >"$TEST_TMPDIR/tmux.log"
  : >"$TEST_TMPDIR/osascript.log"

  "$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" -f /dev/null \
    new-session -d -s source -n work -c "$project" 'sleep 300'
  pane="$("$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" display-message \
    -p -t source:work '#{pane_id}')"
  run_dashboard_status "$wrapper" "$home" "$pane" codex

  if TAW_DASHBOARD_FAIL_LINK_WINDOW=1 run_dashboard "$wrapper" open; then
    fail "expected dashboard creation to fail when linking the view window fails"
  fi
  assert_not_exists "$TEST_TMPDIR/dashboard.state"
  session_count="$("$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" list-sessions \
    -F '#{@taw_agent_dashboard_session}' | awk '$1 == 1 { print }')"
  [[ -z "$session_count" ]] || fail "expected failed view session to be removed"
  "$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" has-session -t source
}

test_dashboard_cleans_state_persistence_failure() {
  local project home wrapper pane session_count

  DASHBOARD_REAL_TMUX="$(command -v tmux || true)"
  [[ -n "$DASHBOARD_REAL_TMUX" ]] || return 0
  DASHBOARD_SOCKET="portables-agent-dashboard-state-failure-$$-$RANDOM"
  trap cleanup_dashboard_server EXIT
  project="$TEST_TMPDIR/project"
  home="$TEST_TMPDIR/home"
  mkdir -p "$project" "$home/.zfuns"
  ln -s "$DASHBOARD_SCRIPT" "$home/.zfuns/taw-agent-dashboard"
  wrapper="$(make_dashboard_tmux_wrapper "$TEST_TMPDIR/tmux-wrapper")"
  make_dashboard_osascript "$TEST_TMPDIR/tmux-wrapper" >/dev/null
  : >"$TEST_TMPDIR/tmux.log"
  : >"$TEST_TMPDIR/osascript.log"

  "$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" -f /dev/null \
    new-session -d -s source -n work -c "$project" 'sleep 300'
  pane="$("$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" display-message \
    -p -t source:work '#{pane_id}')"
  run_dashboard_status "$wrapper" "$home" "$pane" codex

  if TAW_AGENT_DASHBOARD_STATE_FILE=/dev/null/taw-agent-dashboard.state \
    TAW_FAKE_GHOSTTY_BUILD=$'dashboard-window-9\nterminal-11' \
    run_dashboard "$wrapper" open; then
    fail "expected dashboard creation to fail when state persistence fails"
  fi
  assert_dashboard_file_contains "$TEST_TMPDIR/osascript.log" 'mode=close'
  session_count="$("$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" list-sessions \
    -F '#{@taw_agent_dashboard_session}' | awk '$1 == 1 { print }')"
  [[ -z "$session_count" ]] || fail "expected state failure to remove private view sessions"
  "$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" has-session -t source
}

test_dashboard_build_errors_close_partial_window() {
  local project home wrapper pane

  DASHBOARD_REAL_TMUX="$(command -v tmux || true)"
  [[ -n "$DASHBOARD_REAL_TMUX" ]] || return 0
  DASHBOARD_SOCKET="portables-agent-dashboard-build-failure-$$-$RANDOM"
  trap cleanup_dashboard_server EXIT
  project="$TEST_TMPDIR/project"
  home="$TEST_TMPDIR/home"
  mkdir -p "$project" "$home/.zfuns"
  ln -s "$DASHBOARD_SCRIPT" "$home/.zfuns/taw-agent-dashboard"
  wrapper="$(make_dashboard_tmux_wrapper "$TEST_TMPDIR/tmux-wrapper")"
  make_dashboard_osascript "$TEST_TMPDIR/tmux-wrapper" >/dev/null
  : >"$TEST_TMPDIR/tmux.log"
  : >"$TEST_TMPDIR/osascript.log"

  "$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" -f /dev/null \
    new-session -d -s source -n work -c "$project" 'sleep 300'
  pane="$("$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" display-message \
    -p -t source:work '#{pane_id}')"
  run_dashboard_status "$wrapper" "$home" "$pane" codex

  if TAW_FAKE_GHOSTTY_BUILD_ERROR=1 run_dashboard "$wrapper" open; then
    fail "expected dashboard creation to fail when the build script fails"
  fi
  assert_dashboard_file_contains "$TEST_TMPDIR/osascript.log" \
    'on error errorMessage number errorNumber'
  assert_dashboard_file_contains "$TEST_TMPDIR/osascript.log" 'close window win'
  assert_not_exists "$TEST_TMPDIR/dashboard.state"
  "$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" has-session -t source
}

test_dashboard_preserves_state_on_unlink_persistence_failure() {
  local project home wrapper pane first_session first_source session_id
  local state_dir state_file

  DASHBOARD_REAL_TMUX="$(command -v tmux || true)"
  [[ -n "$DASHBOARD_REAL_TMUX" ]] || return 0
  DASHBOARD_SOCKET="portables-agent-dashboard-unlink-state-failure-$$-$RANDOM"
  trap cleanup_dashboard_server EXIT
  project="$TEST_TMPDIR/project"
  home="$TEST_TMPDIR/home"
  state_dir="$TEST_TMPDIR/state"
  state_file="$state_dir/dashboard.state"
  mkdir -p "$project" "$home/.zfuns" "$state_dir"
  ln -s "$DASHBOARD_SCRIPT" "$home/.zfuns/taw-agent-dashboard"
  wrapper="$(make_dashboard_tmux_wrapper "$TEST_TMPDIR/tmux-wrapper")"
  make_dashboard_osascript "$TEST_TMPDIR/tmux-wrapper" >/dev/null
  : >"$TEST_TMPDIR/tmux.log"
  : >"$TEST_TMPDIR/osascript.log"

  "$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" -f /dev/null \
    new-session -d -s source -n first -c "$project" 'sleep 300'
  "$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" -f /dev/null \
    new-window -d -t source: -n second -c "$project" 'sleep 300'
  while IFS= read -r pane; do
    run_dashboard_status "$wrapper" "$home" "$pane" codex
  done < <("$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" list-panes -a \
    -t source -F '#{pane_id}')

  TAW_AGENT_DASHBOARD_STATE_FILE="$state_file" \
    TAW_FAKE_GHOSTTY_BUILD=$'dashboard-window-10\nterminal-12\nterminal-13' \
    run_dashboard "$wrapper" open
  first_session="$(awk -F '\t' '$1 == "terminal" { print $3; exit }' \
    "$state_file")"
  first_source="$(awk -F '\t' '$1 == "terminal" { print $4; exit }' \
    "$state_file")"
  session_id="$("$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" list-sessions \
    -F $'#{session_id}\t#{session_name}' \
    | awk -F '\t' -v name="$first_session" '$2 == name { print $1 }')"
  [[ -n "$session_id" ]] || fail "expected a tmux session ID for $first_session"

  chmod u-w "$state_dir"
  if TAW_AGENT_DASHBOARD_STATE_FILE="$state_file" \
    run_dashboard "$wrapper" unlink "$session_id" "$first_source"; then
    chmod u+w "$state_dir"
    fail "expected unlink to fail when state persistence is unavailable"
  fi
  chmod u+w "$state_dir"
  if ! awk -F '\t' -v session="$first_session" \
    '$1 == "terminal" && $3 == session { found = 1 } END { exit !found }' \
    "$state_file"; then
    fail "expected failed unlink to preserve the prior dashboard state"
  fi
  "$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" has-session -t "=$first_session"

  TAW_AGENT_DASHBOARD_STATE_FILE="$state_file" \
    run_dashboard "$wrapper" unlink "$session_id" "$first_source"
  if "$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" has-session \
    -t "=$first_session" 2>/dev/null; then
    fail "expected successful unlink to remove the private view session"
  fi
  assert_dashboard_file_contains "$state_file" $'exclude\t'"$first_source"
}

test_dashboard_cleans_source_lookup_failure() {
  local project home wrapper pane session_count

  DASHBOARD_REAL_TMUX="$(command -v tmux || true)"
  [[ -n "$DASHBOARD_REAL_TMUX" ]] || return 0
  DASHBOARD_SOCKET="portables-agent-dashboard-source-failure-$$-$RANDOM"
  trap cleanup_dashboard_server EXIT
  project="$TEST_TMPDIR/project"
  home="$TEST_TMPDIR/home"
  mkdir -p "$project" "$home/.zfuns"
  ln -s "$DASHBOARD_SCRIPT" "$home/.zfuns/taw-agent-dashboard"
  wrapper="$(make_dashboard_tmux_wrapper "$TEST_TMPDIR/tmux-wrapper")"
  make_dashboard_osascript "$TEST_TMPDIR/tmux-wrapper" >/dev/null
  : >"$TEST_TMPDIR/tmux.log"
  : >"$TEST_TMPDIR/osascript.log"

  "$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" -f /dev/null \
    new-session -d -s source -n first -c "$project" 'sleep 300'
  "$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" -f /dev/null \
    new-window -d -t source: -n second -c "$project" 'sleep 300'
  while IFS= read -r pane; do
    run_dashboard_status "$wrapper" "$home" "$pane" codex
  done < <("$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" list-panes -a \
    -t source -F '#{pane_id}')

  if TAW_DASHBOARD_FAIL_DISPLAY_MESSAGE=1 run_dashboard "$wrapper" open; then
    fail "expected dashboard creation to fail when a source lookup disappears"
  fi
  assert_not_exists "$TEST_TMPDIR/dashboard.state"
  session_count="$("$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" list-sessions \
    -F '#{@taw_agent_dashboard_session}' | awk '$1 == 1 { print }')"
  [[ -z "$session_count" ]] || fail "expected source lookup failure to clean prior view sessions"
  "$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" has-session -t source
}

test_dashboard_preserves_state_on_health_query_failure() {
  local project home wrapper pane session

  DASHBOARD_REAL_TMUX="$(command -v tmux || true)"
  [[ -n "$DASHBOARD_REAL_TMUX" ]] || return 0
  DASHBOARD_SOCKET="portables-agent-dashboard-health-failure-$$-$RANDOM"
  trap cleanup_dashboard_server EXIT
  project="$TEST_TMPDIR/project"
  home="$TEST_TMPDIR/home"
  mkdir -p "$project" "$home/.zfuns"
  ln -s "$DASHBOARD_SCRIPT" "$home/.zfuns/taw-agent-dashboard"
  wrapper="$(make_dashboard_tmux_wrapper "$TEST_TMPDIR/tmux-wrapper")"
  make_dashboard_osascript "$TEST_TMPDIR/tmux-wrapper" >/dev/null
  : >"$TEST_TMPDIR/tmux.log"
  : >"$TEST_TMPDIR/osascript.log"

  "$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" -f /dev/null \
    new-session -d -s source -n work -c "$project" 'sleep 300'
  pane="$("$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" display-message \
    -p -t source:work '#{pane_id}')"
  run_dashboard_status "$wrapper" "$home" "$pane" codex
  TAW_FAKE_GHOSTTY_BUILD=$'dashboard-window-11\nterminal-14' \
    run_dashboard "$wrapper" open
  session="$(awk -F '\t' '$1 == "terminal" { print $3 }' \
    "$TEST_TMPDIR/dashboard.state")"

  if TAW_FAKE_GHOSTTY_HEALTH_ERROR=1 run_dashboard "$wrapper" sync; then
    fail "expected sync to report a Ghostty health query failure"
  fi
  assert_exists "$TEST_TMPDIR/dashboard.state"
  "$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" has-session -t "=$session"

  TAW_FAKE_GHOSTTY_HEALTH=0 run_dashboard "$wrapper" sync
  assert_not_exists "$TEST_TMPDIR/dashboard.state"
  if "$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" has-session \
    -t "=$session" 2>/dev/null; then
    fail "expected an explicitly missing dashboard to clean its view session"
  fi
}

test_dashboard_preserves_state_on_close_health_query_failure() {
  local project home wrapper pane session

  DASHBOARD_REAL_TMUX="$(command -v tmux || true)"
  [[ -n "$DASHBOARD_REAL_TMUX" ]] || return 0
  DASHBOARD_SOCKET="portables-agent-dashboard-close-health-failure-$$-$RANDOM"
  trap cleanup_dashboard_server EXIT
  project="$TEST_TMPDIR/project"
  home="$TEST_TMPDIR/home"
  mkdir -p "$project" "$home/.zfuns"
  ln -s "$DASHBOARD_SCRIPT" "$home/.zfuns/taw-agent-dashboard"
  wrapper="$(make_dashboard_tmux_wrapper "$TEST_TMPDIR/tmux-wrapper")"
  make_dashboard_osascript "$TEST_TMPDIR/tmux-wrapper" >/dev/null
  : >"$TEST_TMPDIR/tmux.log"
  : >"$TEST_TMPDIR/osascript.log"

  "$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" -f /dev/null \
    new-session -d -s source -n work -c "$project" 'sleep 300'
  pane="$("$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" display-message \
    -p -t source:work '#{pane_id}')"
  run_dashboard_status "$wrapper" "$home" "$pane" codex
  TAW_FAKE_GHOSTTY_BUILD=$'dashboard-window-12\nterminal-15' \
    run_dashboard "$wrapper" open
  session="$(awk -F '\t' '$1 == "terminal" { print $3 }' \
    "$TEST_TMPDIR/dashboard.state")"

  if TAW_FAKE_GHOSTTY_HEALTH_ERROR=1 run_dashboard "$wrapper" close; then
    fail "expected close to report a Ghostty health query failure"
  fi
  assert_exists "$TEST_TMPDIR/dashboard.state"
  "$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" has-session -t "=$session"

  TAW_FAKE_GHOSTTY_HEALTH=0 run_dashboard "$wrapper" close
  assert_not_exists "$TEST_TMPDIR/dashboard.state"
  if "$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" has-session \
    -t "=$session" 2>/dev/null; then
    fail "expected close after a successful health query to remove the view session"
  fi
}

test_dashboard_preserves_state_on_tmux_membership_query_failure() {
  local project home wrapper pane session

  DASHBOARD_REAL_TMUX="$(command -v tmux || true)"
  [[ -n "$DASHBOARD_REAL_TMUX" ]] || return 0
  DASHBOARD_SOCKET="portables-agent-dashboard-tmux-failure-$$-$RANDOM"
  trap cleanup_dashboard_server EXIT
  project="$TEST_TMPDIR/project"
  home="$TEST_TMPDIR/home"
  mkdir -p "$project" "$home/.zfuns"
  ln -s "$DASHBOARD_SCRIPT" "$home/.zfuns/taw-agent-dashboard"
  wrapper="$(make_dashboard_tmux_wrapper "$TEST_TMPDIR/tmux-wrapper")"
  make_dashboard_osascript "$TEST_TMPDIR/tmux-wrapper" >/dev/null
  : >"$TEST_TMPDIR/tmux.log"
  : >"$TEST_TMPDIR/osascript.log"

  "$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" -f /dev/null \
    new-session -d -s source -n work -c "$project" 'sleep 300'
  pane="$("$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" display-message \
    -p -t source:work '#{pane_id}')"
  run_dashboard_status "$wrapper" "$home" "$pane" codex
  TAW_FAKE_GHOSTTY_BUILD=$'dashboard-window-13\nterminal-16' \
    run_dashboard "$wrapper" open
  session="$(awk -F '\t' '$1 == "terminal" { print $3 }' \
    "$TEST_TMPDIR/dashboard.state")"

  if TAW_DASHBOARD_FAIL_LIST_WINDOWS=1 run_dashboard "$wrapper" sync; then
    fail "expected sync to report a tmux membership query failure"
  fi
  assert_exists "$TEST_TMPDIR/dashboard.state"
  "$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" has-session -t "=$session"
}

test_dashboard_rebuilds_missing_saved_view() {
  local project home wrapper pane session source_window marker source

  DASHBOARD_REAL_TMUX="$(command -v tmux || true)"
  [[ -n "$DASHBOARD_REAL_TMUX" ]] || return 0
  DASHBOARD_SOCKET="portables-agent-dashboard-missing-view-$$-$RANDOM"
  trap cleanup_dashboard_server EXIT
  project="$TEST_TMPDIR/project"
  home="$TEST_TMPDIR/home"
  mkdir -p "$project" "$home/.zfuns"
  ln -s "$DASHBOARD_SCRIPT" "$home/.zfuns/taw-agent-dashboard"
  wrapper="$(make_dashboard_tmux_wrapper "$TEST_TMPDIR/tmux-wrapper")"
  make_dashboard_osascript "$TEST_TMPDIR/tmux-wrapper" >/dev/null
  : >"$TEST_TMPDIR/tmux.log"
  : >"$TEST_TMPDIR/osascript.log"

  "$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" -f /dev/null \
    new-session -d -s source -n work -c "$project" 'sleep 300'
  pane="$("$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" display-message \
    -p -t source:work '#{pane_id}')"
  run_dashboard_status "$wrapper" "$home" "$pane" codex

  TAW_FAKE_GHOSTTY_BUILD=$'dashboard-window-14\nterminal-17' \
    run_dashboard "$wrapper" open
  session="$(awk -F '\t' '$1 == "terminal" { print $3 }' \
    "$TEST_TMPDIR/dashboard.state")"
  source_window="$(awk -F '\t' '$1 == "terminal" { print $4 }' \
    "$TEST_TMPDIR/dashboard.state")"
  "$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" kill-session \
    -t "=$session"

  TAW_FAKE_GHOSTTY_BUILD=$'dashboard-window-15\nterminal-18' \
    run_dashboard "$wrapper" sync
  assert_eq 2 "$(grep -Fc 'mode=build' "$TEST_TMPDIR/osascript.log")" \
    "expected a missing saved view to trigger a rebuild"
  session="$(awk -F '\t' '$1 == "terminal" { print $3 }' \
    "$TEST_TMPDIR/dashboard.state")"
  marker="$("$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" show-option \
    -qv -t "$session" @taw_agent_dashboard_session)"
  source="$("$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" show-option \
    -qv -t "$session" @taw_agent_dashboard_window_id)"
  [[ "$marker" = 1 ]] || fail "expected the rebuilt view to be dashboard-owned"
  [[ "$source" = "$source_window" ]] || \
    fail "expected the rebuilt view to retain its source window"
  "$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" has-session -t "=$session"
}

test_dashboard_rebuilds_missing_terminal() {
  local project home wrapper pane old_session

  DASHBOARD_REAL_TMUX="$(command -v tmux || true)"
  [[ -n "$DASHBOARD_REAL_TMUX" ]] || return 0
  DASHBOARD_SOCKET="portables-agent-dashboard-missing-terminal-$$-$RANDOM"
  trap cleanup_dashboard_server EXIT
  project="$TEST_TMPDIR/project"
  home="$TEST_TMPDIR/home"
  mkdir -p "$project" "$home/.zfuns"
  ln -s "$DASHBOARD_SCRIPT" "$home/.zfuns/taw-agent-dashboard"
  wrapper="$(make_dashboard_tmux_wrapper "$TEST_TMPDIR/tmux-wrapper")"
  make_dashboard_osascript "$TEST_TMPDIR/tmux-wrapper" >/dev/null
  : >"$TEST_TMPDIR/tmux.log"
  : >"$TEST_TMPDIR/osascript.log"

  "$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" -f /dev/null \
    new-session -d -s source -n first -c "$project" 'sleep 300'
  "$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" -f /dev/null \
    new-window -d -t source: -n second -c "$project" 'sleep 300'
  while IFS= read -r pane; do
    run_dashboard_status "$wrapper" "$home" "$pane" codex
  done < <("$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" list-panes -a \
    -t source -F '#{pane_id}')

  TAW_FAKE_GHOSTTY_BUILD=$'dashboard-window-18\nterminal-23\nterminal-24' \
    run_dashboard "$wrapper" open
  old_session="$(awk -F '\t' '$1 == "terminal" { print $3; exit }' \
    "$TEST_TMPDIR/dashboard.state")"

  TAW_FAKE_GHOSTTY_MISSING_TERMINAL=1 \
    TAW_FAKE_GHOSTTY_BUILD=$'dashboard-window-19\nterminal-25\nterminal-26' \
    run_dashboard "$wrapper" sync
  assert_eq 2 "$(grep -Fc 'mode=build' "$TEST_TMPDIR/osascript.log")" \
    "expected a missing Ghostty terminal to trigger a rebuild"
  assert_dashboard_file_contains "$TEST_TMPDIR/dashboard.state" \
    $'terminal\tterminal-25'
  if "$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" has-session \
    -t "=$old_session" 2>/dev/null; then
    :
  else
    fail "expected the rebuilt dashboard to retain its private tmux session"
  fi
}

test_dashboard_rolls_back_when_old_window_close_fails() {
  local project home wrapper pane old_window old_session

  DASHBOARD_REAL_TMUX="$(command -v tmux || true)"
  [[ -n "$DASHBOARD_REAL_TMUX" ]] || return 0
  DASHBOARD_SOCKET="portables-agent-dashboard-old-close-failure-$$-$RANDOM"
  trap cleanup_dashboard_server EXIT
  project="$TEST_TMPDIR/project"
  home="$TEST_TMPDIR/home"
  mkdir -p "$project" "$home/.zfuns"
  ln -s "$DASHBOARD_SCRIPT" "$home/.zfuns/taw-agent-dashboard"
  wrapper="$(make_dashboard_tmux_wrapper "$TEST_TMPDIR/tmux-wrapper")"
  make_dashboard_osascript "$TEST_TMPDIR/tmux-wrapper" >/dev/null
  : >"$TEST_TMPDIR/tmux.log"
  : >"$TEST_TMPDIR/osascript.log"

  "$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" -f /dev/null \
    new-session -d -s source -n first -c "$project" 'sleep 300'
  pane="$("$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" display-message \
    -p -t source:first '#{pane_id}')"
  run_dashboard_status "$wrapper" "$home" "$pane" codex
  TAW_FAKE_GHOSTTY_BUILD=$'dashboard-window-20\nterminal-27' \
    run_dashboard "$wrapper" open
  old_window="$(awk -F '\t' '$1 == "window" { print $2 }' \
    "$TEST_TMPDIR/dashboard.state")"
  old_session="$(awk -F '\t' '$1 == "terminal" { print $3 }' \
    "$TEST_TMPDIR/dashboard.state")"

  "$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" -f /dev/null \
    new-window -d -t source: -n second -c "$project" 'sleep 300'
  pane="$("$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" display-message \
    -p -t source:second '#{pane_id}')"
  run_dashboard_status "$wrapper" "$home" "$pane" codex

  if TAW_FAKE_GHOSTTY_CLOSE_ERROR_ONCE=1 \
    TAW_FAKE_GHOSTTY_BUILD=$'dashboard-window-21\nterminal-28\nterminal-29' \
    run_dashboard "$wrapper" sync; then
    fail "expected rebuild to report failure closing the old dashboard"
  fi
  assert_dashboard_file_contains "$TEST_TMPDIR/dashboard.state" \
    $'window\t'"$old_window"
  assert_dashboard_file_contains "$TEST_TMPDIR/dashboard.state" \
    $'terminal\tterminal-27'
  if "$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" has-session \
    -t "=taw-agent-view-1" 2>/dev/null; then
    fail "expected the rolled-back new view session to be cleaned up"
  fi
  "$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" has-session -t "=$old_session"

  TAW_FAKE_GHOSTTY_BUILD=$'dashboard-window-22\nterminal-30\nterminal-31' \
    run_dashboard "$wrapper" sync
  assert_dashboard_file_contains "$TEST_TMPDIR/dashboard.state" \
    $'terminal\tterminal-31'
}

test_dashboard_preserves_state_when_view_teardown_fails() {
  local project home wrapper pane session

  DASHBOARD_REAL_TMUX="$(command -v tmux || true)"
  [[ -n "$DASHBOARD_REAL_TMUX" ]] || return 0
  DASHBOARD_SOCKET="portables-agent-dashboard-teardown-failure-$$-$RANDOM"
  trap cleanup_dashboard_server EXIT
  project="$TEST_TMPDIR/project"
  home="$TEST_TMPDIR/home"
  mkdir -p "$project" "$home/.zfuns"
  ln -s "$DASHBOARD_SCRIPT" "$home/.zfuns/taw-agent-dashboard"
  wrapper="$(make_dashboard_tmux_wrapper "$TEST_TMPDIR/tmux-wrapper")"
  make_dashboard_osascript "$TEST_TMPDIR/tmux-wrapper" >/dev/null
  : >"$TEST_TMPDIR/tmux.log"
  : >"$TEST_TMPDIR/osascript.log"

  "$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" -f /dev/null \
    new-session -d -s source -n work -c "$project" 'sleep 300'
  pane="$("$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" display-message \
    -p -t source:work '#{pane_id}')"
  run_dashboard_status "$wrapper" "$home" "$pane" codex
  TAW_FAKE_GHOSTTY_BUILD=$'dashboard-window-23\nterminal-32' \
    run_dashboard "$wrapper" open
  session="$(awk -F '\t' '$1 == "terminal" { print $3 }' \
    "$TEST_TMPDIR/dashboard.state")"

  if TAW_DASHBOARD_FAIL_KILL_SESSION=1 run_dashboard "$wrapper" close; then
    fail "expected close to report a private-session teardown failure"
  fi
  assert_exists "$TEST_TMPDIR/dashboard.state"
  "$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" has-session -t "=$session"

  run_dashboard "$wrapper" close
  assert_not_exists "$TEST_TMPDIR/dashboard.state"
  if "$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" has-session \
    -t "=$session" 2>/dev/null; then
    fail "expected a successful retry to remove the private session"
  fi
}

test_dashboard_preserves_state_when_rebuild_fails() {
  local project home wrapper pane first_session second_session old_state close_count

  DASHBOARD_REAL_TMUX="$(command -v tmux || true)"
  [[ -n "$DASHBOARD_REAL_TMUX" ]] || return 0
  DASHBOARD_SOCKET="portables-agent-dashboard-rebuild-failure-$$-$RANDOM"
  trap cleanup_dashboard_server EXIT
  project="$TEST_TMPDIR/project"
  home="$TEST_TMPDIR/home"
  mkdir -p "$project" "$home/.zfuns"
  ln -s "$DASHBOARD_SCRIPT" "$home/.zfuns/taw-agent-dashboard"
  wrapper="$(make_dashboard_tmux_wrapper "$TEST_TMPDIR/tmux-wrapper")"
  make_dashboard_osascript "$TEST_TMPDIR/tmux-wrapper" >/dev/null
  : >"$TEST_TMPDIR/tmux.log"
  : >"$TEST_TMPDIR/osascript.log"

  "$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" -f /dev/null \
    new-session -d -s source -n first -c "$project" 'sleep 300'
  "$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" -f /dev/null \
    new-window -d -t source: -n second -c "$project" 'sleep 300'
  while IFS= read -r pane; do
    run_dashboard_status "$wrapper" "$home" "$pane" codex
  done < <("$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" list-panes -a \
    -t source -F '#{pane_id}')

  TAW_FAKE_GHOSTTY_BUILD=$'dashboard-window-16\nterminal-19\nterminal-20' \
    run_dashboard "$wrapper" open
  first_session="$(awk -F '\t' '$1 == "terminal" { print $3; exit }' \
    "$TEST_TMPDIR/dashboard.state")"
  second_session="$(awk -F '\t' '$1 == "terminal" { print $3; exit }' \
    "$TEST_TMPDIR/dashboard.state" | tail -n 1)"
  old_state="$(<"$TEST_TMPDIR/dashboard.state")"

  "$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" -f /dev/null \
    new-window -d -t source: -n third -c "$project" 'sleep 300'
  pane="$("$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" display-message \
    -p -t source:third '#{pane_id}')"
  run_dashboard_status "$wrapper" "$home" "$pane" codex

  if TAW_DASHBOARD_FAIL_DISPLAY_MESSAGE=1 TAW_DASHBOARD_FAIL_DISPLAY_AT=3 \
    run_dashboard "$wrapper" sync; then
    fail "expected rebuild to fail when the new source disappears"
  fi
  [[ "$old_state" = "$(<"$TEST_TMPDIR/dashboard.state")" ]] || \
    fail "expected failed rebuild to preserve the prior state"
  "$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" has-session \
    -t "=$first_session"
  "$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" has-session \
    -t "=$second_session"
  close_count="$(grep -Fc 'mode=close' "$TEST_TMPDIR/osascript.log" || true)"
  assert_eq 0 "$close_count" \
    "expected failed rebuild not to close the prior dashboard"
}

test_dashboard_preserves_state_when_close_terminal_fails() {
  local project home wrapper pane first_session first_source session_id

  DASHBOARD_REAL_TMUX="$(command -v tmux || true)"
  [[ -n "$DASHBOARD_REAL_TMUX" ]] || return 0
  DASHBOARD_SOCKET="portables-agent-dashboard-close-terminal-failure-$$-$RANDOM"
  trap cleanup_dashboard_server EXIT
  project="$TEST_TMPDIR/project"
  home="$TEST_TMPDIR/home"
  mkdir -p "$project" "$home/.zfuns"
  ln -s "$DASHBOARD_SCRIPT" "$home/.zfuns/taw-agent-dashboard"
  wrapper="$(make_dashboard_tmux_wrapper "$TEST_TMPDIR/tmux-wrapper")"
  make_dashboard_osascript "$TEST_TMPDIR/tmux-wrapper" >/dev/null
  : >"$TEST_TMPDIR/tmux.log"
  : >"$TEST_TMPDIR/osascript.log"

  "$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" -f /dev/null \
    new-session -d -s source -n first -c "$project" 'sleep 300'
  "$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" -f /dev/null \
    new-window -d -t source: -n second -c "$project" 'sleep 300'
  while IFS= read -r pane; do
    run_dashboard_status "$wrapper" "$home" "$pane" codex
  done < <("$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" list-panes -a \
    -t source -F '#{pane_id}')

  TAW_FAKE_GHOSTTY_BUILD=$'dashboard-window-17\nterminal-21\nterminal-22' \
    run_dashboard "$wrapper" open
  first_session="$(awk -F '\t' '$1 == "terminal" { print $3; exit }' \
    "$TEST_TMPDIR/dashboard.state")"
  first_source="$(awk -F '\t' '$1 == "terminal" { print $4; exit }' \
    "$TEST_TMPDIR/dashboard.state")"
  session_id="$("$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" list-sessions \
    -F $'#{session_id}\t#{session_name}' \
    | awk -F '\t' -v name="$first_session" '$2 == name { print $1 }')"
  [[ -n "$session_id" ]] || fail "expected a tmux session ID for $first_session"

  if TAW_FAKE_GHOSTTY_CLOSE_TERMINAL_ERROR=1 \
    run_dashboard "$wrapper" unlink "$session_id" "$first_source"; then
    fail "expected unlink to report a close-terminal failure"
  fi
  if grep -Fq $'exclude\t'"$first_source" "$TEST_TMPDIR/dashboard.state"; then
    fail "expected close-terminal failure to preserve the source record"
  fi
  if ! awk -F '\t' -v session="$first_session" \
    '$1 == "terminal" && $3 == session { found = 1 } END { exit !found }' \
    "$TEST_TMPDIR/dashboard.state"; then
    fail "expected close-terminal failure to preserve dashboard state"
  fi
  "$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" has-session \
    -t "=$first_session"

  run_dashboard "$wrapper" unlink "$session_id" "$first_source"
  if awk -F '\t' -v session="$first_session" \
    '$1 == "terminal" && $3 == session { found = 1 } END { exit !found }' \
    "$TEST_TMPDIR/dashboard.state"; then
    fail "expected successful unlink to remove the source record"
  fi
  assert_dashboard_file_contains "$TEST_TMPDIR/dashboard.state" \
    $'exclude\t'"$first_source"
  if "$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" has-session \
    -t "=$first_session" 2>/dev/null; then
    fail "expected successful unlink to remove the private view session"
  fi
}

test_agent_unlink_syncs_dashboard() {
  local project home wrapper source_window pane session
  local attempt

  DASHBOARD_REAL_TMUX="$(command -v tmux || true)"
  [[ -n "$DASHBOARD_REAL_TMUX" ]] || return 0
  DASHBOARD_SOCKET="portables-agent-dashboard-agent-unlink-$$-$RANDOM"
  trap cleanup_dashboard_server EXIT
  project="$TEST_TMPDIR/project"
  home="$TEST_TMPDIR/home"
  mkdir -p "$project" "$home/.zfuns"
  ln -s "$DASHBOARD_SCRIPT" "$home/.zfuns/taw-agent-dashboard"
  wrapper="$(make_dashboard_tmux_wrapper "$TEST_TMPDIR/tmux-wrapper")"
  make_dashboard_osascript "$TEST_TMPDIR/tmux-wrapper" >/dev/null
  : >"$TEST_TMPDIR/tmux.log"
  : >"$TEST_TMPDIR/osascript.log"

  "$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" -f /dev/null \
    new-session -d -s source -n work -c "$project" 'sleep 300'
  pane="$("$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" display-message \
    -p -t source:work '#{pane_id}')"
  run_dashboard_status "$wrapper" "$home" "$pane" claude
  source_window="$("$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" list-windows \
    -t agents -F '#{window_id}')"
  TAW_FAKE_GHOSTTY_BUILD=$'dashboard-window-4\nterminal-6' \
    run_dashboard "$wrapper" open
  session="$(awk -F '\t' '$1 == "terminal" { print $3 }' \
    "$TEST_TMPDIR/dashboard.state")"

  run_dashboard_status_unlink "$wrapper" "$home" "$source_window"

  for ((attempt = 0; attempt < 100; attempt++)); do
    [[ ! -e "$TEST_TMPDIR/dashboard.state" ]] && break
    sleep 0.05
  done
  assert_not_exists "$TEST_TMPDIR/dashboard.state"
  if "$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" has-session -t "=$session"; then
    fail "expected agent unlink to remove the private view session"
  fi
  "$DASHBOARD_REAL_TMUX" -L "$DASHBOARD_SOCKET" has-session -t source
}

test_case "agent dashboard: private views and no reopen" \
  test_dashboard_uses_private_views_and_does_not_reopen
test_case "agent dashboard: close preserves source" \
  test_dashboard_closes_private_views_but_keeps_source_alive
test_case "agent dashboard: unlink resolves session IDs" \
  test_dashboard_unlink_resolves_session_id
test_case "agent dashboard: preserves explicitly closed views" \
  test_dashboard_preserves_explicitly_closed_views
test_case "agent dashboard: cleans failed view sessions" \
  test_dashboard_cleans_failed_new_view_session
test_case "agent dashboard: cleans state persistence failures" \
  test_dashboard_cleans_state_persistence_failure
test_case "agent dashboard: build errors close partial windows" \
  test_dashboard_build_errors_close_partial_window
test_case "agent dashboard: preserves state on unlink persistence failure" \
  test_dashboard_preserves_state_on_unlink_persistence_failure
test_case "agent dashboard: cleans source lookup failures" \
  test_dashboard_cleans_source_lookup_failure
test_case "agent dashboard: preserves state on health query failure" \
  test_dashboard_preserves_state_on_health_query_failure
test_case "agent dashboard: preserves state on close health query failure" \
  test_dashboard_preserves_state_on_close_health_query_failure
test_case "agent dashboard: preserves state on tmux query failure" \
  test_dashboard_preserves_state_on_tmux_membership_query_failure
test_case "agent dashboard: rebuilds missing saved views" \
  test_dashboard_rebuilds_missing_saved_view
test_case "agent dashboard: rebuilds missing terminals" \
  test_dashboard_rebuilds_missing_terminal
test_case "agent dashboard: rolls back old-window close failures" \
  test_dashboard_rolls_back_when_old_window_close_fails
test_case "agent dashboard: preserves state on teardown failures" \
  test_dashboard_preserves_state_when_view_teardown_fails
test_case "agent dashboard: preserves state when rebuild fails" \
  test_dashboard_preserves_state_when_rebuild_fails
test_case "agent dashboard: preserves state when close-terminal fails" \
  test_dashboard_preserves_state_when_close_terminal_fails
test_case "agent dashboard: agent unlink syncs dashboard" \
  test_agent_unlink_syncs_dashboard
