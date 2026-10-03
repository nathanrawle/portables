TMUX_LAYOUT_SOCKET=

layout_tmux() {
  tmux -L "$TMUX_LAYOUT_SOCKET" "$@"
}

setup_layout_server() {
  export HOME="$TEST_TMPDIR/home"
  mkdir -p "$HOME/.zfuns" "$HOME/.config/tmux"
  ln -s "$REPO_ROOT/home/.config/tmux/reshape-pane" "$HOME/.config/tmux/reshape-pane"
  printf '#!/bin/sh\nexit 0\n' >"$HOME/.zfuns/taw-agent-status"
  chmod +x "$HOME/.zfuns/taw-agent-status"
  TMUX_LAYOUT_SOCKET="portables-layout-$$-$RANDOM"
  trap 'layout_tmux kill-server >/dev/null 2>&1 || true' EXIT
  layout_tmux -f "$REPO_ROOT/home/.config/tmux/tmux.conf" \
    new-session -d -s layout -x 180 -y 60 'sleep 120'
}

create_layout_quadrants() {
  local window="$1" first second third first_axis=-h second_axis=-v
  if [[ "${2:-columns}" == rows ]]; then
    first_axis=-v
    second_axis=-h
  fi
  first="$(layout_tmux new-window -d -P -F '#{pane_id}' -n "$window" 'sleep 120')"
  second="$(layout_tmux split-window -d "$first_axis" -P -F '#{pane_id}' -t "$first" 'sleep 120')"
  third="$(layout_tmux split-window -d "$second_axis" -P -F '#{pane_id}' -t "$first" 'sleep 120')"
  LAYOUT_MOVED="$(layout_tmux split-window -d "$second_axis" -P -F '#{pane_id}' -t "$second" 'sleep 120')"
  LAYOUT_FIRST="$first"
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

test_layout_directional_middle_columns_and_rows() {
  local direction shape moved before span position size total
  command -v tmux >/dev/null 2>&1 || return 0
  setup_layout_server
  for shape in columns rows; do
    for direction in left right up down; do
      create_layout_quadrants "middle-$shape-$direction" "$shape"
      case "$direction" in
        left|up) moved="$LAYOUT_MOVED" ;;
        right|down) moved="$LAYOUT_FIRST" ;;
      esac
      before="$(layout_tmux list-panes -t "$moved" -F '#{pane_id}:#{pane_pid}' | sort)"
      run_layout_binding "S-$direction" "$moved"
      if [[ "$direction" == left || "$direction" == right ]]; then
        read -r position size total span < <(layout_tmux display-message -p -t "$moved" \
          '#{pane_left} #{pane_width} #{window_width} #{==:#{pane_height},#{window_height}}')
      else
        read -r position size total span < <(layout_tmux display-message -p -t "$moved" \
          '#{pane_top} #{pane_height} #{window_height} #{==:#{pane_width},#{window_width}}')
      fi
      assert_eq 1 "$span" 'expected full-span pane'
      (( position > 0 && position + size < total )) || fail 'expected middle position'
      (( size >= total / 3 - 1 && size <= total / 3 + 1 )) || fail 'expected one-third size'
      assert_eq 1 "$(layout_tmux display-message -p -t "$moved" '#{pane_active}')"
      assert_eq "$before" "$(layout_tmux list-panes -t "$moved" -F '#{pane_id}:#{pane_pid}' | sort)"
    done
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
  assert_eq 1 "$(layout_tmux display-message -p -t "$moved" '#{==:#{pane_height},#{window_height}}')"
  assert_eq 1 "$(layout_tmux display-message -p -t "$moved" '#{pane_active}')"
  assert_eq 0 "$(layout_tmux display-message -p -t "$moved" '#{window_zoomed_flag}')"
  assert_eq "$before" "$(layout_tmux display-message -p -t "$marked" '#{window_layout}:#{pane_pid}')" \
    'expected marked pane in another window to stay untouched'
}

test_layout_three_pane_middle_column() {
  local left upper moved width peer_width pane
  command -v tmux >/dev/null 2>&1 || return 0
  setup_layout_server
  left="$(layout_tmux display-message -p -t layout:1 '#{pane_id}')"
  upper="$(layout_tmux split-window -dh -P -F '#{pane_id}' -t "$left" 'sleep 120')"
  moved="$(layout_tmux split-window -dv -P -F '#{pane_id}' -t "$upper" 'sleep 120')"
  run_layout_binding S-left "$moved"
  width="$(layout_tmux display-message -p -t "$moved" '#{pane_width}')"
  for pane in "$left" "$upper" "$moved"; do
    assert_eq 1 "$(layout_tmux display-message -p -t "$pane" '#{==:#{pane_height},#{window_height}}')"
    peer_width="$(layout_tmux display-message -p -t "$pane" '#{pane_width}')"
    (( peer_width >= width - 1 && peer_width <= width + 1 )) || fail 'expected equal column widths within rounding'
  done
  assert_eq 1 "$(layout_tmux display-message -p -t "$moved" '#{&&:#{>:#{pane_left},0},#{!:#{pane_at_right}}}')"
}

test_layout_full_span_pane_moves_to_edge() {
  local left moved before
  command -v tmux >/dev/null 2>&1 || return 0
  setup_layout_server
  left="$(layout_tmux display-message -p -t layout:1 '#{pane_id}')"
  moved="$(layout_tmux split-window -dh -P -F '#{pane_id}' -t "$left" 'sleep 120')"
  before="$(layout_tmux list-panes -t "$moved" -F '#{pane_id}:#{pane_pid}' | sort)"
  run_layout_binding S-left "$moved"
  assert_eq 1 "$(layout_tmux display-message -p -t "$moved" '#{pane_at_left}')"
  assert_eq 1 "$(layout_tmux display-message -p -t "$moved" '#{==:#{pane_height},#{window_height}}')"
  assert_eq "$before" "$(layout_tmux list-panes -t "$moved" -F '#{pane_id}:#{pane_pid}' | sort)"
}

test_case 'tmux layout: directional moves create equal middle columns and rows' test_layout_directional_middle_columns_and_rows
test_case 'tmux layout: single pane is unchanged' test_layout_single_pane_is_unchanged
test_case 'tmux layout: zoom and marked pane stay correctly scoped' test_layout_zoom_and_marked_pane
test_case 'tmux layout: three panes become equal full-height columns' test_layout_three_pane_middle_column
test_case 'tmux layout: full-span panes fall back to edge movement' test_layout_full_span_pane_moves_to_edge
