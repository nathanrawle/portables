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

run_layout_binding() {
  local key="$1" pane="$2"
  layout_tmux select-window -t "$pane"
  layout_tmux select-pane -t "$pane"
  # Execute the loaded binding body with the same pane context as a key press.
  layout_tmux list-keys -T root "$key" | \
    sed -E 's/^bind-key[[:space:]]+-T[[:space:]]+root[[:space:]]+[^[:space:]]+[[:space:]]+//' \
    >"$TEST_TMPDIR/binding.conf"
  layout_tmux source-file -t "$pane" "$TEST_TMPDIR/binding.conf"
}

create_transition_layout() {
  local axis="$1" name="$2" across=-h within=-v
  if [[ "$axis" == vertical ]]; then across=-v; within=-h; fi
  ONE="$(layout_tmux new-window -d -P -F '#{pane_id}' -n "$name" 'sleep 120')"
  TWO="$(layout_tmux split-window -d "$across" -P -F '#{pane_id}' -t "$ONE" 'sleep 120')"
  THREE="$(layout_tmux split-window -d "$within" -P -F '#{pane_id}' -t "$TWO" 'sleep 120')"
  FOUR="$(layout_tmux split-window -d "$across" -f -P -F '#{pane_id}' -t "$ONE" 'sleep 120')"
  layout_tmux select-layout -E -t "$FOUR"
  layout_tmux select-layout -E -t "$FOUR"
}

assert_transition_layout() {
  local expected="$1" axis="$2" actual width height
  read -r width height < <(layout_tmux display-message -p -t "$FOUR" '#{window_width} #{window_height}')
  actual="$(layout_tmux list-panes -t "$FOUR" \
    -F '#{pane_id} #{pane_left} #{pane_top} #{pane_width} #{pane_height}' | \
    awk -v expected="$expected" -v axis="$axis" -v width="$width" -v height="$height" \
      -v one="$ONE" -v two="$TWO" -v three="$THREE" -v four="$FOUR" '
      { id[NR] = $1; x[NR] = $2; y[NR] = $3; w[NR] = $4; h[NR] = $5 }
      END {
        label[one] = 1; label[two] = 2; label[three] = 3; label[four] = 4
        columns = 0; row_count = 0
        for (i = 1; i <= NR; i++) {
          cx = axis == "horizontal" ? x[i] : y[i]
          cy = axis == "horizontal" ? y[i] : x[i]
          if (!(cx in seen_x)) { seen_x[cx] = 1; starts_x[++columns] = cx }
          if (!(cy in seen_y)) { seen_y[cy] = 1; starts_y[++row_count] = cy }
        }
        for (i = 1; i <= columns; i++) for (j = i + 1; j <= columns; j++)
          if (starts_x[i] > starts_x[j]) { temp = starts_x[i]; starts_x[i] = starts_x[j]; starts_x[j] = temp }
        for (i = 1; i <= row_count; i++) for (j = i + 1; j <= row_count; j++)
          if (starts_y[i] > starts_y[j]) { temp = starts_y[i]; starts_y[i] = starts_y[j]; starts_y[j] = temp }
        for (r = 1; r <= row_count; r++) {
          result = ""
          for (c = 1; c <= columns; c++) {
            if (axis == "horizontal") { px = starts_x[c] + 1; py = starts_y[r] + 1 }
            else { py = starts_x[c] + 1; px = starts_y[r] + 1 }
            found = "?"
            for (i = 1; i <= NR; i++)
              if (px >= x[i] && px < x[i] + w[i] && py >= y[i] && py < y[i] + h[i]) found = label[id[i]]
            result = result found
          }
          printf "%s%s", (r == 1 ? "" : "|"), result
        }
        print ""
      }')"
  assert_eq "$expected" "$actual" 'unexpected transition layout'
}

