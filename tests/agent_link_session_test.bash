AGENT_LINK_STATUS="$REPO_ROOT/home/.zfuns/taw-agent-status"
AGENT_LINK_TMUX_CONFIG="$REPO_ROOT/home/.config/tmux/tmux.conf"
AGENT_LINK_REAL_TMUX=
AGENT_LINK_SOCKET=

assert_agent_link_file_contains() {
  local path="$1"
  local expected="$2"

  [[ -f "$path" ]] || fail "expected file: $path"
  grep -Fq -- "$expected" "$path" \
    || fail "expected $path to contain: $expected"
}

cleanup_agent_link_server() {
  if [[ -n "$AGENT_LINK_REAL_TMUX" && -n "$AGENT_LINK_SOCKET" ]]; then
    "$AGENT_LINK_REAL_TMUX" -L "$AGENT_LINK_SOCKET" kill-server \
      >/dev/null 2>&1 || true
  fi
}

make_agent_link_tmux_wrapper() {
  local root="$1"
  local bin="$root/bin"

  mkdir -p "$bin"
  cat >"$bin/tmux" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

args=( "$@" )

{
  printf '%s' "${1:-}"
  shift || true
  printf '\t%s' "$@"
  printf '\n'
} >>"$TAW_AGENT_LINK_TMUX_LOG"
exec "$TAW_AGENT_LINK_REAL_TMUX" -L "$TAW_AGENT_LINK_SOCKET" "${args[@]}"
EOF
  chmod +x "$bin/tmux"
  printf '%s\n' "$bin"
}

run_agent_link_status() {
  local bin="$1"
  shift

  TMUX=/tmp/tmux PATH="$bin:$PATH" TAW_AGENT_LINK_REAL_TMUX="$AGENT_LINK_REAL_TMUX" \
    TAW_AGENT_LINK_SOCKET="$AGENT_LINK_SOCKET" TAW_AGENT_LINK_TMUX_LOG="$TEST_TMPDIR/tmux.log" \
    "$AGENT_LINK_STATUS" "$@"
}

