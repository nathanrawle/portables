TMUX_AGENT_STATUS_CONFIG="$REPO_ROOT/home/.config/tmux/tmux.conf"
TMUX_AGENT_STATUS_BIN=
TMUX_AGENT_STATUS_SOCKET=

cleanup_tmux_agent_status_server() {
  if [[ -n "$TMUX_AGENT_STATUS_BIN" && -n "$TMUX_AGENT_STATUS_SOCKET" ]]; then
    "$TMUX_AGENT_STATUS_BIN" -L "$TMUX_AGENT_STATUS_SOCKET" kill-server \
      >/dev/null 2>&1 || true
  fi
}

assert_tmux_status_contains() {
  local actual="$1"
  local expected="$2"
  local message="$3"

  [[ "$actual" == *"$expected"* ]] || fail "$message: missing [$expected] in [$actual]"
}

assert_tmux_status_not_contains() {
  local actual="$1"
  local unexpected="$2"
  local message="$3"

  [[ "$actual" != *"$unexpected"* ]] || fail "$message: found [$unexpected] in [$actual]"
}

set_tmux_agent_status() {
  local pane="$1"
  local agent="$2"
  local state="$3"

  "$TMUX_AGENT_STATUS_BIN" -L "$TMUX_AGENT_STATUS_SOCKET" \
    set-option -p -t "$pane" @taw_agent "$agent"
  "$TMUX_AGENT_STATUS_BIN" -L "$TMUX_AGENT_STATUS_SOCKET" \
    set-option -p -t "$pane" @taw_agent_state "$state"
}

clear_tmux_agent_status() {
  local pane="$1"

  "$TMUX_AGENT_STATUS_BIN" -L "$TMUX_AGENT_STATUS_SOCKET" \
    set-option -pu -t "$pane" @taw_agent_state >/dev/null 2>&1 || true
  "$TMUX_AGENT_STATUS_BIN" -L "$TMUX_AGENT_STATUS_SOCKET" \
    set-option -pu -t "$pane" @taw_agent >/dev/null 2>&1 || true
}

render_tmux_agent_icon() {
  local target="$1"
  local option="$2"

  "$TMUX_AGENT_STATUS_BIN" -L "$TMUX_AGENT_STATUS_SOCKET" \
    display-message -p -t "$target" "#{E:$option}"
}

