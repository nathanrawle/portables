TMUX_LAYOUT_SOCKET=
. "$TESTS_DIR/lib/tmux_client.bash"

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
  local key="$1" pane="$2" table="${3:-root}"
  layout_tmux select-window -t "$pane"
  layout_tmux select-pane -t "$pane"
  # list-keys escapes outer command separators that source-file needs to execute directly.
  layout_tmux list-keys -T "$table" | \
    awk -v key="$key" 'tolower($4) == tolower(key)' | \
    sed -E 's/^bind-key[[:space:]]+-T[[:space:]]+[^[:space:]]+[[:space:]]+[^[:space:]]+[[:space:]]+//; s/\\;/;/g' \
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
  assert_eq "$expected" "$actual" "unexpected transition layout: $(layout_tmux display-message -p -t "$FOUR" '#{window_layout}')"
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
  local real_tmux before order zoom socket helper floating floating_before
  command -v tmux >/dev/null 2>&1 || return 0
  setup_layout_server
  create_transition_layout horizontal rollback
  floating="$(layout_tmux new-pane -Ad -t "$FOUR" -P -F '#{pane_id}' 'sleep 120')"
  layout_tmux set-option -p -t "$FOUR" @reshape_origin "left $TWO"
  layout_tmux select-pane -t "$FOUR"
  layout_tmux resize-pane -Z -t "$FOUR"
  before="$(layout_tmux display-message -p -t "$FOUR" '#{window_layout}')"
  floating_before="$(floating_layout_state)"
  order="$(layout_tmux list-panes -t "$FOUR" -F '#{pane_id}:#{pane_pid}')"
  socket="$(layout_tmux display-message -p -t "$FOUR" '#{socket_path}')"
  real_tmux="$(command -v tmux)"
  helper="$REPO_ROOT/home/.config/tmux/reshape-pane"
  mkdir -p "$TEST_TMPDIR/bin"
  cat >"$TEST_TMPDIR/bin/tmux" <<'WRAPPER'
#!/usr/bin/env bash
if [[ "$1" == select-layout && ! -e "$FAIL_MARKER" ]]; then
  "$REAL_TMUX" "$@" || exit
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
  assert_eq "$floating_before" "$(floating_layout_state)" 'rollback should restore floating stacking and geometry'
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

test_layout_unsupported_json_is_rejected_without_mutation() {
  local before socket real_tmux status fixture
  setup_layout_server
  create_transition_layout horizontal unsupported-json
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
  printf '%s\n' "$LAYOUT_FIXTURE"
  exit 0
fi
exec "$REAL_TMUX" "$@"
WRAPPER
  chmod +x "$TEST_TMPDIR/bin/tmux"
  for fixture in '{"V":3,"L":{}}' '{"V":2,"L":{"t":"p","w":"bad"}}' '0000,legacy'; do
    status=0
    TMUX="$socket,0,0" PATH="$TEST_TMPDIR/bin:$PATH" REAL_TMUX="$real_tmux" \
      LAYOUT_FIXTURE="$fixture" "$REPO_ROOT/home/.config/tmux/reshape-pane" "$FOUR" left \
      >"$TEST_TMPDIR/diagnostics" 2>&1 || status=$?
    assert_eq 2 "$status"
    assert_eq 'reshape-pane: invalid or unsupported tmux JSON layout' "$(cat "$TEST_TMPDIR/diagnostics")"
    assert_eq "$before" "$(layout_window_state)" 'rejection should preserve all pane state'
  done
}

floating_layout_state() {
  layout_tmux display-message -p -t "$FOUR" '#{window_layout}' | \
    jq -c '[.. | objects | select(.t == "p" and has("z"))] | sort_by(.I) | map(del(.a, .l))'
}