test_layout_entry_first_transition_sequences() {
  local axis forward backward index before layout
  local -a states reverse_states
  command -v tmux >/dev/null 2>&1 || return 0
  setup_layout_server
  reverse_states=('12|43' '142|143' '122|143' '12|13|14' '122|134' '124|134')
  states=('124|134' '122|134' '12|13|14' '122|143' '142|143' '12|43' '412|413')
  for axis in horizontal vertical; do
    create_transition_layout "$axis" "sequence-$axis"
    case "$axis" in horizontal) forward=S-left; backward=S-right ;; *) forward=S-up; backward=S-down ;; esac
    before="$(layout_tmux list-panes -t "$FOUR" -F '#{pane_id}:#{pane_pid}' | sort)"
    assert_transition_layout "${states[0]}" "$axis"
    for index in 1 2 3 4 5 6; do
      run_layout_binding "$forward" "$FOUR"
      assert_transition_layout "${states[$index]}" "$axis"
      assert_eq "$before" "$(layout_tmux list-panes -t "$FOUR" -F '#{pane_id}:#{pane_pid}' | sort)"
      assert_eq 1 "$(layout_tmux display-message -p -t "$FOUR" '#{pane_active}')"
    done
    layout="$(layout_tmux display-message -p -t "$FOUR" '#{window_layout}')"
    run_layout_binding "$forward" "$FOUR"
    assert_eq "$layout" "$(layout_tmux display-message -p -t "$FOUR" '#{window_layout}')" 'expected outer boundary no-op'
    layout_tmux resize-pane -Z -t "$FOUR"
    run_layout_binding "$forward" "$FOUR"
    assert_eq 1 "$(layout_tmux display-message -p -t "$FOUR" '#{window_zoomed_flag}')" 'expected a zoomed boundary no-op'
    layout_tmux resize-pane -Z -t "$FOUR"
    for index in 0 1 2 3 4 5; do
      run_layout_binding "$backward" "$FOUR"
      assert_transition_layout "${reverse_states[$index]}" "$axis"
    done
    layout="$(layout_tmux display-message -p -t "$FOUR" '#{window_layout}')"
    run_layout_binding "$backward" "$FOUR"
    assert_eq "$layout" "$(layout_tmux display-message -p -t "$FOUR" '#{window_layout}')" 'expected reverse outer boundary no-op'
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
  local marked before
  command -v tmux >/dev/null 2>&1 || return 0
  setup_layout_server
  marked="$(layout_tmux display-message -p -t layout:1 '#{pane_id}')"
  before="$(layout_tmux display-message -p -t "$marked" '#{window_layout}:#{pane_pid}')"
  layout_tmux select-pane -m -t "$marked"
  create_transition_layout horizontal zoomed
  layout_tmux resize-pane -Z -t "$FOUR"
  run_layout_binding S-left "$FOUR"
  assert_transition_layout '122|134' horizontal
  assert_eq 1 "$(layout_tmux display-message -p -t "$FOUR" '#{pane_active}')"
  assert_eq 0 "$(layout_tmux display-message -p -t "$FOUR" '#{window_zoomed_flag}')"
  assert_eq "$before" "$(layout_tmux display-message -p -t "$marked" '#{window_layout}:#{pane_pid}')"
}

