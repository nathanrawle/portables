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
  layout_tmux list-keys -T root | \
    awk -v key="$key" 'tolower($4) == tolower(key)' | \
    sed -E 's/^bind-key[[:space:]]+-T[[:space:]]+root[[:space:]]+[^[:space:]]+[[:space:]]+//' \
    >"$TEST_TMPDIR/binding.conf"
  [[ -s "$TEST_TMPDIR/binding.conf" ]] || fail "missing loaded binding: $key"
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
  layout_tmux set-option -p -t "$FOUR" @reshape_origin "left $TWO"
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
  assert_eq "left $TWO" "$(origin_hint "$FOUR")" 'failed movement should preserve the hint'
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

create_origin_layout() {
  local axis="$1" side="$2" across=-h within=-v
  local -a placement
  placement=()
  if [[ "$axis" == vertical ]]; then across=-v; within=-h; fi
  if [[ "$side" == before ]]; then placement=(-b); fi
  ONE="$(layout_tmux new-window -d -P -F '#{pane_id}' -n "origin-$axis-$side" 'sleep 120')"
  TWO="$(layout_tmux split-window -d "$across" -P -F '#{pane_id}' -t "$ONE" 'sleep 120')"
  THREE="$(layout_tmux split-window -d "$across" -f -P -F '#{pane_id}' -t "$ONE" 'sleep 120')"
  FOUR="$(layout_tmux split-window -d "$within" "${placement[@]}" -P -F '#{pane_id}' -t "$TWO" 'sleep 120')"
}

origin_hint() {
  layout_tmux display-message -p -t "$1" '#{@reshape_origin}'
}

test_layout_origin_guides_next_reverse_entry() {
  local axis side forward backward initial expanded hint before
  command -v tmux >/dev/null 2>&1 || return 0
  setup_layout_server
  for axis in horizontal vertical; do
    for side in before after; do
      create_origin_layout "$axis" "$side"
      case "$axis:$side" in
        horizontal:before) forward=S-up; backward=S-down ;;
        horizontal:after) forward=S-down; backward=S-up ;;
        vertical:before) forward=S-left; backward=S-right ;;
        vertical:after) forward=S-right; backward=S-left ;;
      esac
      if [[ "$side" == before ]]; then initial='143|123'; expanded='444|123'
      else initial='123|143'; expanded='123|444'; fi
      before="$(layout_tmux list-panes -t "$FOUR" -F '#{pane_id}:#{pane_pid}' | sort)"
      layout_tmux select-pane -t "$THREE"
      run_layout_binding "$forward" "$FOUR"
      assert_transition_layout "$expanded" "$axis"
      hint="${backward#S-} $TWO"
      assert_eq "$hint" "$(origin_hint "$FOUR")"
      run_layout_binding "$forward" "$FOUR"
      assert_eq "$hint" "$(origin_hint "$FOUR")" 'boundary no-op should preserve the hint'
      layout_tmux resize-pane -t "$TWO" -x 25 -y 10
      layout_tmux select-pane -t "$THREE"
      run_layout_binding "$backward" "$FOUR"
      assert_transition_layout "$initial" "$axis"
      assert_eq '' "$(origin_hint "$FOUR")" 'successful entry should consume the hint'
      assert_eq 1 "$(layout_tmux display-message -p -t "$FOUR" '#{pane_active}')"
      assert_eq "$before" "$(layout_tmux list-panes -t "$FOUR" -F '#{pane_id}:#{pane_pid}' | sort)"
    done
  done
}

test_layout_stale_origins_fall_back() {
  local scenario destination expected
  command -v tmux >/dev/null 2>&1 || return 0
  setup_layout_server
  for scenario in killed moved hidden malformed; do
    create_origin_layout horizontal before
    run_layout_binding S-up "$FOUR"
    expected='14|13'
    case "$scenario" in
      killed) layout_tmux kill-pane -t "$TWO" ;;
      moved)
        destination="$(layout_tmux new-window -d -P -F '#{pane_id}' 'sleep 120')"
        layout_tmux join-pane -d -s "$TWO" -t "$destination" ;;
      hidden)
        layout_tmux join-pane -dv -s "$TWO" -t "$THREE"
        expected='14|13|12' ;;
      malformed)
        layout_tmux set-option -p -t "$FOUR" @reshape_origin 'invalid hint'
        expected='124|123' ;;
    esac
    run_layout_binding S-down "$FOUR"
    assert_transition_layout "$expected" horizontal
    assert_eq '' "$(origin_hint "$FOUR")" 'stale hints should be discarded'
  done
}