test_layout_mixed_floating_windows() {
  local floating other before identities tiled socket status zoomed
  setup_layout_server
  create_transition_layout horizontal mixed
  floating="$(layout_tmux new-pane -Ad -t "$FOUR" -x 40 -y 15 -X 10 -Y 5 -P -F '#{pane_id}' 'sleep 120')"
  other="$(layout_tmux new-pane -d -t "$FOUR" -x 35 -y 12 -X 30 -Y 10 -P -F '#{pane_id}' 'sleep 120')"
  before="$(floating_layout_state)"
  identities="$(layout_tmux list-panes -t "$FOUR" -F '#{pane_id}:#{pane_pid}:#{pane_index}')"
  socket="$(layout_tmux display-message -p -t "$FOUR" '#{socket_path}')"
  for zoomed in 0 1; do
    layout_tmux select-pane -t "$FOUR"
    if [[ "$zoomed" == 1 ]]; then layout_tmux resize-pane -Z -t "$FOUR"; fi
    run_layout_binding S-left "$FOUR"
    assert_eq "$before" "$(floating_layout_state)" 'floating geometry and stacking must survive reshaping'
    assert_eq "$identities" "$(layout_tmux list-panes -t "$FOUR" -F '#{pane_id}:#{pane_pid}:#{pane_index}')"
    assert_eq 0 "$(layout_tmux display-message -p -t "$FOUR" '#{window_zoomed_flag}')"
    run_layout_binding S-right "$FOUR"
  done
  layout_tmux select-pane -t "$floating"
  before="$(layout_window_state)"
  status=0
  TMUX="$socket,0,0" "$REPO_ROOT/home/.config/tmux/reshape-pane" "$floating" left \
    >"$TEST_TMPDIR/diagnostics" 2>&1 || status=$?
  assert_eq 2 "$status"
  assert_eq 'reshape-pane: use move-pane to move a floating pane' "$(cat "$TEST_TMPDIR/diagnostics")"
  assert_eq "$before" "$(layout_window_state)" 'direct helper rejection must preserve floating panes'
}

test_layout_floating_controls_preserve_tiles() {
  local floating before x y width height expanded
  setup_layout_server
  create_transition_layout horizontal floating-controls
  floating="$(layout_tmux new-pane -Ad -t "$FOUR" -B single -x 45 -y 15 -X 20 -Y 10 -P -F '#{pane_id}' 'sleep 120')"
  before="$(layout_tmux list-panes -t "$FOUR" -F '#{?pane_floating_flag,,#{pane_id}:#{pane_left}:#{pane_top}:#{pane_width}:#{pane_height}}')"
  read -r x y width height < <(layout_tmux display-message -p -t "$floating" '#{pane_left} #{pane_top} #{pane_width} #{pane_height}')
  run_layout_binding S-right "$floating"
  assert_eq "$((x + 5))" "$(layout_tmux display-message -p -t "$floating" '#{pane_left}')"
  run_layout_binding S-down "$floating"
  assert_eq "$((y + 2))" "$(layout_tmux display-message -p -t "$floating" '#{pane_top}')"
  run_layout_binding C-= "$floating"
  assert_eq "$((width + 20))" "$(pane_sizing_dimension "$floating" width)"
  run_layout_binding C-- "$floating"
  assert_eq "$width" "$(pane_sizing_dimension "$floating" width)"
  run_layout_binding C-. "$floating"
  expanded="$(pane_sizing_dimension "$floating" height)"
  [[ "$expanded" -gt "$height" ]] || fail 'floating height should expand'
  run_layout_binding C-. "$floating"
  assert_eq "$height" "$(pane_sizing_dimension "$floating" height)"
  run_layout_binding C-, "$floating"
  width="$(pane_sizing_dimension "$floating" width)"
  run_layout_binding C-, "$floating"
  [[ "$(pane_sizing_dimension "$floating" width)" -gt "$width" ]] || fail 'floating width should advance to the next preset'
  assert_eq "$before" "$(layout_tmux list-panes -t "$FOUR" -F '#{?pane_floating_flag,,#{pane_id}:#{pane_left}:#{pane_top}:#{pane_width}:#{pane_height}}')"
}