test_agent_link_session_reconciles_direct_agent_panes() {
  local project temp_parent bin first_agent second_agent added_agent
  local first_window second_window linked marker suppression linked_after
  local -a temp_dirs

  AGENT_LINK_REAL_TMUX="$(command -v tmux || true)"
  [[ -n "$AGENT_LINK_REAL_TMUX" ]] || return 0
  AGENT_LINK_SOCKET="portables-agent-links-$$-$RANDOM"
  trap cleanup_agent_link_server EXIT
  project="$TEST_TMPDIR/project"
  temp_parent="$TEST_TMPDIR/tmp"
  mkdir -p "$project" "$temp_parent"
  : >"$TEST_TMPDIR/tmux.log"
  bin="$(make_agent_link_tmux_wrapper "$TEST_TMPDIR/wrapper")"

  "$AGENT_LINK_REAL_TMUX" -L "$AGENT_LINK_SOCKET" -f /dev/null \
    new-session -d -s source -n work -c "$project" 'sleep 300'
  first_agent="$(
    "$AGENT_LINK_REAL_TMUX" -L "$AGENT_LINK_SOCKET" split-window -d -h \
      -P -F '#{pane_id}' -t source:work -c "$project" 'sleep 300'
  )"
  first_window="$(
    "$AGENT_LINK_REAL_TMUX" -L "$AGENT_LINK_SOCKET" display-message \
      -p -t "$first_agent" '#{window_id}'
  )"

  TMPDIR="$temp_parent" run_agent_link_status "$bin" start codex "$first_agent"

  linked="$(
    "$AGENT_LINK_REAL_TMUX" -L "$AGENT_LINK_SOCKET" list-windows \
      -t agents -F '#{window_id}'
  )"
  marker="$(
    "$AGENT_LINK_REAL_TMUX" -L "$AGENT_LINK_SOCKET" show-option \
      -qv -t agents @taw_agent_link_session
  )"
  assert_eq "$first_window" "$linked" "expected the direct agent window to be linked"
  assert_eq 1 "$marker" "expected the aggregate session marker"
  assert_agent_link_file_contains "$TEST_TMPDIR/tmux.log" \
    $'link-window\t-d\t-k\t-s\t'"$first_window"
  shopt -s nullglob
  temp_dirs=( "$temp_parent"/??? )
  shopt -u nullglob
  assert_eq 1 "${#temp_dirs[@]}" "expected the successful session temp directory to remain"
  assert_agent_link_file_contains "$TEST_TMPDIR/tmux.log" $'new-session\t-d\t-P'
  assert_agent_link_file_contains "$TEST_TMPDIR/tmux.log" $'-c\t'"${temp_dirs[0]}"

  second_agent="$(
    "$AGENT_LINK_REAL_TMUX" -L "$AGENT_LINK_SOCKET" new-window -d \
      -P -F '#{pane_id}' -t source: -n second -c "$project" 'sleep 300'
  )"
  second_window="$(
    "$AGENT_LINK_REAL_TMUX" -L "$AGENT_LINK_SOCKET" display-message \
      -p -t "$second_agent" '#{window_id}'
  )"
  run_agent_link_status "$bin" start claude "$second_agent"
  linked="$(
    "$AGENT_LINK_REAL_TMUX" -L "$AGENT_LINK_SOCKET" list-windows \
      -t agents -F '#{window_id}'
  )"
  assert_eq "$first_window"$'\n'"$second_window" "$linked" \
    "expected new agent windows after existing links"

  run_agent_link_status "$bin" sync
  linked_after="$(
    "$AGENT_LINK_REAL_TMUX" -L "$AGENT_LINK_SOCKET" list-windows \
      -t agents -F '#{window_id}'
  )"
  assert_eq "$linked" "$linked_after" "expected reconciliation to be idempotent"

  run_agent_link_status "$bin" unlink "$first_window"
  linked="$(
    "$AGENT_LINK_REAL_TMUX" -L "$AGENT_LINK_SOCKET" list-windows \
      -t agents -F '#{window_id}'
  )"
  suppression="$(
    "$AGENT_LINK_REAL_TMUX" -L "$AGENT_LINK_SOCKET" show-option \
      -wqv -t "$first_window" @taw_agent_link_suppressed
  )"
  assert_eq "$second_window" "$linked" "expected only the aggregate link to be removed"
  assert_eq "$first_agent=codex," "$suppression" "expected membership suppression"
  "$AGENT_LINK_REAL_TMUX" -L "$AGENT_LINK_SOCKET" has-session -t source

  run_agent_link_status "$bin" set codex thinking "$first_agent"
  run_agent_link_status "$bin" sync
  linked="$(
    "$AGENT_LINK_REAL_TMUX" -L "$AGENT_LINK_SOCKET" list-windows \
      -t agents -F '#{window_id}'
  )"
  assert_eq "$second_window" "$linked" "expected state changes to preserve suppression"

  added_agent="$(
    "$AGENT_LINK_REAL_TMUX" -L "$AGENT_LINK_SOCKET" split-window -d \
      -P -F '#{pane_id}' -t "$first_agent" -c "$project" 'sleep 300'
  )"
  run_agent_link_status "$bin" start claude "$added_agent"
  linked="$(
    "$AGENT_LINK_REAL_TMUX" -L "$AGENT_LINK_SOCKET" list-windows \
      -t agents -F '#{window_id}'
  )"
  suppression="$(
    "$AGENT_LINK_REAL_TMUX" -L "$AGENT_LINK_SOCKET" show-option \
      -wqv -t "$first_window" @taw_agent_link_suppressed
  )"
  assert_eq "$second_window"$'\n'"$first_window" "$linked" \
    "expected changed membership to append the window again"
  assert_eq "" "$suppression" "expected changed membership to clear suppression"

  "$AGENT_LINK_REAL_TMUX" -L "$AGENT_LINK_SOCKET" kill-window -t "source:$first_window"
  linked="$(
    "$AGENT_LINK_REAL_TMUX" -L "$AGENT_LINK_SOCKET" list-windows \
      -t agents -F '#{window_id}'
  )"
  assert_eq "$second_window" "$linked" "expected source kill to remove the shared link"

  run_agent_link_status "$bin" clear "$second_agent"
  if "$AGENT_LINK_REAL_TMUX" -L "$AGENT_LINK_SOCKET" has-session -t agents 2>/dev/null; then
    fail "expected the empty aggregate session to be destroyed"
  fi
}