test_tmux_status_formats_show_agent_state_and_priority() {
  local first second third fourth state expected actual pane pane_tabs window_tab i
  local inactive_window_tab
  local -a panes states icons

  TMUX_AGENT_STATUS_BIN="$(command -v tmux || true)"
  [[ -n "$TMUX_AGENT_STATUS_BIN" ]] || return 0
  TMUX_AGENT_STATUS_SOCKET="portables-agent-status-$$-$RANDOM"
  trap cleanup_tmux_agent_status_server EXIT

  first="$(
    "$TMUX_AGENT_STATUS_BIN" -L "$TMUX_AGENT_STATUS_SOCKET" \
      -f "$TMUX_AGENT_STATUS_CONFIG" new-session -d -P -F '#{pane_id}' \
      -s agent-status -n agents 'sleep 120'
  )"
  second="$(
    "$TMUX_AGENT_STATUS_BIN" -L "$TMUX_AGENT_STATUS_SOCKET" split-window \
      -d -P -F '#{pane_id}' -t agent-status:agents 'sleep 120'
  )"
  third="$(
    "$TMUX_AGENT_STATUS_BIN" -L "$TMUX_AGENT_STATUS_SOCKET" split-window \
      -d -P -F '#{pane_id}' -t agent-status:agents 'sleep 120'
  )"
  fourth="$(
    "$TMUX_AGENT_STATUS_BIN" -L "$TMUX_AGENT_STATUS_SOCKET" split-window \
      -d -P -F '#{pane_id}' -t agent-status:agents 'sleep 120'
  )"

  states=(idle thinking acknowledged waiting)
  icons=('󰚩' '󰔟' '…' '󰹇')
  for ((i = 0; i < ${#states[@]}; i++)); do
    state="${states[$i]}"
    expected="${icons[$i]}"
    set_tmux_agent_status "$first" codex "$state"
    actual="$(render_tmux_agent_icon "$first" @taw_pane_agent_icon)"
    assert_eq "$expected" "$actual" "unexpected pane icon for $state"
  done

  set_tmux_agent_status "$first" gemini waiting
  actual="$(render_tmux_agent_icon "$first" @taw_pane_agent_icon)"
  assert_eq "" "$actual" "expected an unsupported agent to have no icon"

  panes=("$first" "$second" "$third" "$fourth")
  for ((i = 0; i < ${#panes[@]}; i++)); do
    set_tmux_agent_status "${panes[$i]}" codex "${states[$i]}"
  done
  actual="$(render_tmux_agent_icon agent-status:agents @taw_window_agent_icon)"
  assert_eq '󰹇' "$actual" "expected waiting to have window priority"

  set_tmux_agent_status "$fourth" codex thinking
  actual="$(render_tmux_agent_icon agent-status:agents @taw_window_agent_icon)"
  assert_eq '…' "$actual" "expected acknowledged to have window priority"

  set_tmux_agent_status "$third" codex idle
  actual="$(render_tmux_agent_icon agent-status:agents @taw_window_agent_icon)"
  assert_eq '󰔟' "$actual" "expected thinking to have window priority"

  set_tmux_agent_status "$second" codex idle
  set_tmux_agent_status "$fourth" codex idle
  actual="$(render_tmux_agent_icon agent-status:agents @taw_window_agent_icon)"
  assert_eq '󰚩' "$actual" "expected idle when no higher-priority state remains"

  for pane in "${panes[@]}"; do
    clear_tmux_agent_status "$pane"
  done
  actual="$(render_tmux_agent_icon agent-status:agents @taw_window_agent_icon)"
  assert_eq "" "$actual" "expected a window without agent state to have no icon"

  window_tab="$(
    "$TMUX_AGENT_STATUS_BIN" -L "$TMUX_AGENT_STATUS_SOCKET" display-message \
      -p -t agent-status:agents '#{E:window-status-current-format}'
  )"
  assert_tmux_status_contains "$window_tab" '*' \
    "expected tmux flags when the window has no agent state"
  inactive_window_tab="$(
    "$TMUX_AGENT_STATUS_BIN" -L "$TMUX_AGENT_STATUS_SOCKET" display-message \
      -p -t agent-status:agents '#{E:window-status-format}'
  )"
  assert_tmux_status_contains "$inactive_window_tab" '*' \
    "expected inactive-format tmux flags when the window has no agent state"

  set_tmux_agent_status "$first" claude waiting
  window_tab="$(
    "$TMUX_AGENT_STATUS_BIN" -L "$TMUX_AGENT_STATUS_SOCKET" display-message \
      -p -t agent-status:agents '#{E:window-status-current-format}'
  )"
  assert_tmux_status_contains "$window_tab" '󰹇' \
    "expected the window icon in the flag slot"
  assert_tmux_status_not_contains "$window_tab" '*' \
    "expected the window icon to replace tmux flags"
  inactive_window_tab="$(
    "$TMUX_AGENT_STATUS_BIN" -L "$TMUX_AGENT_STATUS_SOCKET" display-message \
      -p -t agent-status:agents '#{E:window-status-format}'
  )"
  assert_tmux_status_contains "$inactive_window_tab" '󰹇' \
    "expected the inactive-format icon in the flag slot"
  assert_tmux_status_not_contains "$inactive_window_tab" '*' \
    "expected the inactive-format icon to replace tmux flags"

  set_tmux_agent_status "$second" codex thinking
  pane_tabs="$(
    "$TMUX_AGENT_STATUS_BIN" -L "$TMUX_AGENT_STATUS_SOCKET" display-message \
      -p -t agent-status:agents '#{E:status-format[1]}'
  )"
  assert_tmux_status_contains "$pane_tabs" '"sleep 120" 󰹇' \
    "expected the active pane icon after its title"
  assert_tmux_status_contains "$pane_tabs" '"sleep 120" 󰔟' \
    "expected the inactive pane icon after its title"
}

test_case "tmux agent status: formats show pane state and window priority" \
  test_tmux_status_formats_show_agent_state_and_priority