test_layout_floating_terminal_binding_and_toggle() {
  local pane floating before bindings path
  setup_layout_server
  start_tmux_test_client "$TMUX_LAYOUT_SOCKET" layout
  trap 'layout_tmux kill-server >/dev/null 2>&1 || true; stop_tmux_test_client' EXIT
  pane="$(layout_tmux display-message -p '#{pane_id}')"
  path="$(layout_tmux display-message -p -t "$pane" '#{pane_current_path}')"
  layout_tmux set-option default-command 'sleep 120'
  before="$(layout_tmux display-message -p -t "$pane" '#{pane_pid}')"
  run_layout_binding T "$pane" prefix
  floating="$(layout_tmux display-message -p '#{pane_id}')"
  assert_eq 1 "$(layout_tmux display-message -p -t "$floating" '#{pane_floating_flag}')"
  assert_eq "$path" "$(layout_tmux display-message -p -t "$floating" '#{pane_current_path}')"
  assert_eq "$before" "$(layout_tmux display-message -p -t "$pane" '#{pane_pid}')"
  run_layout_binding @ "$floating" prefix
  assert_eq 0 "$(layout_tmux display-message -p -t "$floating" '#{pane_floating_flag}')"
  run_layout_binding @ "$floating" prefix
  assert_eq 1 "$(layout_tmux display-message -p -t "$floating" '#{pane_floating_flag}')"
  bindings="$(layout_tmux list-keys -T prefix)"
  [[ "$bindings" == *'M-t'*'select-pane -T'* ]] || fail 'pane title prompt should remain available on Alt+t'
  [[ "$(layout_tmux list-keys -T prefix G)" == *'switch-client -T move'* ]] || fail 'G should use the native move table'
  [[ "$(layout_tmux list-keys -T prefix t)" == *display-popup* ]] || fail 't should retain the terminal popup'
  [[ "$(layout_tmux list-keys -T prefix g)" == *lazygit* ]] || fail 'g should retain lazygit'
}

test_layout_local_equalization_keeps_nested_geometry_valid() {
  local before after pane
  setup_layout_server
  create_transition_layout horizontal equalize
  before="$(layout_tmux list-panes -t "$FOUR" -F '#{pane_id}:#{pane_pid}:#{pane_index}')"
  run_layout_binding E "$FOUR" prefix
  after="$(layout_tmux display-message -p -t "$FOUR" '#{window_layout}')"
  layout_tmux select-layout -t "$FOUR" "$after"
  assert_eq "$after" "$(layout_tmux display-message -p -t "$FOUR" '#{window_layout}')" 'equalized layout must survive a native JSON round trip'
  assert_eq "$before" "$(layout_tmux list-panes -t "$FOUR" -F '#{pane_id}:#{pane_pid}:#{pane_index}')"
}

test_layout_minimum_panes_can_be_reshaped() {
  local axis side along across width height direction before expected
  local -a placement
  command -v tmux >/dev/null 2>&1 || return 0
  setup_layout_server
  TWO=unused
  for axis in horizontal vertical; do
    if [[ "$axis" == horizontal ]]; then along=-v; across=-h; width=100; height=20
    else along=-h; across=-v; width=20; height=100; fi
    for side in before after; do
      placement=()
      if [[ "$side" == after ]]; then placement=(-b); fi
      FOUR="$(layout_tmux new-window -d -P -F '#{pane_id}' -n "minimum-$axis-$side" 'sleep 120')"
      layout_tmux resize-window -t "$FOUR" -x "$width" -y "$height"
      ONE="$(layout_tmux split-window -d "$along" "${placement[@]}" -l 17 -P -F '#{pane_id}' -t "$FOUR" 'sleep 120')"
      THREE="$(layout_tmux split-window -d "$across" -l 97 -P -F '#{pane_id}' -t "$ONE" 'sleep 120')"
      case "$axis:$side" in
        horizontal:before) direction=S-down ;;
        horizontal:after) direction=S-up ;;
        vertical:before) direction=S-right ;;
        vertical:after) direction=S-left ;;
      esac
      if [[ "$side" == before ]]; then assert_transition_layout '44|13' "$axis"; expected='14|13'
      else assert_transition_layout '13|44' "$axis"; expected='13|14'; fi
      before="$(layout_tmux list-panes -t "$FOUR" -F '#{pane_id}:#{pane_pid}' | sort)"
      run_layout_binding "$direction" "$FOUR"
      assert_transition_layout "$expected" "$axis"
      assert_eq "$before" "$(layout_tmux list-panes -t "$FOUR" -F '#{pane_id}:#{pane_pid}' | sort)"
      assert_eq 1 "$(layout_tmux display-message -p -t "$FOUR" '#{pane_active}')"
      layout_tmux list-panes -t "$FOUR" -F '#{pane_width} #{pane_height}' | \
        awk '$1 < 2 || $2 < 2 { exit 1 }'
    done
  done
  ONE="$(layout_tmux new-window -d -P -F '#{pane_id}' -n zero-excess 'sleep 120')"
  layout_tmux resize-window -t "$ONE" -x 8 -y 5
  TWO="$(layout_tmux split-window -dh -l 5 -P -F '#{pane_id}' -t "$ONE" 'sleep 120')"
  FOUR="$(layout_tmux split-window -dh -l 2 -P -F '#{pane_id}' -t "$TWO" 'sleep 120')"
  THREE=unused
  run_layout_binding S-left "$FOUR"
  assert_transition_layout '12|14' horizontal
  assert_eq 2 "$(layout_tmux display-message -p -t "$FOUR" '#{pane_height}')"
}