test_agent_link_session_removes_temp_dir_when_creation_fails() {
  local bin temp_parent output
  local -a temp_dirs

  bin="$TEST_TMPDIR/bin"
  temp_parent="$TEST_TMPDIR/tmp"
  mkdir -p "$bin" "$temp_parent"
  cat >"$bin/tmux" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
  wait-for) ;;
  list-sessions) printf '$0\tsource\t\n' ;;
  list-panes) printf '$0\t@0\t%%1\tcodex\t\n' ;;
  new-session) exit 1 ;;
esac
EOF
  chmod +x "$bin/tmux"

  if output="$(TMUX=/tmp/tmux TMPDIR="$temp_parent" PATH="$bin:$PATH" \
    "$AGENT_LINK_STATUS" sync 2>&1)"; then
    fail "expected failed tmux session creation to fail"
  fi
  shopt -s nullglob
  temp_dirs=( "$temp_parent"/??? )
  shopt -u nullglob
  assert_eq 0 "${#temp_dirs[@]}" "expected the unused temp directory to be removed"
}

test_agent_link_session_refuses_unowned_name() {
  local bin pane before output after

  AGENT_LINK_REAL_TMUX="$(command -v tmux || true)"
  [[ -n "$AGENT_LINK_REAL_TMUX" ]] || return 0
  AGENT_LINK_SOCKET="portables-agent-link-conflict-$$-$RANDOM"
  trap cleanup_agent_link_server EXIT
  : >"$TEST_TMPDIR/tmux.log"
  bin="$(make_agent_link_tmux_wrapper "$TEST_TMPDIR/wrapper")"

  "$AGENT_LINK_REAL_TMUX" -L "$AGENT_LINK_SOCKET" -f /dev/null \
    new-session -d -s source -n work 'sleep 300'
  "$AGENT_LINK_REAL_TMUX" -L "$AGENT_LINK_SOCKET" \
    new-session -d -s agents -n personal 'sleep 300'
  pane="$(
    "$AGENT_LINK_REAL_TMUX" -L "$AGENT_LINK_SOCKET" display-message \
      -p -t source:work '#{pane_id}'
  )"
  "$AGENT_LINK_REAL_TMUX" -L "$AGENT_LINK_SOCKET" \
    set-option -p -t "$pane" @taw_agent codex
  before="$(
    "$AGENT_LINK_REAL_TMUX" -L "$AGENT_LINK_SOCKET" list-windows \
      -t agents -F '#{window_id}'
  )"

  if output="$(run_agent_link_status "$bin" sync 2>&1)"; then
    fail "expected an unowned agents session to be rejected"
  fi
  after="$(
    "$AGENT_LINK_REAL_TMUX" -L "$AGENT_LINK_SOCKET" list-windows \
      -t agents -F '#{window_id}'
  )"
  [[ "$output" = *'refusing unowned tmux session: agents'* ]] \
    || fail "expected an ownership diagnostic: $output"
  assert_eq "$before" "$after" "expected the unowned session to remain untouched"
}