test_layout_failure_restores_order_geometry_and_zoom() {
  local real_tmux before order zoom socket helper
  command -v tmux >/dev/null 2>&1 || return 0
  setup_layout_server
  create_transition_layout horizontal rollback
  layout_tmux select-pane -t "$FOUR"
  layout_tmux resize-pane -Z -t "$FOUR"
  before="$(layout_tmux display-message -p -t "$FOUR" '#{window_layout}')"
  order="$(layout_tmux list-panes -t "$FOUR" -F '#{pane_id}:#{pane_pid}')"
  socket="$(layout_tmux display-message -p -t "$FOUR" '#{socket_path}')"
  real_tmux="$(command -v tmux)"
  helper="$REPO_ROOT/home/.config/tmux/reshape-pane"
  mkdir -p "$TEST_TMPDIR/bin"
  cat >"$TEST_TMPDIR/bin/tmux" <<'WRAPPER'
#!/usr/bin/env bash
if [[ "$1" == select-layout && ! -e "$FAIL_MARKER" ]]; then
  touch "$FAIL_MARKER"
  exit 1
fi
exec "$REAL_TMUX" "$@"
WRAPPER
  chmod +x "$TEST_TMPDIR/bin/tmux"
  if TMUX="$socket,0,0" PATH="$TEST_TMPDIR/bin:$PATH" REAL_TMUX="$real_tmux" \
    FAIL_MARKER="$TEST_TMPDIR/failed" "$helper" "$FOUR" left; then
    fail 'expected the injected layout application failure'
  fi
  assert_eq "$before" "$(layout_tmux display-message -p -t "$FOUR" '#{window_layout}')"
  assert_eq "$order" "$(layout_tmux list-panes -t "$FOUR" -F '#{pane_id}:#{pane_pid}')"
  assert_eq 1 "$(layout_tmux display-message -p -t "$FOUR" '#{window_zoomed_flag}')"
  assert_eq 1 "$(layout_tmux display-message -p -t "$FOUR" '#{pane_active}')"
}