test_layout_nested_branch_minimum_is_reserved() {
  local lower before
  command -v tmux >/dev/null 2>&1 || return 0
  setup_layout_server
  FOUR="$(layout_tmux new-window -d -P -F '#{pane_id}' -n nested-minimum 'sleep 120')"
  layout_tmux resize-window -t "$FOUR" -x 100 -y 20
  ONE="$(layout_tmux split-window -dv -l 17 -P -F '#{pane_id}' -t "$FOUR" 'sleep 120')"
  THREE="$(layout_tmux split-window -dh -l 94 -P -F '#{pane_id}' -t "$ONE" 'sleep 120')"
  lower="$(layout_tmux split-window -dv -l 14 -P -F '#{pane_id}' -t "$ONE" 'sleep 120')"
  TWO="$(layout_tmux split-window -dh -l 2 -P -F '#{pane_id}' -t "$ONE" 'sleep 120')"
  before="$(layout_tmux list-panes -t "$FOUR" -F '#{pane_id}:#{pane_pid}' | sort)"
  run_layout_binding S-down "$FOUR"
  assert_eq "$before" "$(layout_tmux list-panes -t "$FOUR" -F '#{pane_id}:#{pane_pid}' | sort)"
  assert_eq "$(layout_tmux display-message -p -t "$THREE" '#{pane_left}')" \
    "$(layout_tmux display-message -p -t "$FOUR" '#{pane_left}')"
  [[ "$(layout_tmux display-message -p -t "$FOUR" '#{pane_top}')" -lt \
    "$(layout_tmux display-message -p -t "$THREE" '#{pane_top}')" ]] \
    || fail 'expected the active pane to join above the right-hand pane'
  [[ "$(layout_tmux display-message -p -t "$lower" '#{pane_width}')" -ge 5 ]] \
    || fail 'expected the left branch to retain room for both two-cell children'
  layout_tmux list-panes -t "$FOUR" -F '#{pane_width} #{pane_height}' | \
    awk '$1 < 2 || $2 < 2 { exit 1 }'
}

