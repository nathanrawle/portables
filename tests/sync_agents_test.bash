#!/usr/bin/env bash

make_sync_agents_fixture() {
  local fixture_root="$1"
  local repo="$fixture_root/repo"

  mkdir -p "$repo/home/.claude/agents" "$repo/home/.codex/agents"
  repo="$(cd "$repo" && pwd -P)" || return 1
  cp "$REPO_ROOT/sync-agents" "$repo/"
  printf 'sandbox_mode = "workspace-write"\n\n' >"$repo/home/.codex/config.toml"
  printf '%s\n' "$repo"
}

run_sync_agents() {
  local repo="$1"
  shift

  python3 "$repo/sync-agents" --root "$repo" "$@"
}

assert_file_contains() {
  local path="$1"
  local expected="$2"

  [[ -f "$path" ]] || fail "expected file: $path"
  grep -Fq "$expected" "$path" || fail "expected $path to contain: $expected"
}

assert_output_contains() {
  local output="$1"
  local expected="$2"

  [[ "$output" == *"$expected"* ]] || fail "expected output to contain: $expected"
}

test_claude_only_converts_to_codex_and_registers() {
  local repo

  repo="$(make_sync_agents_fixture "$TEST_TMPDIR")"
  cat >"$repo/home/.claude/agents/researcher.md" <<'EOF'
---
name: 'Researcher'
description: 'Reads source files'
model: sonnet
tools: ['Read', 'Glob', 'Grep']
---

# Researcher

Read the repository.
EOF

  run_sync_agents "$repo" >/dev/null

  assert_exists "$repo/home/.codex/agents/researcher.toml"
  assert_file_contains "$repo/home/.codex/agents/researcher.toml" 'name = "Researcher"'
  assert_file_contains "$repo/home/.codex/agents/researcher.toml" 'model = "gpt-5.4-mini"'
  assert_file_contains "$repo/home/.codex/agents/researcher.toml" 'model_reasoning_effort = "high"'
  assert_file_contains "$repo/home/.codex/agents/researcher.toml" 'sandbox_mode = "read-only"'
  assert_file_contains "$repo/home/.codex/agents/researcher.toml" '# Researcher'
  assert_file_contains "$repo/home/.codex/config.toml" '[agents.researcher]'
  assert_file_contains "$repo/home/.codex/config.toml" 'config_file = "./agents/researcher.toml"'
}

test_codex_only_converts_to_claude() {
  local repo

  repo="$(make_sync_agents_fixture "$TEST_TMPDIR")"
  cat >"$repo/home/.codex/agents/writer.toml" <<'EOF'
name = "Writer"
description = "Writes docs"
model = "gpt-5.4-mini"
model_reasoning_effort = "medium"
sandbox_mode = "workspace-write"
developer_instructions = "# Writer\n\nWrite carefully.\n"
EOF

  run_sync_agents "$repo" >/dev/null

  assert_exists "$repo/home/.claude/agents/writer.md"
  assert_file_contains "$repo/home/.claude/agents/writer.md" 'name: "Writer"'
  assert_file_contains "$repo/home/.claude/agents/writer.md" 'model: haiku'
  assert_file_contains "$repo/home/.claude/agents/writer.md" '"Edit"'
  assert_file_contains "$repo/home/.claude/agents/writer.md" '# Writer'
  assert_file_contains "$repo/home/.codex/config.toml" '[agents.writer]'
}

test_agent_suffix_normalization_matches_existing_counterpart() {
  local repo

  repo="$(make_sync_agents_fixture "$TEST_TMPDIR")"
  cat >"$repo/home/.claude/agents/se-review.agent.md" <<'EOF'
---
name: 'Review'
description: 'Review code'
model: opus
tools: ['Read']
---

Review.
EOF
  cat >"$repo/home/.codex/agents/se-review.toml" <<'EOF'
name = "Existing Review"
description = "Already present"
model_reasoning_effort = "xhigh"
sandbox_mode = "read-only"
developer_instructions = "Existing.\n"
EOF

  run_sync_agents "$repo" >/dev/null

  assert_not_exists "$repo/home/.codex/agents/se-review.agent.toml"
  assert_file_contains "$repo/home/.codex/agents/se-review.toml" 'Existing Review'
  assert_file_contains "$repo/home/.codex/config.toml" '[agents.se-review]'
}

