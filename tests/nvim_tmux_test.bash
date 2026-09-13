#!/usr/bin/env bash

. "$TESTS_DIR/lib/taw_test_helpers.bash"

NVIM_TMUX="$REPO_ROOT/home/.zfuns/nvim-tmux"
NVIM_RUNTIME="$REPO_ROOT/home/.config/nvim"
NVIM_TMUX_BIN=
NVIM_TMUX_SOCKET=
NVIM_TMUX_TEST_FILE=

cleanup_nvim_tmux_server() {
  if [[ -n "$NVIM_TMUX_BIN" && -n "$NVIM_TMUX_SOCKET" ]]; then
    "$NVIM_TMUX_BIN" -L "$NVIM_TMUX_SOCKET" kill-server >/dev/null 2>&1 || true
  fi
}

wait_for_pane_option() {
  local pane="$1"
  local option="$2"
  local value attempt

  for ((attempt = 0; attempt < 100; attempt++)); do
    value="$("$NVIM_TMUX_BIN" -L "$NVIM_TMUX_SOCKET" \
      show-option -pqv -t "$pane" "$option" 2>/dev/null)" || value=
    if [[ -n "$value" ]]; then
      printf '%s\n' "$value"
      return 0
    fi
    sleep 0.05
  done
  fail "timed out waiting for $option on $pane"
}

wait_for_file() {
  local path="$1"
  local attempt

  for ((attempt = 0; attempt < 100; attempt++)); do
    [[ -s "$path" ]] && return 0
    sleep 0.05
  done
  fail "timed out waiting for $path"
}

wait_for_socket() {
  local path="$1"
  local attempt

  for ((attempt = 0; attempt < 100; attempt++)); do
    [[ -S "$path" ]] && return 0
    sleep 0.05
  done
  fail "timed out waiting for $path"
}

start_registered_nvim() {
  local command="$1"
  local target_args=( "${@:2}" )

  "$NVIM_TMUX_BIN" -L "$NVIM_TMUX_SOCKET" "$command" \
    -d -P -F '#{pane_id}' "${target_args[@]}" \
    "TAW_NVIM_RUNTIME='$NVIM_RUNTIME' nvim -u '$TEST_TMPDIR/minimal-init.lua' -i NONE '$NVIM_TMUX_TEST_FILE'"
}

run_bridge() {
  local tmux_environment="$1"
  local caller_pane="$2"
  shift 2

  TMUX="$tmux_environment" TMUX_PANE="$caller_pane" "$NVIM_TMUX" "$@"
}

make_no_lsof_path() {
  local bin="$TEST_TMPDIR/no-lsof-bin"
  local command path

  mkdir -p "$bin"
  for command in bash env git jq nvim od ps realpath tmux tr; do
    path="$(command -v "$command")"
    ln -s "$path" "$bin/$command"
  done
  printf '%s\n' "$bin"
}

test_agent_nvim_lua_context() {
  command -v nvim >/dev/null 2>&1 || return 0

  cat >"$TEST_TMPDIR/context-test.lua" <<'EOF'
vim.opt.runtimepath:prepend(vim.env.TAW_NVIM_RUNTIME)
local bridge = require("agent_nvim")
local buffer = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { "first", "second", "third" })
vim.api.nvim_win_set_cursor(0, { 2, 2 })
local namespace = vim.api.nvim_create_namespace("test-diagnostics")
vim.diagnostic.set(namespace, buffer, {
  { lnum = 1, col = 1, severity = vim.diagnostic.severity.WARN, message = "warning", source = "test" },
})
vim.cmd("normal! ggVj")
local context = bridge.context()
assert(context.cursor.line == 2)
assert(context.cursor.column == 3)
assert(context.selection.mode == "V")
assert(context.selection.text == "first\nsecond")
assert(context.diagnostics[1].line == 2)
assert(context.diagnostics[1].severity == "WARN")

local agent_namespace = vim.api.nvim_create_namespace("taw-agent-nvim")
vim.api.nvim_buf_set_extmark(buffer, agent_namespace, 0, 0, { end_col = 1, hl_group = "Visual" })
local other_buffer = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_extmark(other_buffer, agent_namespace, 0, 0, { hl_group = "Visual" })
require("keymaps")
vim.opt.hlsearch = true
vim.fn.setreg("/", "first")
vim.cmd("normal! gg")
vim.cmd("normal! n")
assert(vim.v.hlsearch == 1)
local escape_mapping
for _, mapping in ipairs(vim.api.nvim_get_keymap("n")) do
  if mapping.lhs == "<Esc>" then
    escape_mapping = mapping.callback
  end