test_layout_insufficient_space_preserves_state() {
  local before socket status
  command -v tmux >/dev/null 2>&1 || return 0
  setup_layout_server
  FOUR="$(layout_tmux new-window -d -P -F '#{pane_id}' -n insufficient 'sleep 120')"
  layout_tmux resize-window -t "$FOUR" -x 2 -y 8
  ONE="$(layout_tmux split-window -dv -l 5 -P -F '#{pane_id}' -t "$FOUR" 'sleep 120')"
  THREE="$(layout_tmux split-window -dv -l 2 -P -F '#{pane_id}' -t "$ONE" 'sleep 120')"
  layout_tmux select-pane -t "$ONE"
  layout_tmux set-option -p -t "$ONE" @reshape_origin "right $FOUR"
  before="$(layout_window_state)"
  socket="$(layout_tmux display-message -p -t "$ONE" '#{socket_path}')"
  status=0
  TMUX="$socket,0,0" "$REPO_ROOT/home/.config/tmux/reshape-pane" "$ONE" left \
    >"$TEST_TMPDIR/diagnostics" 2>&1 || status=$?
  assert_eq 1 "$status" 'a genuinely oversized split should fail before mutation'
  assert_eq 'Invalid pane layout' "$(cat "$TEST_TMPDIR/diagnostics")"
  assert_eq "$before" "$(layout_window_state)" 'insufficient space should preserve pane state'
}

pane_sizing_dimension() {
  layout_tmux display-message -p -t "$1" "#{pane_$2}"
}

create_sizing_stack() {
  ONE="$(layout_tmux new-window -d -P -F '#{pane_id}' -n sizing 'sleep 120')"
  TWO="$(layout_tmux split-window -dh -P -F '#{pane_id}' -t "$ONE" 'sleep 120')"
  THREE="$(layout_tmux split-window -dv -P -F '#{pane_id}' -t "$TWO" 'sleep 120')"
}

test_layout_sizing_width_cycle() {
  command -v tmux >/dev/null 2>&1 || return 0
  setup_layout_server
  create_sizing_stack
  local width percent expected
  for width in 180 181; do
    layout_tmux resize-window -t "$ONE" -x "$width"
    layout_tmux resize-pane -t "$ONE" -x 20
    for percent in 25 33 50 66 75 25; do
      run_layout_binding C-, "$ONE"
      expected=$((width * percent / 100))
      assert_eq "$expected" "$(pane_sizing_dimension "$ONE" width)" "width preset $percent at $width columns"
    done
    layout_tmux resize-pane -t "$ONE" -x "$((width * 40 / 100))"
    run_layout_binding C-, "$ONE"
    assert_eq "$((width / 2))" "$(pane_sizing_dimension "$ONE" width)" 'arbitrary width should advance to 50%'
  done
}

test_layout_sizing_height_toggle() {
  command -v tmux >/dev/null 2>&1 || return 0
  setup_layout_server
  create_sizing_stack
  local height outer top bottom saved
  height="$(layout_tmux display-message -p -t "$TWO" '#{window_height}')"
  outer="$(layout_tmux display-message -p -t "$ONE" '#{pane_left}:#{pane_top}:#{pane_width}:#{pane_height}')"
  run_layout_binding C-. "$TWO"
  assert_eq "$((height * 95 / 100))" "$(pane_sizing_dimension "$TWO" height)" 'height should expand to 95%'
  saved="$(layout_tmux display-message -p -t "$TWO" '#{@pane_height_expanded}')"
  assert_eq "$((height * 95 / 100)):$height" "$saved" 'remember achieved dimensions'
  assert_eq '' "$(layout_tmux display-message -p -t "$THREE" '#{@pane_height_expanded}')" 'state must stay pane local'
  run_layout_binding C-. "$TWO"
  top="$(pane_sizing_dimension "$TWO" height)"
  bottom="$(pane_sizing_dimension "$THREE" height)"
  [[ $((top - bottom)) -ge -1 && $((top - bottom)) -le 1 ]] || fail 'stack heights should be equal within one row'
  assert_eq '' "$(layout_tmux display-message -p -t "$TWO" '#{@pane_height_expanded}')" 'equalizing clears state'
  assert_eq "$outer" "$(layout_tmux display-message -p -t "$ONE" '#{pane_left}:#{pane_top}:#{pane_width}:#{pane_height}')" 'neighboring column must stay unchanged'
  layout_tmux resize-pane -t "$TWO" -y 95%
  run_layout_binding C-. "$TWO"
  assert_eq "$top" "$(pane_sizing_dimension "$TWO" height)" 'an existing 95% pane should equalize'
  run_layout_binding C-. "$TWO"
  layout_tmux resize-pane -t "$TWO" -y 20
  run_layout_binding C-. "$TWO"
  assert_eq "$((height * 95 / 100))" "$(pane_sizing_dimension "$TWO" height)" 'manual resizing should invalidate expansion state'
  saved="$(layout_tmux display-message -p -t "$TWO" '#{@pane_height_expanded}')"
  run_layout_binding C-. "$THREE"
  assert_eq "$saved" "$(layout_tmux display-message -p -t "$TWO" '#{@pane_height_expanded}')" 'expanding another pane must not overwrite saved state'
  assert_eq "$((height * 95 / 100)):$height" "$(layout_tmux display-message -p -t "$THREE" '#{@pane_height_expanded}')" 'another pane tracks its own expansion'
}