test_existing_counterpart_is_not_overwritten() {
  local repo

  repo="$(make_sync_agents_fixture "$TEST_TMPDIR")"
  cat >"$repo/home/.claude/agents/reviewer.md" <<'EOF'
---
name: 'Reviewer'
description: 'New source'
model: opus
tools: ['Read', 'Edit']
---

New content.
EOF
  printf 'original codex\n' >"$repo/home/.codex/agents/reviewer.toml"

  run_sync_agents "$repo" >/dev/null

  assert_file_contents "$repo/home/.codex/agents/reviewer.toml" "original codex"
}

test_dry_run_prints_without_writing() {
  local repo output

  repo="$(make_sync_agents_fixture "$TEST_TMPDIR")"
  cat >"$repo/home/.claude/agents/dry.md" <<'EOF'
---
name: 'Dry'
description: 'Dry run'
model: haiku
tools: ['Read']
---

Dry.
EOF

  output="$(run_sync_agents "$repo" --dry-run)"

  assert_output_contains "$output" "create codex $repo/home/.codex/agents/dry.toml"
  assert_output_contains "$output" "register codex dry"
  assert_not_exists "$repo/home/.codex/agents/dry.toml"
  [[ "$(grep -c 'agents.dry' "$repo/home/.codex/config.toml" || true)" == "0" ]] || \
    fail "dry run changed config"
}

test_check_reports_drift_and_exits_nonzero() {
  local repo output rc

  repo="$(make_sync_agents_fixture "$TEST_TMPDIR")"
  cat >"$repo/home/.claude/agents/checker.md" <<'EOF'
---
name: 'Checker'
description: 'Check mode'
model: sonnet
tools: ['Read']
---

Check.
EOF

  set +e
  output="$(run_sync_agents "$repo" --check 2>&1)"
  rc=$?
  set -e

  assert_eq "1" "$rc" "check should report drift"
  assert_output_contains "$output" "create codex $repo/home/.codex/agents/checker.toml"
  assert_not_exists "$repo/home/.codex/agents/checker.toml"
}

test_registration_entries_are_sorted_after_agents_block() {
  local repo config

  repo="$(make_sync_agents_fixture "$TEST_TMPDIR")"
  cat >"$repo/home/.codex/config.toml" <<'EOF'
sandbox_mode = "workspace-write"

[agents.zed]
config_file = "./agents/zed.toml"

[profiles.safe-readonly]
sandbox_mode = "read-only"
EOF
  printf 'name = "Alpha"\ndescription = ""\nmodel_reasoning_effort = "high"\ndeveloper_instructions = ""\n' \
    >"$repo/home/.codex/agents/alpha.toml"
  printf 'name = "Beta"\ndescription = ""\nmodel_reasoning_effort = "high"\ndeveloper_instructions = ""\n' \
    >"$repo/home/.codex/agents/beta.toml"

  run_sync_agents "$repo" >/dev/null

  config="$(cat "$repo/home/.codex/config.toml")"
  [[ "$config" == *$'[agents.zed]\nconfig_file = "./agents/zed.toml"\n\n[agents.alpha]\nconfig_file = "./agents/alpha.toml"\n\n[agents.beta]\nconfig_file = "./agents/beta.toml"\n\n[profiles.safe-readonly]'* ]] || \
    fail "registrations were not inserted sorted after agents block"
}

test_case "sync-agents: Claude-only converts to Codex and registers" \
  test_claude_only_converts_to_codex_and_registers
test_case "sync-agents: Codex-only converts to Claude" \
  test_codex_only_converts_to_claude
test_case "sync-agents: .agent.md suffix normalization matches existing counterpart" \
  test_agent_suffix_normalization_matches_existing_counterpart
test_case "sync-agents: existing counterpart is not overwritten" \
  test_existing_counterpart_is_not_overwritten
test_case "sync-agents: dry-run prints without writing" \
  test_dry_run_prints_without_writing
test_case "sync-agents: check reports drift and exits nonzero" \
  test_check_reports_drift_and_exits_nonzero
test_case "sync-agents: registration entries are sorted after agents block" \
  test_registration_entries_are_sorted_after_agents_block