test_layout_equivalent_nested_containers() {
  local width height middle_width middle_x right_x body checksum code i fixture pane leaf
  local -a leaves
  leaves=()
  command -v tmux >/dev/null 2>&1 || return 0
  setup_layout_server
  create_transition_layout horizontal nested
  read -r width height < <(layout_tmux display-message -p -t "$FOUR" '#{window_width} #{window_height}')
  read -r middle_width middle_x < <(layout_tmux display-message -p -t "$TWO" '#{pane_width} #{pane_left}')
  right_x="$(layout_tmux display-message -p -t "$FOUR" '#{pane_left}')"
  i=0
  for pane in "$ONE" "$TWO" "$THREE" "$FOUR"; do
    leaf="$(layout_tmux display-message -p -t "$pane" '#{pane_width}x#{pane_height},#{pane_left},#{pane_top},#{pane_id}')"
    leaves[$i]="${leaf/,%/,}"
    i=$((i + 1))
  done
  body="${width}x${height},0,0{$((right_x - 1))x${height},0,0{${leaves[0]},${middle_width}x${height},${middle_x},0[${leaves[1]},${leaves[2]}]},${leaves[3]}}"
  checksum=0
  for ((i = 0; i < ${#body}; i++)); do
    printf -v code '%d' "'${body:i:1}"
    checksum=$(( ((checksum >> 1) + ((checksum & 1) << 15) + code) & 65535 ))
  done
  printf -v fixture '%04x,%s' "$checksum" "$body"
  layout_tmux select-layout -t "$FOUR" "$fixture"
  assert_transition_layout '124|134' horizontal
  run_layout_binding S-left "$FOUR"
  assert_transition_layout '122|134' horizontal
  run_layout_binding S-right "$FOUR"
  assert_transition_layout '124|134' horizontal
}

test_layout_three_pane_promotion_reverses() {
  command -v tmux >/dev/null 2>&1 || return 0
  setup_layout_server
  ONE="$(layout_tmux display-message -p -t layout:1 '#{pane_id}')"
  TWO="$(layout_tmux split-window -dh -P -F '#{pane_id}' -t "$ONE" 'sleep 120')"
  FOUR="$(layout_tmux split-window -dv -P -F '#{pane_id}' -t "$TWO" 'sleep 120')"
  THREE=unused
  assert_transition_layout '12|14' horizontal
  run_layout_binding S-left "$FOUR"
  assert_transition_layout '142' horizontal
  run_layout_binding S-right "$FOUR"
  assert_transition_layout '12|14' horizontal
}

test_layout_invalid_input_does_not_mutate_panes() {
  local before order socket real_tmux
  command -v tmux >/dev/null 2>&1 || return 0
  setup_layout_server
  create_transition_layout horizontal invalid
  before="$(layout_tmux display-message -p -t "$FOUR" '#{window_layout}')"
  order="$(layout_tmux list-panes -t "$FOUR" -F '#{pane_id}:#{pane_pid}')"
  socket="$(layout_tmux display-message -p -t "$FOUR" '#{socket_path}')"
  real_tmux="$(command -v tmux)"
  mkdir -p "$TEST_TMPDIR/bin"
  cat >"$TEST_TMPDIR/bin/tmux" <<'WRAPPER'
#!/usr/bin/env bash
if [[ "$1" == display-message && "$*" == *'#{window_layout}'* ]]; then
  printf '0000,invalid
'
  exit 0
fi
exec "$REAL_TMUX" "$@"
WRAPPER
  chmod +x "$TEST_TMPDIR/bin/tmux"
  if TMUX="$socket,0,0" PATH="$TEST_TMPDIR/bin:$PATH" REAL_TMUX="$real_tmux" \
    "$REPO_ROOT/home/.config/tmux/reshape-pane" "$FOUR" left \
    >"$TEST_TMPDIR/diagnostics" 2>&1; then
    fail 'expected malformed layout input to fail before applying changes'
  fi
  assert_eq "$before" "$(layout_tmux display-message -p -t "$FOUR" '#{window_layout}')"
  assert_eq "$order" "$(layout_tmux list-panes -t "$FOUR" -F '#{pane_id}:#{pane_pid}')"
}

test_layout_middle_sibling_enters_then_expands() {
  local axis across within forward backward state before
  local -a states
  command -v tmux >/dev/null 2>&1 || return 0
  setup_layout_server
  states=('123|144' '13|12|14' '123|144' '12|13|14')
  for axis in horizontal vertical; do
    case "$axis" in
      horizontal) across=-h; within=-v; forward=S-up; backward=S-down ;;
      vertical) across=-v; within=-h; forward=S-left; backward=S-right ;;
    esac
    ONE="$(layout_tmux new-window -d -P -F '#{pane_id}' -n "middle-$axis" 'sleep 120')"
    TWO="$(layout_tmux split-window -d "$across" -P -F '#{pane_id}' -t "$ONE" 'sleep 120')"
    THREE="$(layout_tmux split-window -d "$within" -P -F '#{pane_id}' -t "$TWO" 'sleep 120')"
    FOUR="$(layout_tmux split-window -d "$within" -P -F '#{pane_id}' -t "$THREE" 'sleep 120')"
    before="$(layout_tmux list-panes -t "$THREE" -F '#{pane_id}:#{pane_pid}' | sort)"
    assert_transition_layout '12|13|14' "$axis"
    for state in 0 1 2 3; do
      if [[ "$state" -lt 2 ]]; then run_layout_binding "$forward" "$THREE"
      else run_layout_binding "$backward" "$THREE"; fi
      assert_transition_layout "${states[$state]}" "$axis"
      assert_eq 1 "$(layout_tmux display-message -p -t "$THREE" '#{pane_active}')"
      assert_eq "$before" "$(layout_tmux list-panes -t "$THREE" -F '#{pane_id}:#{pane_pid}' | sort)"
    done
  done
}

test_layout_larger_groups_pair_locally() {
  local axis across within forward backward step before outer pane
  local -a states
  command -v tmux >/dev/null 2>&1 || return 0
  setup_layout_server
  states=('1243' '143|123' '1243' '123|143')
  for axis in horizontal vertical; do
    case "$axis" in
      horizontal) across=-h; within=-v; forward=S-up; backward=S-down ;;
      vertical) across=-v; within=-h; forward=S-left; backward=S-right ;;
    esac
    ONE="$(layout_tmux new-window -d -P -F '#{pane_id}' -n "local-$axis" 'sleep 120')"
    TWO="$(layout_tmux split-window -d "$across" -P -F '#{pane_id}' -t "$ONE" 'sleep 120')"
    FOUR="$(layout_tmux split-window -d "$within" -P -F '#{pane_id}' -t "$TWO" 'sleep 120')"
    THREE="$(layout_tmux split-window -d "$across" -f -P -F '#{pane_id}' -t "$ONE" 'sleep 120')"
    layout_tmux select-layout -E -t "$THREE"
    layout_tmux select-layout -E -t "$THREE"
    before="$(layout_tmux list-panes -t "$FOUR" -F '#{pane_id}:#{pane_pid}' | sort)"
    assert_transition_layout '123|143' "$axis"
    for step in 0 1 2 3; do
      if [[ "$step" -lt 2 ]]; then run_layout_binding "$forward" "$FOUR"
      else run_layout_binding "$backward" "$FOUR"; fi
      assert_transition_layout "${states[$step]}" "$axis"
      assert_eq 1 "$(layout_tmux display-message -p -t "$FOUR" '#{pane_active}')"
      assert_eq "$before" "$(layout_tmux list-panes -t "$FOUR" -F '#{pane_id}:#{pane_pid}' | sort)"
      for pane in "$ONE" "$THREE"; do
        if [[ "$axis" == horizontal ]]; then
          outer="$(layout_tmux display-message -p -t "$pane" '#{==:#{pane_height},#{window_height}}')"
        else
          outer="$(layout_tmux display-message -p -t "$pane" '#{==:#{pane_width},#{window_width}}')"
        fi
        assert_eq 1 "$outer" 'expected outer panes to retain their full span'
      done
    done
    run_layout_binding "$forward" "$FOUR"
    run_layout_binding "$forward" "$ONE"
    assert_transition_layout '143|243' "$axis"
  done
}