test_layout_sizing_capped_height() {
  command -v tmux >/dev/null 2>&1 || return 0
  setup_layout_server
  create_sizing_stack
  local height actual top bottom
  layout_tmux resize-window -t "$TWO" -y 12
  height="$(layout_tmux display-message -p -t "$TWO" '#{window_height}')"
  run_layout_binding C-. "$TWO"
  actual="$(pane_sizing_dimension "$TWO" height)"
  [[ "$actual" -lt $((height * 95 / 100)) ]] || fail 'fixture should cap expansion below 95%'
  assert_eq "$actual:$height" "$(layout_tmux display-message -p -t "$TWO" '#{@pane_height_expanded}')" 'remember capped height'
  run_layout_binding C-. "$TWO"
  top="$(pane_sizing_dimension "$TWO" height)"
  bottom="$(pane_sizing_dimension "$THREE" height)"
  [[ $((top - bottom)) -ge -1 && $((top - bottom)) -le 1 ]] || fail 'capped expansion should toggle back to equal heights'
}

test_layout_sizing_zoom_and_single_pane() {
  command -v tmux >/dev/null 2>&1 || return 0
  setup_layout_server
  local before key
  ONE="$(layout_tmux display-message -p '#{pane_id}')"
  before="$(layout_tmux display-message -p -t "$ONE" '#{window_layout}')"
  for key in C-, C-. C-.; do
    run_layout_binding "$key" "$ONE"
    assert_eq "$before" "$(layout_tmux display-message -p -t "$ONE" '#{window_layout}')" 'single pane geometry stays unchanged'
  done
  create_sizing_stack
  layout_tmux resize-pane -t "$ONE" -x 20
  for key in C-, C-.; do
    layout_tmux resize-pane -Z -t "$TWO"
    run_layout_binding "$key" "$TWO"
    assert_eq 0 "$(layout_tmux display-message -p -t "$TWO" '#{window_zoomed_flag}')" 'sizing should unzoom'
  done
}

test_case 'tmux layout: sizing width cycles through rounded presets' test_layout_sizing_width_cycle
test_case 'tmux layout: sizing height toggles locally and invalidates stale state' test_layout_sizing_height_toggle
test_case 'tmux layout: sizing capped height still toggles back' test_layout_sizing_capped_height
test_case 'tmux layout: sizing unzooms and preserves single panes' test_layout_sizing_zoom_and_single_pane

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
test_case 'tmux layout: mixed floating windows preserve geometry, stacking and identities' test_layout_mixed_floating_windows
test_case 'tmux layout: malformed and unsupported JSON preserves state' test_layout_unsupported_json_is_rejected_without_mutation
test_case 'tmux layout: floating movement and sizing preserve tiled geometry' test_layout_floating_controls_preserve_tiles
test_case 'tmux layout: floating terminal, title prompt and native toggle bindings' test_layout_floating_terminal_binding_and_toggle
test_case 'tmux layout: local equalization produces valid nested geometry' test_layout_local_equalization_keeps_nested_geometry_valid
test_case 'tmux layout: minimum panes can be reshaped in all directions' test_layout_minimum_panes_can_be_reshaped
test_case 'tmux layout: insufficient space preserves state' test_layout_insufficient_space_preserves_state
test_case 'tmux layout: nested branch minimum is reserved' test_layout_nested_branch_minimum_is_reserved
