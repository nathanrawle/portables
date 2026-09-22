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
  printf '%s\n' "$script"
} >>"$TAW_DASHBOARD_OSASCRIPT_LOG"

case "$mode" in
  health)
    printf '%s\n' "${TAW_FAKE_GHOSTTY_HEALTH:-1}"
    ;;
  build)
    printf '%s' "${TAW_FAKE_GHOSTTY_BUILD:?}"
    ;;
  close|close-terminal|focus)
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
    TAW_AGENT_DASHBOARD_STATE_FILE="$TEST_TMPDIR/dashboard.state" \
    TAW_AGENT_DASHBOARD_OSASCRIPT="$bin/osascript" \
    TAW_FAKE_GHOSTTY_BUILD="${TAW_FAKE_GHOSTTY_BUILD:-}" \
    TAW_FAKE_GHOSTTY_HEALTH="${TAW_FAKE_GHOSTTY_HEALTH:-1}" \
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

test_case "agent dashboard: private views and no reopen" \
  test_dashboard_uses_private_views_and_does_not_reopen
test_case "agent dashboard: close preserves source" \
  test_dashboard_closes_private_views_but_keeps_source_alive