test_layout_local_pairing_with_neighbouring_group() {
  local before
  command -v tmux >/dev/null 2>&1 || return 0
  setup_layout_server
  create_transition_layout horizontal local-group
  before="$(layout_tmux list-panes -t "$FOUR" -F '#{pane_id}:#{pane_pid}' | sort)"
  assert_transition_layout '124|134' horizontal
  run_layout_binding S-up "$FOUR"
  assert_transition_layout '14|12|13' horizontal
  assert_eq 1 "$(layout_tmux display-message -p -t "$ONE" '#{==:#{pane_height},#{window_height}}')"
  assert_eq 1 "$(layout_tmux display-message -p -t "$FOUR" '#{pane_active}')"
  assert_eq "$before" "$(layout_tmux list-panes -t "$FOUR" -F '#{pane_id}:#{pane_pid}' | sort)"
}

test_case 'tmux layout: entry-first horizontal and vertical split transitions' test_layout_entry_first_transition_sequences
test_case 'tmux layout: single pane is unchanged' test_layout_single_pane_is_unchanged
test_case 'tmux layout: zoom and marked pane stay correctly scoped' test_layout_zoom_and_marked_pane
test_case 'tmux layout: failed application restores pane order, geometry and zoom' test_layout_failure_restores_order_geometry_and_zoom
test_case 'tmux layout: equivalent nested containers have the same transitions' test_layout_equivalent_nested_containers
test_case 'tmux layout: three-pane promotion reverses without saved history' test_layout_three_pane_promotion_reverses
test_case 'tmux layout: invalid layout input leaves panes untouched' test_layout_invalid_input_does_not_mutate_panes
test_case 'tmux layout: a middle sibling enters first and expands on the next press' test_layout_middle_sibling_enters_then_expands
test_case 'tmux layout: larger groups pair locally without moving outer panes' test_layout_larger_groups_pair_locally
test_case 'tmux layout: local pairing can target a neighbouring group' test_layout_local_pairing_with_neighbouring_group