end
assert(type(escape_mapping) == "function")
escape_mapping()
assert(vim.v.hlsearch == 0)
assert(#vim.api.nvim_buf_get_extmarks(buffer, agent_namespace, 0, -1, {}) == 0)
assert(#vim.api.nvim_buf_get_extmarks(other_buffer, agent_namespace, 0, -1, {}) == 1)
EOF

  TMUX= TMUX_PANE= TAW_NVIM_RUNTIME="$NVIM_RUNTIME" \
    nvim --headless -u NONE -i NONE -l "$TEST_TMPDIR/context-test.lua"
}

test_nvim_tmux_hook_is_quiet_outside_tmux() {
  local output

  output="$(TMUX= TMUX_PANE= "$NVIM_TMUX" codex-context)"
  assert_eq "" "$output" "expected no startup context outside tmux"
}

test_nvim_tmux_discovers_and_controls_exact_window() {
  local init first second outside editor agent socket_path tmux_environment output summary count
  local ancestry_output ambiguity_output ambiguity_status other_agent fallback_editor fallback_agent
  local registered_socket registered_pid no_lsof_path stale_status stdin_guard_path real_nvim
  local extra_socket invalid_highlight_status highlight_row nested_socket

  command -v tmux >/dev/null 2>&1 || return 0
  command -v nvim >/dev/null 2>&1 || return 0
  command -v jq >/dev/null 2>&1 || return 0
  NVIM_TMUX_BIN="$(command -v tmux)"
  NVIM_TMUX_SOCKET="portables-nvim-tmux-$$-$RANDOM"
  trap cleanup_nvim_tmux_server EXIT

  init="$TEST_TMPDIR/minimal-init.lua"
  first="$REPO_ROOT/README.md"
  second="$REPO_ROOT/docs/taw.md"
  NVIM_TMUX_TEST_FILE="$first"
  outside="$TEST_TMPDIR/../outside.txt"
  cat >"$init" <<'EOF'
vim.opt.swapfile = false
vim.opt.runtimepath:prepend(vim.env.TAW_NVIM_RUNTIME)
require("agent_nvim").setup()
EOF
  printf 'outside\n' >"$outside"

  editor="$(start_registered_nvim new-session -s nvim-tmux -n editor)"
  agent="$("$NVIM_TMUX_BIN" -L "$NVIM_TMUX_SOCKET" split-window \
    -d -P -F '#{pane_id}' -t "$editor" 'sleep 120')"
  wait_for_pane_option "$editor" @taw_nvim_socket >/dev/null
  socket_path="$("$NVIM_TMUX_BIN" -L "$NVIM_TMUX_SOCKET" \
    display-message -p -t "$editor" '#{socket_path}')"
  tmux_environment="$socket_path,$$,0"

  output="$(run_bridge "$tmux_environment" "$agent" discover)"
  assert_eq "$editor" "$(jq -r '.pane_id' <<<"$output")" "unexpected editor pane"
  assert_eq registered "$(jq -r '.source' <<<"$output")" "expected registered discovery"

  output="$(run_bridge "$tmux_environment" "$agent" context)"
  assert_eq "$first" "$(jq -r '.editor.file' <<<"$output")" "unexpected current file"
  registered_socket="$("$NVIM_TMUX_BIN" -L "$NVIM_TMUX_SOCKET" \
    show-option -pqv -t "$editor" @taw_nvim_socket)"
  output="$(run_bridge "$tmux_environment" "$agent" codex-context)"
  assert_string_contains "$output" \
    'A live Neovim is available in this exact tmux window. Connection context:'
  assert_string_contains "$output" \
    "Only if an initial attempt to reach Neovim fails, refresh with: nvim-tmux --pane $editor context."
  assert_string_contains "$output" \
    "Use nvim-tmux --pane $editor open, highlight, and clear-highlights—not direct Ex, Lua, remote-expr, or remote-send."
  assert_string_contains "$output" \
    'Conservatively focus the relevant file and smallest useful line range when it materially helps explain or hand off work; otherwise leave the editor untouched, and clear stale highlights before showing a new location.'
  summary="$(sed -n 's/^A live Neovim is available in this exact tmux window\. Connection context: //p' \
    <<<"$output")"
  assert_eq "$agent" "$(jq -r '.routing.codex_pane_id' <<<"$summary")" \
    "unexpected Codex pane in startup context"
  assert_eq "$editor" "$(jq -r '.routing.nvim_pane_id' <<<"$summary")" \
    "unexpected Neovim pane in startup context"
  assert_eq "$registered_socket" "$(jq -r '.connection.socket' <<<"$summary")" \
    "unexpected Neovim socket in startup context"
  assert_eq false "$(jq -r 'has("editor")' <<<"$summary")" \
    "startup context should not include stale editor state"

  stdin_guard_path="$TEST_TMPDIR/stdin-guard-bin"
  real_nvim="$(command -v nvim)"
  mkdir -p "$stdin_guard_path"
  cat >"$stdin_guard_path/nvim" <<EOF
#!/usr/bin/env bash
if IFS= read -r input; then
  exit 0
fi
exec "$real_nvim" "\$@"
EOF
  chmod +x "$stdin_guard_path/nvim"
  output="$(printf 'caller input\n' | PATH="$stdin_guard_path:$PATH" \
    run_bridge "$tmux_environment" "$agent" context)"
  assert_eq "$first" "$(jq -r '.editor.file' <<<"$output")" \
    "RPC client should not inherit caller stdin"

  registered_pid="$("$NVIM_TMUX_BIN" -L "$NVIM_TMUX_SOCKET" \
    show-option -pqv -t "$editor" @taw_nvim_pid)"
  no_lsof_path="$(make_no_lsof_path)"
  output="$(PATH="$no_lsof_path" run_bridge "$tmux_environment" "$agent" discover)"
  assert_eq registered "$(jq -r '.source' <<<"$output")" \
    "registered discovery should not require lsof"
  "$NVIM_TMUX_BIN" -L "$NVIM_TMUX_SOCKET" \
    set-option -p -t "$editor" @taw_nvim_socket /tmp/missing-nvim-socket
  if PATH="$no_lsof_path" run_bridge "$tmux_environment" "$agent" discover >/dev/null 2>&1; then
    fail "expected stale registration to be ignored without lsof"
  else
    stale_status=$?
  fi
  assert_eq 1 "$stale_status" "unexpected stale-registration exit status"
  "$NVIM_TMUX_BIN" -L "$NVIM_TMUX_SOCKET" \
    set-option -p -t "$editor" @taw_nvim_pid "$registered_pid"
  "$NVIM_TMUX_BIN" -L "$NVIM_TMUX_SOCKET" \
    set-option -p -t "$editor" @taw_nvim_socket "$registered_socket"

  output="$(cd "$REPO_ROOT" && run_bridge "$tmux_environment" "$agent" open "$second" 3 2)"
  assert_eq "$second" "$(jq -r '.editor.file' <<<"$output")" "open did not select the file"
  assert_eq 3 "$(jq -r '.editor.cursor.line' <<<"$output")" "open did not select the line"
  assert_eq 2 "$(jq -r '.editor.cursor.column' <<<"$output")" "open did not select the column"

  cd "$REPO_ROOT"
  run_bridge "$tmux_environment" "$agent" highlight "$first" 2:3 >/dev/null
  count="$(nvim --server "$(jq -r '.socket' <<<"$(run_bridge "$tmux_environment" "$agent" discover)")" \
    --remote-expr "luaeval(\"#vim.api.nvim_buf_get_extmarks(0, vim.api.nvim_create_namespace('taw-agent-nvim'), 0, -1, {})\")")"
  assert_eq 1 "$count" "expected one highlight extmark"
  run_bridge "$tmux_environment" "$agent" open "$second" 3 2 >/dev/null
  if run_bridge "$tmux_environment" "$agent" highlight "$first" 1:1 999:999 >/dev/null 2>&1; then
    fail "expected an invalid later range to reject the highlight operation"
  else
    invalid_highlight_status=$?
  fi
  assert_eq 4 "$invalid_highlight_status" "unexpected invalid-highlight exit status"
  output="$(run_bridge "$tmux_environment" "$agent" context)"
  assert_eq "$second" "$(jq -r '.editor.file' <<<"$output")" \
    "invalid ranges should preserve the current file"
  assert_eq 3 "$(jq -r '.editor.cursor.line' <<<"$output")" \
    "invalid ranges should preserve the cursor line"
  assert_eq 2 "$(jq -r '.editor.cursor.column' <<<"$output")" \
    "invalid ranges should preserve the cursor column"
  run_bridge "$tmux_environment" "$agent" open "$first" >/dev/null
  highlight_row="$(nvim --server "$(jq -r '.socket' <<<"$(run_bridge "$tmux_environment" "$agent" discover)")" \
    --remote-expr "luaeval(\"vim.api.nvim_buf_get_extmarks(0, vim.api.nvim_create_namespace('taw-agent-nvim'), 0, -1, {})[1][2]\")")"
  assert_eq 1 "$highlight_row" "invalid ranges should preserve the previous highlights"
  run_bridge "$tmux_environment" "$agent" clear-highlights "$first" >/dev/null
  count="$(nvim --server "$(jq -r '.socket' <<<"$(run_bridge "$tmux_environment" "$agent" discover)")" \
    --remote-expr "luaeval(\"#vim.api.nvim_buf_get_extmarks(0, vim.api.nvim_create_namespace('taw-agent-nvim'), 0, -1, {})\")")"
  assert_eq 0 "$count" "expected highlights to be cleared"

  if run_bridge "$tmux_environment" "$agent" open "$outside" >/dev/null 2>&1; then
    fail "expected a path outside the worktree to be rejected"
  fi

  ancestry_output="$TEST_TMPDIR/ancestry.json"
  "$NVIM_TMUX_BIN" -L "$NVIM_TMUX_SOCKET" respawn-pane -k -t "$agent" \
    "env -u TMUX_PANE '$NVIM_TMUX' --pane '$editor' discover >'$ancestry_output'"
  wait_for_file "$ancestry_output"
  assert_eq "$editor" "$(jq -r '.pane_id' "$ancestry_output")" \
    "process ancestry did not resolve the editor"

  agent="$("$NVIM_TMUX_BIN" -L "$NVIM_TMUX_SOCKET" split-window \
    -d -P -F '#{pane_id}' -t "$editor" 'sleep 120')"
  local second_editor
  second_editor="$(start_registered_nvim split-window -t "$editor")"
  wait_for_pane_option "$second_editor" @taw_nvim_socket >/dev/null
  if ambiguity_output="$(run_bridge "$tmux_environment" "$agent" discover 2>&1)"; then
    fail "expected multiple editors to be rejected"
  else
    ambiguity_status=$?
  fi
  assert_eq 3 "$ambiguity_status" "unexpected ambiguity exit status"
  assert_string_contains "$ambiguity_output" 'multiple Neovim instances found'
  output="$(run_bridge "$tmux_environment" "$agent" codex-context)"
  assert_string_contains "$output" 'Multiple Neovim instances are available'
  assert_string_contains "$output" "$editor,$second_editor"
  output="$(run_bridge "$tmux_environment" "$agent" --pane "$editor" discover)"
  assert_eq "$editor" "$(jq -r '.pane_id' <<<"$output")" "explicit pane was not selected"

  if command -v lsof >/dev/null 2>&1; then
    extra_socket="$TEST_TMPDIR/extra-nvim.sock"
    nvim --server "$registered_socket" --remote-expr "serverstart('$extra_socket')" >/dev/null
    wait_for_socket "$extra_socket"
    output="$(run_bridge "$tmux_environment" "$agent" --pane "$editor" discover)"
    assert_eq registered "$(jq -r '.source' <<<"$output")" \
      "multiple sockets for one Neovim should prefer its registration"

    nested_socket="$TEST_TMPDIR/nested-nvim.sock"
    nvim --server "$registered_socket" --remote-expr \
      "luaeval(\"vim.fn.jobstart({'nvim', '--headless', '-u', 'NONE', '-i', 'NONE', '--listen', _A})\", '$nested_socket')" \
      >/dev/null
    wait_for_socket "$nested_socket"
    if ambiguity_output="$(run_bridge "$tmux_environment" "$agent" --pane "$editor" discover 2>&1)"; then
      fail "expected multiple editors in one registered pane to be rejected"
    else
      ambiguity_status=$?
    fi
    assert_eq 3 "$ambiguity_status" "unexpected same-pane ambiguity exit status"
  fi

  other_agent="$("$NVIM_TMUX_BIN" -L "$NVIM_TMUX_SOCKET" new-window \
    -d -P -F '#{pane_id}' -t nvim-tmux: -n no-editor 'sleep 120')"
  if run_bridge "$tmux_environment" "$other_agent" discover >/dev/null 2>&1; then
    fail "expected another window's editors to be ignored"
  else
    assert_eq 1 "$?" "unexpected no-editor exit status"
  fi

  if command -v lsof >/dev/null 2>&1; then
    fallback_editor="$("$NVIM_TMUX_BIN" -L "$NVIM_TMUX_SOCKET" new-window \
      -d -P -F '#{pane_id}' -t nvim-tmux: -n fallback \
      "nvim -u NONE -i NONE '$first'")"
    fallback_agent="$("$NVIM_TMUX_BIN" -L "$NVIM_TMUX_SOCKET" split-window \
      -d -P -F '#{pane_id}' -t "$fallback_editor" 'sleep 120')"
    sleep 0.2
    output="$(run_bridge "$tmux_environment" "$fallback_agent" discover)"
    assert_eq lsof "$(jq -r '.source' <<<"$output")" "expected lsof fallback"
  fi
}

test_case "agent Neovim: reports context, selection, and diagnostics" \
  test_agent_nvim_lua_context
test_case "nvim-tmux: startup context is quiet outside tmux" \
  test_nvim_tmux_hook_is_quiet_outside_tmux
test_case "nvim-tmux: discovers and controls only the exact tmux window" \
  test_nvim_tmux_discovers_and_controls_exact_window
