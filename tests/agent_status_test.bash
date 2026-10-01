#!/usr/bin/env bash

. "$TESTS_DIR/lib/taw_test_helpers.bash"

AGENT_STATUS="$REPO_ROOT/home/.zfuns/taw-agent-status"
AGENT_STATUS_CONFIG="$REPO_ROOT/machine-tools/agent-status.sh"

make_status_tmux() {
  local root="$1"
  local bin="$root/bin"

  mkdir -p "$bin"
  ln -sf "$(command -v bash)" "$bin/bash"
  cat >"$bin/tmux" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >>"$TAW_STATUS_TMUX_LOG"
if [[ "${1:-}" = show-option ]]; then
  printf '%s\n' "${TAW_STATUS_EXISTING_STATE:-}"
elif [[ "${1:-}" = display-message ]]; then
  printf '1234\n'
fi
EOF
  chmod +x "$bin/tmux"
  printf '%s\n' "$bin"
}

owned_hook_count() {
  jq '[.hooks[][]?.hooks[]? | select((.command? // "") | startswith("\"$HOME/.zfuns/taw-agent-status\" "))] | length' "$1"
}

nvim_hook_count() {
  jq '[.hooks[][]?.hooks[]? | select((.command? // "") | startswith("\"$HOME/.zfuns/nvim-tmux\" "))] | length' "$1"
}

test_agent_status_sets_pane_options() {
  local bin log

  bin="$(make_status_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"
  TMUX=/tmp/tmux TMUX_PANE=%3 PATH="$bin" TAW_STATUS_TMUX_LOG="$log" \
    "$AGENT_STATUS" set codex thinking

  assert_file_contains "$log" 'set-option -p -t %3 @taw_agent codex'
  assert_file_contains "$log" 'set-option -p -t %3 @taw_agent_state thinking'
  assert_file_contains "$log" 'set-option -p -t %3 @taw_agent_pane_pid 1234'
}

test_agent_status_acknowledges_only_waiting() {
  local bin log

  bin="$(make_status_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"
  TMUX=/tmp/tmux PATH="$bin" TAW_STATUS_TMUX_LOG="$log" \
    TAW_STATUS_EXISTING_STATE=waiting "$AGENT_STATUS" acknowledge %7
  assert_file_contains "$log" 'set-option -p -t %7 @taw_agent_state acknowledged'

  : >"$log"
  TMUX=/tmp/tmux PATH="$bin" TAW_STATUS_TMUX_LOG="$log" \
    TAW_STATUS_EXISTING_STATE=thinking "$AGENT_STATUS" acknowledge %7
  assert_file_not_contains "$log" '@taw_agent_state acknowledged'
}

test_agent_status_clears_pane_options() {
  local bin log

  bin="$(make_status_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"
  TMUX=/tmp/tmux TMUX_PANE=%2 PATH="$bin" TAW_STATUS_TMUX_LOG="$log" \
    "$AGENT_STATUS" clear

  assert_file_contains "$log" 'set-option -pu -t %2 @taw_agent_state'
  assert_file_contains "$log" 'set-option -pu -t %2 @taw_agent'
  assert_file_contains "$log" 'set-option -pu -t %2 @taw_agent_pane_pid'
}

test_agent_status_is_quiet_without_tmux() {
  local bin output

  bin="$TEST_TMPDIR/bin"
  mkdir -p "$bin"
  ln -sf "$(command -v bash)" "$bin/bash"
  output="$(PATH="$bin" TMUX= TMUX_PANE= "$AGENT_STATUS" set claude idle 2>&1)"
  assert_eq "" "$output" "expected no-tmux status publication to be silent"

  output="$(PATH="$bin" TMUX=/tmp/tmux TMUX_PANE=%1 \
    "$AGENT_STATUS" set claude idle 2>&1)"
  assert_eq "" "$output" "expected unavailable tmux to be silent"
}

test_agent_status_rejects_invalid_arguments() {
  local output

  if output="$(TMUX= "$AGENT_STATUS" set gemini sleeping 2>&1)"; then
    fail "expected invalid agent status arguments to fail"
  fi
  assert_string_contains "$output" 'usage: taw-agent-status'
}

