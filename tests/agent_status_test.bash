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
fi
EOF
  chmod +x "$bin/tmux"
  printf '%s\n' "$bin"
}

owned_hook_count() {
  jq '[.hooks[][]?.hooks[]? | select((.command? // "") | startswith("$HOME/.zfuns/taw-agent-status "))] | length' "$1"
}

test_agent_status_sets_pane_options() {
  local bin log

  bin="$(make_status_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"
  TMUX=/tmp/tmux TMUX_PANE=%3 PATH="$bin" TAW_STATUS_TMUX_LOG="$log" \
    "$AGENT_STATUS" set codex thinking

  assert_file_contains "$log" 'set-option -p -t %3 @taw_agent codex'
  assert_file_contains "$log" 'set-option -p -t %3 @taw_agent_state thinking'
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

test_agent_status_config_creates_native_hooks() {
  local home codex claude

  home="$TEST_TMPDIR/home"
  codex="$home/.codex/hooks.json"
  claude="$home/.claude/settings.json"
  HOME="$home" bash "$AGENT_STATUS_CONFIG" config

  assert_eq 8 "$(jq '.hooks | length' "$codex")" "expected Codex lifecycle events"
  assert_eq 11 "$(jq '.hooks | length' "$claude")" "expected Claude lifecycle events"
  assert_eq 8 "$(owned_hook_count "$codex")" "expected Codex status handlers"
  assert_eq 11 "$(owned_hook_count "$claude")" "expected Claude status handlers"
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
      {"type": "command", "command": "$HOME/.zfuns/taw-agent-status set codex stale"}
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
test_case "agent status config: creates native hooks" test_agent_status_config_creates_native_hooks
test_case "agent status config: preserves unrelated settings" test_agent_status_config_preserves_unrelated_settings
test_case "agent status config: is idempotent" test_agent_status_config_is_idempotent
test_case "agent status config: refuses malformed JSON" test_agent_status_config_refuses_malformed_json
test_case "agent status config: preserves symlinks" test_agent_status_config_preserves_symlink
test_case "agent status config: prefers GNU stat syntax" \
  test_agent_status_config_prefers_gnu_stat_syntax
