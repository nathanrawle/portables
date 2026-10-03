TMUX_LAYOUT_SOCKET=

layout_tmux() {
  tmux -L "$TMUX_LAYOUT_SOCKET" "$@"
}

setup_layout_server() {
  export HOME="$TEST_TMPDIR/home"
  mkdir -p "$HOME/.zfuns"
  printf '#!/bin/sh\nexit 0\n' >"$HOME/.zfuns/taw-agent-status"
  chmod +x "$HOME/.zfuns/taw-agent-status"
  TMUX_LAYOUT_SOCKET="portables-layout-$$-$RANDOM"
  trap 'layout_tmux kill-server >/dev/null 2>&1 || true' EXIT
  layout_tmux -f "$REPO_ROOT/home/.config/tmux/tmux.conf" \
    new-session -d -s layout -x 180 -y 60 'sleep 120'
}

create_layout_quadrants() {
  local window="$1" first second third
  first="$(layout_tmux new-window -d -P -F '#{pane_id}' -n "$window" 'sleep 120')"
  second="$(layout_tmux split-window -dh -P -F '#{pane_id}' -t "$first" 'sleep 120')"
  third="$(layout_tmux split-window -dv -P -F '#{pane_id}' -t "$first" 'sleep 120')"
  LAYOUT_MOVED="$(layout_tmux split-window -dv -P -F '#{pane_id}' -t "$second" 'sleep 120')"
  layout_tmux resize-pane -t "$third" -y 17
  layout_tmux resize-pane -t "$LAYOUT_MOVED" -y 21
  layout_tmux select-window -t "$LAYOUT_MOVED"
  layout_tmux select-pane -t "$LAYOUT_MOVED"
}

run_layout_binding() {
  local key="$1" pane="$2"
  layout_tmux select-window -t "$pane"
  layout_tmux select-pane -t "$pane"
  # Execute the loaded binding body with the same pane context as a key press.
  layout_tmux list-keys -T prefix "$key" | \
    sed -E 's/^bind-key[[:space:]]+-T[[:space:]]+prefix[[:space:]]+[^[:space:]]+[[:space:]]+//' \
    >"$TEST_TMPDIR/binding.conf"
  layout_tmux source-file -t "$pane" "$TEST_TMPDIR/binding.conf"
}

layout_geometry() {
  layout_tmux list-panes -t "$1" -F '#{pane_left},#{pane_top},#{pane_width},#{pane_height}' | sort
}

assert_layout_edge() {
  local pane="$1" direction="$2" actual
  case "$direction" in
    left) actual="$(layout_tmux display-message -p -t "$pane" '#{pane_at_left}:#{pane_at_top}:#{pane_at_bottom}')" ;;
    right) actual="$(layout_tmux display-message -p -t "$pane" '#{pane_at_right}:#{pane_at_top}:#{pane_at_bottom}')" ;;
    up) actual="$(layout_tmux display-message -p -t "$pane" '#{pane_at_top}:#{pane_at_left}:#{pane_at_right}')" ;;
    down) actual="$(layout_tmux display-message -p -t "$pane" '#{pane_at_bottom}:#{pane_at_left}:#{pane_at_right}')" ;;
  esac
  assert_eq '1:1:1' "$actual" "expected full-span $direction edge"
  assert_eq 1 "$(layout_tmux display-message -p -t "$pane" '#{pane_active}')" \
    'expected moved pane to remain active'
}

test_layout_edges_match_native_equalisation() {
  local direction flags before expected actual reference
  command -v tmux >/dev/null 2>&1 || return 0
  setup_layout_server
  for direction in left right up down; do
    create_layout_quadrants "actual-$direction"
    actual="$LAYOUT_MOVED"
    before="$(layout_tmux list-panes -t "$actual" -F '#{pane_id}:#{pane_pid}' | sort)"
    create_layout_quadrants "reference-$direction"
    reference="$LAYOUT_MOVED"
    case "$direction" in
      left) flags=-bhf ;;
      right) flags=-hf ;;
      up) flags=-bvf ;;
      down) flags=-vf ;;
    esac
    layout_tmux move-pane "$flags" -s "$reference" -t ':.+'
    layout_tmux select-layout -E -t "$reference"
    layout_tmux select-layout -E -t "$reference"
    expected="$(layout_geometry "$reference")"
    run_layout_binding "S-$direction" "$actual"
    assert_layout_edge "$actual" "$direction"
    assert_eq "$before" "$(layout_tmux list-panes -t "$actual" -F '#{pane_id}:#{pane_pid}' | sort)" \
      'expected pane identities and processes to survive'
    assert_eq "$expected" "$(layout_geometry "$actual")" \
      'expected geometry equivalent to two E presses'
  done
}

test_layout_single_pane_is_unchanged() {
  local direction before pane
  command -v tmux >/dev/null 2>&1 || return 0
  setup_layout_server
  pane="$(layout_tmux display-message -p -t layout:1 '#{pane_id}')"
  before="$(layout_tmux display-message -p -t "$pane" '#{window_layout}:#{pane_pid}')"
  for direction in left right up down; do
    run_layout_binding "S-$direction" "$pane"
    assert_eq "$before" "$(layout_tmux display-message -p -t "$pane" '#{window_layout}:#{pane_pid}')"
  done
}

test_layout_zoom_and_marked_pane() {
  local marked before moved
  command -v tmux >/dev/null 2>&1 || return 0
  setup_layout_server
  marked="$(layout_tmux display-message -p -t layout:1 '#{pane_id}')"
  before="$(layout_tmux display-message -p -t "$marked" '#{window_layout}:#{pane_pid}')"
  layout_tmux select-pane -m -t "$marked"
  create_layout_quadrants zoomed
  moved="$LAYOUT_MOVED"
  layout_tmux resize-pane -Z -t "$moved"
  run_layout_binding S-left "$moved"
  assert_layout_edge "$moved" left
  assert_eq 0 "$(layout_tmux display-message -p -t "$moved" '#{window_zoomed_flag}')"
  assert_eq "$before" "$(layout_tmux display-message -p -t "$marked" '#{window_layout}:#{pane_pid}')" \
    'expected marked pane in another window to stay untouched'
}

test_layout_middle_column_sequence() {
  local middle right left width height window_height
  command -v tmux >/dev/null 2>&1 || return 0
  setup_layout_server
  create_layout_quadrants middle
  middle="$LAYOUT_MOVED"
  right="$(layout_tmux list-panes -t "$middle" -F '#{pane_id}' | sed -n '2p')"
  run_layout_binding S-right "$middle"
  run_layout_binding S-right "$right"
  left="$(layout_tmux display-message -p -t "$middle" '#{pane_left}')"
  width="$(layout_tmux display-message -p -t "$middle" '#{pane_width}')"
  height="$(layout_tmux display-message -p -t "$middle" '#{pane_height}')"
  window_height="$(layout_tmux display-message -p -t "$middle" '#{window_height}')"
  [[ "$left" -gt 0 ]] || fail 'expected middle column to have space on its left'
  assert_eq "$window_height" "$height" 'expected full-height middle column'
  assert_eq "$width" "$(layout_tmux display-message -p -t "$right" '#{pane_width}')" \
    'expected equal middle and right column widths'
}

test_case 'tmux layout: edge moves match two native E presses' test_layout_edges_match_native_equalisation
test_case 'tmux layout: single pane is unchanged' test_layout_single_pane_is_unchanged
test_case 'tmux layout: zoom and marked pane stay correctly scoped' test_layout_zoom_and_marked_pane
test_case 'tmux layout: successive edge moves create a middle column' test_layout_middle_column_sequence