prepare_background_status() {
  BACKGROUND_HOME="$TEST_TMPDIR/home"
  BACKGROUND_CONFIG="$TEST_TMPDIR/claude config"
  BACKGROUND_BIN="$TEST_TMPDIR/bin"
  BACKGROUND_LOG="$TEST_TMPDIR/tmux.log"
  BACKGROUND_SESSION=aed5f56d-1391-4b34-8fa3-b7a9aa607dda
  mkdir -p "$BACKGROUND_CONFIG/sessions" "$BACKGROUND_BIN" "$BACKGROUND_HOME"
  : >"$BACKGROUND_LOG"
  cat >"$BACKGROUND_BIN/tmux" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$TAW_STATUS_TMUX_LOG"
if [[ "${1:-}" = -L ]]; then
  [[ "$2" = default ]] || exit 1
  shift 2
fi
if [[ "$1" = display-message ]]; then
  [[ "${TAW_BACKGROUND_NO_SERVER:-}" != 1 ]] || exit 1
  root=1234
  [[ "$4" != %8 ]] || root=2345
  root="${TAW_BACKGROUND_ROOT:-$root}"
  if [[ "$5" = '#{pane_pid}' ]]; then
    printf '%s\n' "${TAW_BACKGROUND_NEW_ROOT:-$root}"
  else
    printf '%s\t%s\t%s\t%s\t%s\n' "$4" "${TAW_BACKGROUND_WINDOW:-@4}" \
      "$root" "${TAW_BACKGROUND_AGENT:-claude}" "${TAW_BACKGROUND_SAVED_ROOT:-$root}"
    if [[ -n "${TAW_BACKGROUND_REPLACE_RECORD:-}" ]]; then
      printf '{}\n' >"$TAW_BACKGROUND_REPLACE_RECORD"
    fi
  fi
fi
EOF
  cat >"$BACKGROUND_BIN/ps" <<'EOF'
#!/usr/bin/env bash
case "$4" in
  lstart=)
    [[ "$TZ" = UTC && "$LC_ALL" = C ]] || exit 1
    [[ "${TAW_BACKGROUND_DEAD:-}" != 1 ]] || exit 1
    printf '  %s    \n' "${TAW_BACKGROUND_LSTART:-Thu Oct  1 19:26:43 2026}"
    ;;
  ppid=) printf '%s\n' "${TAW_BACKGROUND_PARENT:-1}" ;;
  *) exit 1 ;;
esac
EOF
  cat >"$BACKGROUND_BIN/uname" <<'EOF'
#!/usr/bin/env bash
printf 'Darwin\n'
EOF
  chmod +x "$BACKGROUND_BIN/tmux" "$BACKGROUND_BIN/ps" "$BACKGROUND_BIN/uname"
  write_background_record 1234 %7
}

write_background_record() {
  local pid="$1" pane="$2"

  jq -n --argjson pid "$pid" --arg pane "$pane" '{
    pid: $pid, kind: "interactive", pidDomain: "darwin",
    sessionId: "b666ce8b-aadb-45ec-8e51-95e5bc28e985", parkedJobId: "aed5f56d",
    tmux: ("project:@4." + $pane), procStart: "Thu Oct  1 19:26:43 2026"
  }' >"$BACKGROUND_CONFIG/sessions/$pid.json"
}

run_background_status() {
  local state="$1" payload="${2:-}" output

  [[ -n "$payload" ]] || payload="{\"session_id\":\"$BACKGROUND_SESSION\"}"
  output="$(HOME="$BACKGROUND_HOME" CLAUDE_CONFIG_DIR="$BACKGROUND_CONFIG" \
    TMUX= TMUX_PANE= PATH="$BACKGROUND_BIN:$PATH" TAW_STATUS_TMUX_LOG="$BACKGROUND_LOG" \
    "$AGENT_STATUS" hook claude "$state" <<<"$payload" 2>&1)" || fail "$output"
  assert_eq "" "$output" "expected quiet hook publication"
}

test_claude_hook_preserves_foreground_path() {
  local bin log

  bin="$(make_status_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"
  TMUX=/tmp/tmux TMUX_PANE=%3 PATH="$bin" TAW_STATUS_TMUX_LOG="$log" \
    "$AGENT_STATUS" hook claude idle </dev/null
  assert_file_contains "$log" 'set-option -p -t %3 @taw_agent_state idle'
  assert_file_not_contains "$log" '-L default'
}

test_claude_hook_routes_background_states() {
  local state

  prepare_background_status
  for state in idle thinking waiting; do
    : >"$BACKGROUND_LOG"
    run_background_status "$state"
    assert_file_contains "$BACKGROUND_LOG" "-L default set-option -p -t %7 @taw_agent_state $state"
  done
  assert_file_contains "$BACKGROUND_LOG" '-L default set-option -p -t %7 @taw_agent_pane_pid 1234'
}

