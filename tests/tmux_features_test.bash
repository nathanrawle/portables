FEATURE_SOCKET=
. "$TESTS_DIR/lib/tmux_client.bash"

feature_tmux() {
  tmux -L "$FEATURE_SOCKET" "$@"
}

setup_feature_server() {
  command -v tmux >/dev/null 2>&1 || return 1
  export HOME="$TEST_TMPDIR/home"
  mkdir -p "$HOME/.zfuns"
  printf '#!/bin/sh\nexit 0\n' >"$HOME/.zfuns/taw-agent-status"
  chmod +x "$HOME/.zfuns/taw-agent-status"
  FEATURE_SOCKET="portables-features-$$-$RANDOM"
  trap 'feature_tmux kill-server >/dev/null 2>&1 || true' EXIT
  feature_tmux -f "$REPO_ROOT/home/.config/tmux/tmux.conf" \
    new-session -d -s features -x 120 -y 40 'sleep 120'
}

test_feature_reload_and_options() {
  local before after hook binding
  command -v tmux >/dev/null 2>&1 || return 0
  setup_feature_server
  before="$(feature_tmux show-hooks -g)"
  feature_tmux source-file "$REPO_ROOT/home/.config/tmux/tmux.conf"
  after="$(feature_tmux show-hooks -g)"
  assert_eq "$before" "$after" 'reloading must replace, rather than duplicate, managed hooks'
  assert_eq on "$(feature_tmux show-options -gv focus-follows-mouse)"
  assert_eq on "$(feature_tmux show-options -sv focus-events)"
  assert_eq on "$(feature_tmux show-options -sv set-clipboard)"
  assert_eq request "$(feature_tmux show-options -sv get-clipboard)"
  assert_eq failed-key "$(feature_tmux show-options -gwv remain-on-exit)"
  assert_eq hybrid "$(feature_tmux show-options -gwv copy-mode-line-numbers)"
  assert_eq modal "$(feature_tmux show-options -gwv pane-scrollbars)"
  assert_eq top-floating "$(feature_tmux show-options -gwv pane-border-status)"
  [[ "$(feature_tmux list-keys -T copy-mode-vi R)" == *refresh-toggle* ]] || fail 'R should toggle live refresh'
  [[ "$(feature_tmux list-keys -T copy-mode-vi r)" == *refresh-now* ]] || fail 'r should retain one-shot refresh'
  for hook in pane-created pane-moved pane-died; do
    [[ "$(feature_tmux show-hooks -g "$hook")" == *taw-agent-status*sync* ]] || fail "missing reconciliation hook: $hook"
  done
  [[ "$(feature_tmux show-options -gv @pane_status)" == *'range=pane|#{pane_id}'* ]] || fail 'pane entries should be clickable'
}

test_feature_failed_pane_lifecycle() {
  local live failed successful address window i
  command -v tmux >/dev/null 2>&1 || return 0
  setup_feature_server
  start_tmux_test_client "$FEATURE_SOCKET" features 120,40
  trap 'feature_tmux kill-server >/dev/null 2>&1 || true; stop_tmux_test_client' EXIT
  live="$(feature_tmux display-message -p '#{pane_id}')"
  failed="$(feature_tmux split-window -d -P -F '#{pane_id}' -t "$live" 'exit 7')"
  for ((i = 0; i < 100; i++)); do
    [[ "$(feature_tmux display-message -p -t "$failed" '#{pane_dead}')" != 1 ]] || break
    sleep 0.02
  done
  assert_eq 1 "$(feature_tmux display-message -p -t "$failed" '#{pane_dead}')"
  assert_eq 7 "$(feature_tmux display-message -p -t "$failed" '#{pane_dead_status}')"
  feature_tmux set-option -p -t "$failed" @taw_agent codex
  feature_tmux set-option -p -t "$failed" @taw_agent_state waiting
  assert_eq '' "$(feature_tmux display-message -p -t "$failed" '#{E:@taw_pane_agent_icon}')"
  assert_eq '' "$(feature_tmux display-message -p -t "$live" '#{E:@taw_window_agent_icon}')"
  [[ "$(feature_tmux display-message -p -t "$failed" '#{E:@pane_status_agent}')" == *'[exit 7]'* ]] || fail 'failed pane should show its exit status'
  address="$(feature_tmux display-message -p '#{socket_path},#{pid},0')"
  TMUX="$address" "$REPO_ROOT/home/.zfuns/taw-agent-status" acknowledge "$failed"
  assert_eq waiting "$(feature_tmux show-options -pqv -t "$failed" @taw_agent_state)" 'dead panes must not acknowledge prompts'
  TMUX="$address" "$REPO_ROOT/home/.zfuns/taw-agent-status" start codex "$failed"
  TMUX="$address" "$REPO_ROOT/home/.zfuns/taw-agent-status" clear "$failed"
  feature_tmux has-session -t agents || fail 'retained failures should preserve their managed view'
  window="$(feature_tmux display-message -p -t "$failed" '#{window_id}')"
  TMUX="$address" "$REPO_ROOT/home/.zfuns/taw-agent-status" unlink "$window"
  if feature_tmux has-session -t agents 2>/dev/null; then fail 'explicit unlink should close the retained view'; fi
  assert_eq 1 "$(feature_tmux display-message -p -t "$failed" '#{pane_dead}')" 'unlink must preserve the source failure'
  TMUX="$address" "$REPO_ROOT/home/.zfuns/taw-agent-status" start codex "$failed"
  TMUX="$address" "$REPO_ROOT/home/.zfuns/taw-agent-status" clear "$failed"
  feature_tmux select-pane -t "$failed"
  feature_tmux send-keys -K -c "$TEST_TMUX_CLIENT_NAME" Space
  for ((i = 0; i < 100; i++)); do
    if ! feature_tmux list-panes -F '#{pane_id}' | rg -Fx "$failed" >/dev/null; then break; fi
    sleep 0.02
  done
  if feature_tmux list-panes -F '#{pane_id}' | rg -Fx "$failed" >/dev/null; then
    fail 'a key should dismiss the failed pane'
  fi
  TMUX="$address" "$REPO_ROOT/home/.zfuns/taw-agent-status" sync
  if feature_tmux has-session -t agents 2>/dev/null; then fail 'dismissed failure should remove its managed view'; fi
  successful="$(feature_tmux split-window -d -P -F '#{pane_id}' -t "$live" 'sleep 0.1; exit 0')"
  for ((i = 0; i < 100; i++)); do
    if ! feature_tmux list-panes -F '#{pane_id}' | rg -Fx "$successful" >/dev/null; then break; fi
    sleep 0.02
  done
  if feature_tmux list-panes -F '#{pane_id}' | rg -Fx "$successful" >/dev/null; then
    fail 'successful commands should close normally'
  fi
  feature_tmux copy-mode -t "$live"
  feature_tmux send-keys -K -c "$TEST_TMUX_CLIENT_NAME" R
  assert_eq 1 "$(feature_tmux display-message -p -t "$live" '#{refresh_active}')" 'R should enable automatic copy refresh'
  feature_tmux send-keys -K -c "$TEST_TMUX_CLIENT_NAME" R
  assert_eq 0 "$(feature_tmux display-message -p -t "$live" '#{refresh_active}')" 'R should disable automatic copy refresh'
}

test_case 'tmux features: reload preserves hooks and selected defaults' test_feature_reload_and_options
test_case 'tmux features: failed panes remain visible and ignore agent priority' test_feature_failed_pane_lifecycle