test_layout_origin_is_bounded_and_pane_scoped() {
  local independent
  command -v tmux >/dev/null 2>&1 || return 0
  setup_layout_server
  independent="$(layout_tmux display-message -p -t layout:1 '#{pane_id}')"
  layout_tmux set-option -p -t "$independent" @reshape_origin 'left %999999'
  create_origin_layout horizontal before
  run_layout_binding S-up "$FOUR"
  run_layout_binding S-right "$FOUR"
  assert_eq "left $THREE" "$(origin_hint "$FOUR")" 'another expansion should replace the old hint'
  run_layout_binding S-left "$FOUR"
  assert_eq '' "$(origin_hint "$FOUR")" 'the next successful entry should clear the hint'
  assert_eq 'left %999999' "$(origin_hint "$independent")" 'other panes should keep their own hint'
  run_layout_binding S-left "$independent"
  assert_eq '' "$(origin_hint "$independent")" 'a no-op should discard an invalid origin'
}

layout_window_state() {
  layout_tmux display-message -p -t "$FOUR" '#{window_width}:#{window_height}:#{window_layout}:#{window_zoomed_flag}'
  layout_tmux list-panes -t "$FOUR" \
    -F '#{pane_id}:#{pane_pid}:#{pane_active}:#{pane_left}:#{pane_top}:#{pane_width}:#{pane_height}:#{@reshape_origin}'
}

test_layout_floating_suffix_is_rejected_without_mutation() {
  local before socket real_tmux status
  command -v tmux >/dev/null 2>&1 || return 0
  setup_layout_server
  create_transition_layout horizontal floating-suffix
  layout_tmux select-pane -t "$FOUR"
  layout_tmux set-option -p -t "$FOUR" @reshape_origin "left $TWO"
  layout_tmux resize-pane -Z -t "$FOUR"
  before="$(layout_window_state)"
  socket="$(layout_tmux display-message -p -t "$FOUR" '#{socket_path}')"
  real_tmux="$(command -v tmux)"
  mkdir -p "$TEST_TMPDIR/bin"
  cat >"$TEST_TMPDIR/bin/tmux" <<'WRAPPER'
#!/usr/bin/env bash
if [[ "$1" == display-message && "$*" == *'#{window_layout}'* ]]; then
  layout="$("$REAL_TMUX" "$@")" || exit
  printf '%s<20x10,4,2,999999>\n' "$layout"
  exit 0
fi
exec "$REAL_TMUX" "$@"
WRAPPER
  chmod +x "$TEST_TMPDIR/bin/tmux"
  status=0
  TMUX="$socket,0,0" PATH="$TEST_TMPDIR/bin:$PATH" REAL_TMUX="$real_tmux" \
    "$REPO_ROOT/home/.config/tmux/reshape-pane" "$FOUR" left \
    >"$TEST_TMPDIR/diagnostics" 2>&1 || status=$?
  assert_eq 2 "$status"
  assert_eq 'reshape-pane: windows containing floating panes are not supported' \
    "$(cat "$TEST_TMPDIR/diagnostics")"
  assert_eq "$before" "$(layout_window_state)" 'unsupported layout should preserve all pane state'
}

test_layout_real_floating_window_is_preserved() {
  local floating pane direction before socket status
  command -v tmux >/dev/null 2>&1 || return 0
  setup_layout_server
  if ! layout_tmux list-commands | rg '^new-pane ' >/dev/null; then return 0; fi
  if [[ "$(layout_tmux display-message -p -t layout:1 '#{window_layout}')" == '{'* ]]; then return 0; fi
  create_transition_layout horizontal real-floating
  floating="$(layout_tmux new-pane -d -t "$FOUR" -P -F '#{pane_id}' 'sleep 120')"
  assert_eq 1 "$(layout_tmux display-message -p -t "$floating" '#{pane_floating_flag}')"
  socket="$(layout_tmux display-message -p -t "$FOUR" '#{socket_path}')"
  layout_tmux set-option -p -t "$FOUR" @reshape_origin "left $TWO"
  layout_tmux set-option -p -t "$floating" @reshape_origin "up $ONE"
  for pane in "$FOUR" "$floating"; do
    layout_tmux select-window -t "$pane"
    layout_tmux select-pane -t "$pane"
    if [[ "$pane" == "$FOUR" ]]; then
      direction=left
      layout_tmux resize-pane -Z -t "$pane"
    else direction=up; fi
    before="$(layout_window_state)"
    status=0
    TMUX="$socket,0,0" "$REPO_ROOT/home/.config/tmux/reshape-pane" "$pane" "$direction" \
      >"$TEST_TMPDIR/diagnostics" 2>&1 || status=$?
    assert_eq 2 "$status"
    assert_eq 'reshape-pane: windows containing floating panes are not supported' \
      "$(cat "$TEST_TMPDIR/diagnostics")"
    assert_eq "$before" "$(layout_window_state)" 'floating windows should remain unchanged'
    if [[ "$pane" == "$FOUR" ]]; then layout_tmux resize-pane -Z -t "$pane"; fi
  done
  layout_tmux kill-pane -t "$floating"
  layout_tmux set-option -pu -t "$FOUR" @reshape_origin
  layout_tmux select-pane -t "$FOUR"
  TMUX="$socket,0,0" "$REPO_ROOT/home/.config/tmux/reshape-pane" "$FOUR" left
  assert_transition_layout '122|134' horizontal
}