test_claude_hook_routes_exact_session_and_descendant() {
  prepare_background_status
  BACKGROUND_SESSION=b666ce8b-aadb-45ec-8e51-95e5bc28e985
  TAW_BACKGROUND_ROOT=1111 TAW_BACKGROUND_PARENT=1111 run_background_status idle
  assert_file_contains "$BACKGROUND_LOG" '-L default set-option -p -t %7 @taw_agent_state idle'
  assert_file_contains "$BACKGROUND_LOG" '-L default set-option -p -t %7 @taw_agent_pane_pid 1111'
}

test_claude_hook_rejects_invalid_payloads() {
  local payload

  prepare_background_status
  for payload in '{broken' '{}' '[]' '{"session_id":"not-a-session"}' \
    "{\"session_id\":\"$BACKGROUND_SESSION\",\"agent_id\":\"agent-one\"}"; do
    run_background_status idle "$payload"
  done
  assert_file_not_contains "$BACKGROUND_LOG" 'set-option'
}

test_claude_hook_rejects_invalid_routes() {
  prepare_background_status
  TAW_BACKGROUND_LSTART=wrong run_background_status idle
  TAW_BACKGROUND_DEAD=1 run_background_status idle
  TAW_BACKGROUND_WINDOW=@9 run_background_status idle
  TAW_BACKGROUND_AGENT=codex run_background_status idle
  TAW_BACKGROUND_SAVED_ROOT=999 run_background_status idle
  TAW_BACKGROUND_ROOT=1111 run_background_status idle
  TAW_BACKGROUND_ROOT=1111 TAW_BACKGROUND_PARENT=1234 run_background_status idle
  TAW_BACKGROUND_NO_SERVER=1 run_background_status idle
  TAW_BACKGROUND_NEW_ROOT=999 run_background_status idle
  assert_file_not_contains "$BACKGROUND_LOG" 'set-option'
}

test_claude_hook_rejects_ambiguous_and_changed_records() {
  prepare_background_status
  write_background_record 2345 %8
  run_background_status idle
  assert_file_not_contains "$BACKGROUND_LOG" 'set-option'

  printf '{}\n' >"$BACKGROUND_CONFIG/sessions/2345.json"
  TAW_BACKGROUND_REPLACE_RECORD="$BACKGROUND_CONFIG/sessions/1234.json" \
    run_background_status idle
  assert_file_not_contains "$BACKGROUND_LOG" 'set-option'
}

test_claude_hook_handles_missing_and_malformed_records() {
  prepare_background_status
  printf '{broken\n' >"$BACKGROUND_CONFIG/sessions/1234.json"
  run_background_status idle
  mv "$BACKGROUND_CONFIG/sessions" "$BACKGROUND_CONFIG/old-sessions"
  run_background_status idle
  assert_file_not_contains "$BACKGROUND_LOG" 'set-option'
}

test_claude_hook_rejects_incompatible_records() {
  local filter record

  prepare_background_status
  record="$BACKGROUND_CONFIG/sessions/1234.json"
  for filter in '.pidDomain = "other"' '.kind = "bg"' '.pid = 999' \
    '.tmux = "project:%7"' '.procStart = null' '.parkedJobId = "other"'; do
    write_background_record 1234 %7
    jq "$filter" "$record" >"$TEST_TMPDIR/record.json"
    mv "$TEST_TMPDIR/record.json" "$record"
    run_background_status idle
  done
  assert_file_not_contains "$BACKGROUND_LOG" 'set-option'
}

test_claude_hook_default_config_and_missing_jq() {
  prepare_background_status
  mv "$BACKGROUND_CONFIG" "$BACKGROUND_HOME/.claude"
  HOME="$BACKGROUND_HOME" CLAUDE_CONFIG_DIR= TMUX= TMUX_PANE= \
    PATH="$BACKGROUND_BIN:$PATH" TAW_STATUS_TMUX_LOG="$BACKGROUND_LOG" \
    "$AGENT_STATUS" hook claude idle <<<"{\"session_id\":\"$BACKGROUND_SESSION\"}"
  assert_file_contains "$BACKGROUND_LOG" '-L default set-option -p -t %7 @taw_agent_state idle'

  : >"$BACKGROUND_LOG"
  ln -s "$(command -v bash)" "$BACKGROUND_BIN/bash"
  HOME="$BACKGROUND_HOME" TMUX= TMUX_PANE= PATH="$BACKGROUND_BIN" \
    TAW_STATUS_TMUX_LOG="$BACKGROUND_LOG" "$AGENT_STATUS" hook claude idle </dev/null
  assert_file_not_contains "$BACKGROUND_LOG" 'set-option'
}

