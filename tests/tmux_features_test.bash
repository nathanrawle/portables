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

feature_key() {
  local table="$1" key="$2"
  feature_tmux switch-client -c "$TEST_TMUX_CLIENT_NAME" -T "$table"
  # tmux's CLI treats a bare semicolon as a command separator even inside shell quotes.
  [[ "$key" != ';' ]] || key='\;'
  feature_tmux send-keys -K -c "$TEST_TMUX_CLIENT_NAME" "$key"
}

test_feature_picker_bindings() {
  local pane original table key expected exit_key
  command -v tmux >/dev/null 2>&1 || return 0
  setup_feature_server
  start_tmux_test_client "$FEATURE_SOCKET" features 120,40
  trap 'feature_tmux kill-server >/dev/null 2>&1 || true; stop_tmux_test_client' EXIT
  pane="$(feature_tmux display-message -p '#{pane_id}')"
  original="$pane"
  feature_tmux set-buffer 'picker fixture'
  while read -r table key expected; do
    feature_key "$table" "$key" >"$TEST_TMPDIR/key-output"
    pane="$(feature_tmux display-message -p '#{pane_id}')"
    # Control clients receive list output directly instead of opening a view in the pane.
    if [[ "$expected" == key-list ]]; then
      [[ "$(cat "$TEST_TMPDIR/key-output")" == *'List key bindings'* ]] || fail 'keymap sheet must list bindings'
      assert_eq '' "$(feature_tmux display-message -p -t "$pane" '#{pane_mode}')"
      continue
    fi
    assert_eq "$expected" "$(feature_tmux display-message -p -t "$pane" '#{pane_mode}')" \
      "$table $key must open its picker through client key dispatch"
    exit_key=q
    [[ "$expected" != switch-mode ]] || exit_key=Escape
    feature_tmux send-keys -K -c "$TEST_TMUX_CLIENT_NAME" "$exit_key"
    assert_eq "$original" "$(feature_tmux display-message -p '#{pane_id}')" "$key must return to the source pane"
    assert_eq '' "$(feature_tmux display-message -p -t "$original" '#{pane_mode}')" "$key must exit cleanly"
  done <<'KEYS'
root C-Enter tree-mode
prefix s tree-mode
prefix w tree-mode
prefix = buffer-mode
prefix D client-mode
prefix C options-mode
prefix ? key-list
prefix Tab switch-mode
prefix BTab switch-mode
KEYS
}

test_feature_navigation_and_split_bindings() {
  local first second pane key before path window
  command -v tmux >/dev/null 2>&1 || return 0
  setup_feature_server
  start_tmux_test_client "$FEATURE_SOCKET" features 120,40
  trap 'feature_tmux kill-server >/dev/null 2>&1 || true; stop_tmux_test_client' EXIT
  feature_tmux set-option default-command 'sleep 120'
  first="$(feature_tmux display-message -p '#{window_id}')"
  second="$(feature_tmux new-window -P -F '#{window_id}')"
  feature_key root C-M-left
  assert_eq "$first" "$(feature_tmux display-message -p '#{window_id}')"
  feature_key root C-M-right
  assert_eq "$second" "$(feature_tmux display-message -p '#{window_id}')"
  feature_key root C-M-h
  assert_eq "$first" "$(feature_tmux display-message -p '#{window_id}')"
  feature_key root C-M-o
  assert_eq "$second" "$(feature_tmux display-message -p '#{window_id}')"
  feature_key root C-M-j
  assert_eq "$first" "$(feature_tmux display-message -p '#{window_id}')"
  feature_key root C-M-k
  assert_eq "$second" "$(feature_tmux display-message -p '#{window_id}')"

  while IFS= read -r key; do
    pane="$(feature_tmux new-window -P -F '#{pane_id}')"
    path="$(feature_tmux display-message -p -t "$pane" '#{pane_current_path}')"
    feature_key prefix "$key"
    assert_eq 2 "$(feature_tmux display-message -p '#{window_panes}')" "prefix $key must split"
    assert_eq "$path" "$(feature_tmux display-message -p '#{pane_current_path}')" "$key must retain the directory"
  done <<'KEYS'
'
"
-
_
;
:
|
\
KEYS
  before="$(feature_tmux list-panes -F '#{pane_id}:#{pane_pid}' | sort)"
  feature_key root C-j
  assert_eq 1 "$(feature_tmux display-message -p '#{pane_index}')"
  feature_key root C-k
  assert_eq 2 "$(feature_tmux display-message -p '#{pane_index}')"
  feature_key root C-h
  assert_eq 1 "$(feature_tmux display-message -p '#{pane_index}')"
  feature_key root C-right
  assert_eq 2 "$(feature_tmux display-message -p '#{pane_index}')"
  feature_key root C-left
  assert_eq 1 "$(feature_tmux display-message -p '#{pane_index}')"
  pane="$(feature_tmux display-message -p '#{pane_id}')"
  feature_key root C-S-right
  assert_eq "$pane" "$(feature_tmux display-message -p '#{pane_id}')"
  assert_eq 2 "$(feature_tmux display-message -p '#{pane_index}')"
  assert_eq "$before" "$(feature_tmux list-panes -F '#{pane_id}:#{pane_pid}' | sort)" 'swapping must preserve processes'
}

test_case 'tmux features: native picker bindings execute through client keys' test_feature_picker_bindings
test_case 'tmux features: navigation and split bindings preserve targets and processes' test_feature_navigation_and_split_bindings

test_feature_prefix_resize_bindings() {
  local pane floating size key direction amount before
  command -v tmux >/dev/null 2>&1 || return 0
  setup_feature_server
  start_tmux_test_client "$FEATURE_SOCKET" features 120,40
  trap 'feature_tmux kill-server >/dev/null 2>&1 || true; stop_tmux_test_client' EXIT
  feature_tmux set-option default-command 'sleep 120'
  while read -r key direction amount; do
    pane="$(feature_tmux new-window -P -F '#{pane_id}')"
    if [[ "$direction" == width ]]; then
      pane="$(feature_tmux split-window -h -P -F '#{pane_id}' -t "$pane")"
    else
      pane="$(feature_tmux split-window -P -F '#{pane_id}' -t "$pane")"
    fi
    size="$(feature_tmux display-message -p -t "$pane" "#{pane_$direction}")"
    feature_key prefix "$key"
    assert_eq "$((size + amount))" "$(feature_tmux display-message -p -t "$pane" "#{pane_$direction}")" \
      "prefix $key must expand a tiled pane toward its neighbor"
    floating="$(feature_tmux new-pane -A -B single -x 40 -y 20 -X 15 -Y 5 -P -F '#{pane_id}')"
    before="$(feature_tmux list-panes -F '#{?pane_floating_flag,,#{pane_id}:#{pane_width}:#{pane_height}}')"
    size="$(feature_tmux display-message -p -t "$floating" "#{pane_$direction}")"
    feature_key prefix "$key"
    assert_eq "$((size - amount))" "$(feature_tmux display-message -p -t "$floating" "#{pane_$direction}")" \
      "prefix $key must shrink a floating pane"
    assert_eq "$before" "$(feature_tmux list-panes -F '#{?pane_floating_flag,,#{pane_id}:#{pane_width}:#{pane_height}}')" \
      'floating resizing must preserve tiled panes'
  done <<'KEYS'
M-Up height 5
M-Left width 5
C-Up height 1
C-Left width 1
KEYS
}

test_case 'tmux features: prefix resizing distinguishes floating and tiled panes' test_feature_prefix_resize_bindings