test_layout_json_format_is_rejected_without_mutation() {
  local before socket real_tmux status
  command -v tmux >/dev/null 2>&1 || return 0
  setup_layout_server
  create_transition_layout horizontal json-format
  layout_tmux select-pane -t "$FOUR"
  layout_tmux set-option -p -t "$FOUR" @reshape_origin "left $TWO"
  layout_tmux resize-pane -Z -t "$FOUR"
  before="$(layout_window_state)"
  socket="$(layout_tmux display-message -p -t "$FOUR" '#{socket_path}')"
  real_tmux="$(command -v tmux)"
  mkdir -p "$TEST_TMPDIR/bin"
  cat >"$TEST_TMPDIR/bin/tmux" <<'WRAPPER'
#!/usr/bin/env bash
if [[ "$1" == display-message && "$*" == *'#{window_layout}'* ]]; then
  printf '%s\n' '{"V":2,"L":{"t":"p","w":180,"h":60,"x":0,"y":0,"I":"%0"}}'
  exit 0
fi
exec "$REAL_TMUX" "$@"
WRAPPER
  chmod +x "$TEST_TMPDIR/bin/tmux"
  status=0
  TMUX="$socket,0,0" PATH="$TEST_TMPDIR/bin:$PATH" REAL_TMUX="$real_tmux" \
    "$REPO_ROOT/home/.config/tmux/reshape-pane" "$FOUR" left \
    >"$TEST_TMPDIR/diagnostics" 2>&1 || status=$?
  assert_eq 2 "$status"
  assert_eq 'reshape-pane: tmux JSON layouts are not supported; use a tmux version with legacy layouts' \
    "$(cat "$TEST_TMPDIR/diagnostics")"
  assert_eq "$before" "$(layout_window_state)" 'JSON rejection should preserve all pane state'
}

test_layout_real_json_window_is_preserved() {
  local socket before status zoomed
  command -v tmux >/dev/null 2>&1 || return 0
  setup_layout_server
  if [[ "$(layout_tmux display-message -p -t layout:1 '#{window_layout}')" != '{'* ]]; then return 0; fi
  create_transition_layout horizontal real-json
  layout_tmux select-pane -t "$FOUR"
  layout_tmux set-option -p -t "$FOUR" @reshape_origin "left $TWO"
  socket="$(layout_tmux display-message -p -t "$FOUR" '#{socket_path}')"
  for zoomed in 0 1; do
    if [[ "$zoomed" == 1 ]]; then layout_tmux resize-pane -Z -t "$FOUR"; fi
    before="$(layout_window_state)"
    status=0
    TMUX="$socket,0,0" "$REPO_ROOT/home/.config/tmux/reshape-pane" "$FOUR" left \
      >"$TEST_TMPDIR/diagnostics" 2>&1 || status=$?
    assert_eq 2 "$status"
    assert_eq 'reshape-pane: tmux JSON layouts are not supported; use a tmux version with legacy layouts' \
      "$(cat "$TEST_TMPDIR/diagnostics")"
    assert_eq "$before" "$(layout_window_state)" 'real JSON windows should remain unchanged'
  done
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
test_case 'tmux layout: origin guides the next reverse entry in all directions' test_layout_origin_guides_next_reverse_entry
test_case 'tmux layout: stale origins fall back to structural selection' test_layout_stale_origins_fall_back
test_case 'tmux layout: origin hints are bounded and pane scoped' test_layout_origin_is_bounded_and_pane_scoped
test_case 'tmux layout: floating suffix reports the tiled-window limitation without mutation' test_layout_floating_suffix_is_rejected_without_mutation
test_case 'tmux layout: real floating windows preserve state until the floating pane is removed' test_layout_real_floating_window_is_preserved
test_case 'tmux layout: JSON layouts report the unsupported format without mutation' test_layout_json_format_is_rejected_without_mutation
test_case 'tmux layout: real JSON windows preserve state with and without zoom' test_layout_real_json_window_is_preserved