test_agent_status_config_creates_native_hooks() {
  local home codex claude

  home="$TEST_TMPDIR/home"
  codex="$home/.codex/hooks.json"
  claude="$home/.claude/settings.json"
  HOME="$home" bash "$AGENT_STATUS_CONFIG" config

  assert_eq 8 "$(jq '.hooks | length' "$codex")" "expected Codex lifecycle events"
  assert_eq 11 "$(jq '.hooks | length' "$claude")" "expected Claude lifecycle events"
  assert_eq 8 "$(owned_hook_count "$codex")" "expected Codex status handlers"
  assert_eq 1 "$(nvim_hook_count "$codex")" "expected Codex Neovim context handler"
  assert_eq 11 "$(owned_hook_count "$claude")" "expected Claude status handlers"
  assert_eq 9 "$(jq '[.hooks[][]?.hooks[]? | select((.command // "") | contains("hook claude"))] | length' "$claude")" \
    "expected metadata-aware Claude state handlers"
  assert_eq '"$HOME/.zfuns/taw-agent-status" clear' \
    "$(jq -r '.hooks.SessionEnd[0].hooks[0].command' "$claude")" \
    "expected SessionEnd to retain foreground-only cleanup"
}

test_agent_status_config_preserves_unrelated_settings() {
  local home codex claude

  home="$TEST_TMPDIR/home"
  codex="$home/.codex/hooks.json"
  claude="$home/.claude/settings.json"
  mkdir -p "$(dirname "$codex")" "$(dirname "$claude")"
  cat >"$codex" <<'EOF'
{
  "description": "keep me",
  "hooks": {
    "Stop": [{"hooks": [
      {"type": "command", "command": "keep-this"},
      {"type": "command", "command": "$HOME/.zfuns/taw-agent-status set codex stale"},
      {"type": "command", "command": "$HOME/.zfuns/nvim-tmux clear-highlights"}
    ]}]
  }
}
EOF
  cat >"$claude" <<'EOF'
{"theme":"dark","permissions":{"allow":["Read"]}}
EOF

  HOME="$home" bash "$AGENT_STATUS_CONFIG" config

  assert_eq 'keep me' "$(jq -r '.description' "$codex")" "expected Codex metadata preserved"
  assert_eq 1 "$(jq '[.hooks.Stop[].hooks[] | select(.command == "keep-this")] | length' "$codex")" \
    "expected unrelated Codex hook preserved"
  assert_eq 0 "$(jq '[.hooks[][]?.hooks[]? | select(.command? == "$HOME/.zfuns/taw-agent-status set codex stale")] | length' "$codex")" \
    "expected stale owned hook replaced"
  assert_eq 1 "$(jq '[.hooks[][]?.hooks[]? | select(.command? == "$HOME/.zfuns/nvim-tmux clear-highlights")] | length' "$codex")" \
    "expected unrelated Neovim hook preserved"
  assert_eq dark "$(jq -r '.theme' "$claude")" "expected Claude theme preserved"
  assert_eq Read "$(jq -r '.permissions.allow[0]' "$claude")" \
    "expected Claude permissions preserved"
}

test_agent_status_config_is_idempotent() {
  local home codex before after

  home="$TEST_TMPDIR/home"
  codex="$home/.codex/hooks.json"
  HOME="$home" bash "$AGENT_STATUS_CONFIG" config
  before="$(cksum "$codex")"
  HOME="$home" bash "$AGENT_STATUS_CONFIG" config
  after="$(cksum "$codex")"

  assert_eq "$before" "$after" "expected repeated hook configuration to be stable"
  assert_eq 8 "$(owned_hook_count "$codex")" "expected no duplicate Codex handlers"
  assert_eq 1 "$(nvim_hook_count "$codex")" "expected no duplicate Neovim handlers"
}

test_agent_status_config_quotes_home_with_spaces() {
  local home codex bin log command nvim_command

  home="$TEST_TMPDIR/home with spaces"
  codex="$home/.codex/hooks.json"
  bin="$(make_status_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"
  mkdir -p "$home/.zfuns"
  ln -s "$AGENT_STATUS" "$home/.zfuns/taw-agent-status"
  ln -s "$REPO_ROOT/home/.zfuns/nvim-tmux" "$home/.zfuns/nvim-tmux"

  HOME="$home" bash "$AGENT_STATUS_CONFIG" config
  command="$(jq -r '.hooks.SessionStart[0].hooks[0].command' "$codex")"
  HOME="$home" TMUX=/tmp/tmux TMUX_PANE=%4 PATH="$bin" \
    TAW_STATUS_TMUX_LOG="$log" bash -c "$command"

  assert_file_contains "$log" 'set-option -p -t %4 @taw_agent codex'
  assert_file_contains "$log" 'set-option -p -t %4 @taw_agent_state idle'

  nvim_command="$(jq -r '.hooks.SessionStart[0].hooks[] | select(.command | contains("nvim-tmux")) | .command' "$codex")"
  HOME="$home" TMUX= bash -c "$nvim_command"
}