test_agent_link_session_clears_respawned_pane() {
  local bin pane agent pane_pid

  AGENT_LINK_REAL_TMUX="$(command -v tmux || true)"
  [[ -n "$AGENT_LINK_REAL_TMUX" ]] || return 0
  AGENT_LINK_SOCKET="portables-agent-link-respawn-$$-$RANDOM"
  trap cleanup_agent_link_server EXIT
  : >"$TEST_TMPDIR/tmux.log"
  bin="$(make_agent_link_tmux_wrapper "$TEST_TMPDIR/wrapper")"

  "$AGENT_LINK_REAL_TMUX" -L "$AGENT_LINK_SOCKET" -f /dev/null \
    new-session -d -s source -n work 'sleep 300'
  pane="$(
    "$AGENT_LINK_REAL_TMUX" -L "$AGENT_LINK_SOCKET" display-message \
      -p -t source:work '#{pane_id}'
  )"
  run_agent_link_status "$bin" start codex "$pane"
  pane_pid="$(
    "$AGENT_LINK_REAL_TMUX" -L "$AGENT_LINK_SOCKET" show-option \
      -pqv -t "$pane" @taw_agent_pane_pid
  )"
  [[ -n "$pane_pid" ]] || fail "expected the agent pane process to be recorded"

  "$AGENT_LINK_REAL_TMUX" -L "$AGENT_LINK_SOCKET" \
    respawn-pane -k -t "$pane" 'sleep 300'
  run_agent_link_status "$bin" sync
  agent="$(
    "$AGENT_LINK_REAL_TMUX" -L "$AGENT_LINK_SOCKET" show-option \
      -pqv -t "$pane" @taw_agent
  )"
  assert_eq "" "$agent" "expected respawned pane metadata to be cleared"
  if "$AGENT_LINK_REAL_TMUX" -L "$AGENT_LINK_SOCKET" has-session -t agents 2>/dev/null; then
    fail "expected a respawned non-agent pane to be unlinked"
  fi
}

test_agent_link_bindings_load() {
  local home root_binding prefix_binding lower upper rejected

  AGENT_LINK_REAL_TMUX="$(command -v tmux || true)"
  [[ -n "$AGENT_LINK_REAL_TMUX" ]] || return 0
  AGENT_LINK_SOCKET="portables-agent-link-bindings-$$-$RANDOM"
  trap cleanup_agent_link_server EXIT
  home="$TEST_TMPDIR/home"
  mkdir -p "$home/.zfuns"
  ln -s "$AGENT_LINK_STATUS" "$home/.zfuns/taw-agent-status"

  HOME="$home" "$AGENT_LINK_REAL_TMUX" -L "$AGENT_LINK_SOCKET" \
    -f "$AGENT_LINK_TMUX_CONFIG" new-session -d -s binding-test 'sleep 300'
  root_binding="$(
    "$AGENT_LINK_REAL_TMUX" -L "$AGENT_LINK_SOCKET" list-keys -T root C-q
  )"
  prefix_binding="$(
    "$AGENT_LINK_REAL_TMUX" -L "$AGENT_LINK_SOCKET" list-keys -T prefix '&'
  )"
  lower="$(
    "$AGENT_LINK_REAL_TMUX" -L "$AGENT_LINK_SOCKET" display-message \
      -p '#{m/r:^[Yy],y}'
  )"
  upper="$(
    "$AGENT_LINK_REAL_TMUX" -L "$AGENT_LINK_SOCKET" display-message \
      -p '#{m/r:^[Yy],Y}'
  )"
  rejected="$(
    "$AGENT_LINK_REAL_TMUX" -L "$AGENT_LINK_SOCKET" display-message \
      -p '#{m/r:^[Yy],n}'
  )"
  [[ "$root_binding" = *'command-prompt -1'* && "$root_binding" = *'unlink #{window_id}'* ]] \
    || fail "expected C-q to protect windows in agents: $root_binding"
  [[ "$prefix_binding" = *'command-prompt -1'* && "$prefix_binding" = *'confirm-before'* ]] \
    || fail "expected prefix-& to preserve source confirmation: $prefix_binding"
  [[ "$root_binding" = *'#{==:#{@taw_agent_link_session},1}'* \
    && "$prefix_binding" = *'#{==:#{@taw_agent_link_session},1}'* ]] \
    || fail "expected safe bindings to require managed-session ownership"
  assert_eq 1 "$lower" "expected lowercase confirmation"
  assert_eq 1 "$upper" "expected uppercase confirmation"
  assert_eq 0 "$rejected" "expected other confirmation keys to be rejected"
}

test_case "agent link session: reconciles direct agent panes" \
  test_agent_link_session_reconciles_direct_agent_panes
test_case "agent link session: removes temp dir when creation fails" \
  test_agent_link_session_removes_temp_dir_when_creation_fails
test_case "agent link session: refuses an unowned agents session" \
  test_agent_link_session_refuses_unowned_name
test_case "agent link session: clears respawned pane metadata" \
  test_agent_link_session_clears_respawned_pane
test_case "agent link session: safe bindings load" test_agent_link_bindings_load