test_agent_status_config_refuses_malformed_json() {
  local home codex before output

  home="$TEST_TMPDIR/home"
  codex="$home/.codex/hooks.json"
  mkdir -p "$(dirname "$codex")"
  printf '{broken\n' >"$codex"
  before="$(cat "$codex")"

  if output="$(HOME="$home" bash "$AGENT_STATUS_CONFIG" config 2>&1)"; then
    fail "expected malformed Codex hooks to fail"
  fi
  assert_string_contains "$output" 'refusing malformed JSON'
  assert_eq "$before" "$(cat "$codex")" "expected malformed config left untouched"
  assert_not_exists "$home/.claude/settings.json"
}

test_agent_status_config_preserves_symlink() {
  local home target link

  home="$TEST_TMPDIR/home"
  target="$TEST_TMPDIR/codex-hooks.json"
  link="$home/.codex/hooks.json"
  mkdir -p "$(dirname "$link")"
  printf '{}\n' >"$target"
  ln -s "$target" "$link"

  HOME="$home" bash "$AGENT_STATUS_CONFIG" config

  assert_symlink_to "$link" "$target"
  assert_eq 8 "$(owned_hook_count "$target")" "expected symlink target updated"
}

test_agent_status_config_prefers_gnu_stat_syntax() {
  local home bin stat_log

  home="$TEST_TMPDIR/home"
  bin="$TEST_TMPDIR/bin"
  stat_log="$TEST_TMPDIR/stat.log"
  mkdir -p "$home/.codex" "$home/.claude" "$bin"
  printf '{}\n' >"$home/.codex/hooks.json"
  printf '{}\n' >"$home/.claude/settings.json"
  cat >"$bin/stat" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >>"$TAW_STATUS_STAT_LOG"
case "${1:-}" in
  -c) printf '600\n' ;;
  -f) printf 'unexpected filesystem report\n' ;;
  *) exit 1 ;;
esac
EOF
  chmod +x "$bin/stat"

  HOME="$home" PATH="$bin:$PATH" TAW_STATUS_STAT_LOG="$stat_log" \
    bash "$AGENT_STATUS_CONFIG" config

  assert_file_contains "$stat_log" '-c %a'
  assert_file_not_contains "$stat_log" '-f %Lp'
}

test_case "agent status: sets pane options" test_agent_status_sets_pane_options
test_case "agent status: acknowledges only waiting panes" test_agent_status_acknowledges_only_waiting
test_case "agent status: clears pane options" test_agent_status_clears_pane_options
test_case "agent status: is quiet without tmux" test_agent_status_is_quiet_without_tmux
test_case "agent status: rejects invalid arguments" test_agent_status_rejects_invalid_arguments
test_case "Claude hook: preserves foreground publication" test_claude_hook_preserves_foreground_path
test_case "Claude hook: routes background states" test_claude_hook_routes_background_states
test_case "Claude hook: routes exact session and descendant" test_claude_hook_routes_exact_session_and_descendant
test_case "Claude hook: rejects invalid payloads" test_claude_hook_rejects_invalid_payloads
test_case "Claude hook: rejects invalid routes" test_claude_hook_rejects_invalid_routes
test_case "Claude hook: rejects ambiguous and changed records" test_claude_hook_rejects_ambiguous_and_changed_records
test_case "Claude hook: handles missing and malformed records" test_claude_hook_handles_missing_and_malformed_records
test_case "Claude hook: rejects incompatible records" test_claude_hook_rejects_incompatible_records
test_case "Claude hook: default config and missing jq" test_claude_hook_default_config_and_missing_jq
test_case "agent status config: creates native hooks" test_agent_status_config_creates_native_hooks
test_case "agent status config: preserves unrelated settings" test_agent_status_config_preserves_unrelated_settings
test_case "agent status config: is idempotent" test_agent_status_config_is_idempotent
test_case "agent status config: quotes HOME paths containing spaces" \
  test_agent_status_config_quotes_home_with_spaces
test_case "agent status config: refuses malformed JSON" test_agent_status_config_refuses_malformed_json
test_case "agent status config: preserves symlinks" test_agent_status_config_preserves_symlink
test_case "agent status config: prefers GNU stat syntax" \
  test_agent_status_config_prefers_gnu_stat_syntax
