#!/usr/bin/env bash

. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/lib/harness.bash"

skill_fixture() {
  local skill_root="$TEST_TMPDIR/skill"
  mkdir -p "$skill_root/scripts" "$TEST_TMPDIR/bin"
  cp "$REPO_ROOT/home/.agent-generics/skills/pr-review-followup-loop/scripts/pr-review-state.sh" \
    "$skill_root/scripts/"
  printf '%s\n' "$skill_root"
}

test_pr_review_state_reports_only_compact_current_head_state() {
  local skill_root output bot_login
  skill_root="$(skill_fixture)"
  cat >"$TEST_TMPDIR/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$TRACE"
if [[ "$1" == api ]]; then
  query="${!#}"
  expected=".user.login == \"$EXPECTED_BOT\" or .user.login == \"$EXPECTED_BOT[bot]\""
  [[ "$query" == *"$expected"* ]] || {
    printf 'query does not match both exact bot logins: %s\n' "$query" >&2
    exit 1
  }
fi
case "$*" in
  'pr view 17 '*) printf 'abc123\tfalse\tOPEN\thttps://example.test/pull/17\n' ;;
  *'issues/comments/99/reactions'*) printf 'EYES\n' ;;
  *'pulls/17/reviews'*) printf 'COMMENTED\tabc123\t2026-09-27T10:01:00Z\thttps://example.test/review/1\n' ;;
  *'issues/17/comments?since='*) printf '72\t2026-09-27T10:02:00Z\thttps://example.test/comment/72\n' ;;
  *) printf 'unexpected gh invocation: %s\n' "$*" >&2; exit 1 ;;
esac
EOF
  chmod +x "$TEST_TMPDIR/bin/gh"
  for bot_login in chatgpt-codex-connector 'chatgpt-codex-connector[bot]' custom-reviewer; do
    output="$(TRACE="$TEST_TMPDIR/trace" EXPECTED_BOT="${bot_login%\[bot\]}" \
      PATH="$TEST_TMPDIR/bin:$PATH" \
      "$skill_root/scripts/pr-review-state.sh" --pr 17 --bot "$bot_login" \
      --since 2026-09-27T10:00:00Z --reaction-target comment --comment-id 99)"
    assert_eq $'pr\t17\nhead\tabc123\ndraft\tfalse\nstate\tOPEN\nurl\thttps://example.test/pull/17\ntarget\tcomment\ncomment-id\t99\nreaction\tEYES\nreview\tCOMMENTED\tabc123\t2026-09-27T10:01:00Z\thttps://example.test/review/1\ncomment\t72\t2026-09-27T10:02:00Z\thttps://example.test/comment/72' \
      "$output"
  done
  grep -q 'issues/comments/99/reactions' "$TEST_TMPDIR/trace" || fail 'comment reaction target not queried'
  grep -q 'issues/17/comments?since=2026-09-27T10:00:00Z' "$TEST_TMPDIR/trace" ||
    fail 'comments were not bounded by request time'
  grep -q 'created_at >= "2026-09-27T10:00:00Z"' "$TEST_TMPDIR/trace" ||
    fail 'reactions were not bounded by request time'
  grep -q 'submitted_at >= "2026-09-27T10:00:00Z"' "$TEST_TMPDIR/trace" ||
    fail 'reviews were not bounded by request time'
  grep -q 'commit_id == "abc123"' "$TEST_TMPDIR/trace" ||
    fail 'reviews were not bounded by current head'
}

test_pr_review_state_rejects_malformed_bot_logins() {
  local skill_root bot_login status
  skill_root="$(skill_fixture)"
  for bot_login in '[bot]' 'reviewer[bot][bot]' 'reviewer[other]' 'reviewer[bot]extra'; do
    status=0
    "$skill_root/scripts/pr-review-state.sh" --pr 17 --bot "$bot_login" \
      --since 2026-09-27T10:00:00Z --reaction-target pr \
      >"$TEST_TMPDIR/output" 2>&1 || status=$?
    assert_eq 2 "$status" "malformed bot login accepted: $bot_login"
  done
}

test_pr_review_state_rejects_invalid_reaction_target() {
  local skill_root
  skill_root="$(skill_fixture)"
  if "$skill_root/scripts/pr-review-state.sh" --pr 17 --bot chatgpt-codex-connector \
    --since 2026-09-27T10:00:00Z --reaction-target comment; then
    fail 'missing comment ID accepted'
  fi
}

test_pr_review_state_queries_pr_body_for_automatic_reviews() {
  local skill_root output
  skill_root="$(skill_fixture)"
  cat >"$TEST_TMPDIR/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$TRACE"
case "$*" in
  'pr view 17 '*) printf 'abc123\tfalse\tOPEN\thttps://example.test/pull/17\n' ;;
  *'issues/17/reactions'*|*'pulls/17/reviews'*|*'issues/17/comments?since='*) ;;
  *) printf 'unexpected gh invocation: %s\n' "$*" >&2; exit 1 ;;
esac
EOF
  chmod +x "$TEST_TMPDIR/bin/gh"
  output="$(TRACE="$TEST_TMPDIR/trace" PATH="$TEST_TMPDIR/bin:$PATH" \
    "$skill_root/scripts/pr-review-state.sh" --pr 17 --bot chatgpt-codex-connector \
    --since 2026-09-27T10:00:00Z --reaction-target pr)"
  assert_eq $'pr\t17\nhead\tabc123\ndraft\tfalse\nstate\tOPEN\nurl\thttps://example.test/pull/17\ntarget\tpr' "$output"
  grep -q 'issues/17/reactions' "$TEST_TMPDIR/trace" || fail 'PR reaction target not queried'
}

test_case 'pr review skill: compact state follows the tracked request' test_pr_review_state_reports_only_compact_current_head_state
test_case 'pr review skill: malformed bot logins are rejected' test_pr_review_state_rejects_malformed_bot_logins
test_case 'pr review skill: tracked comments require an ID' test_pr_review_state_rejects_invalid_reaction_target
test_case 'pr review skill: automatic reviews track the PR body' test_pr_review_state_queries_pr_body_for_automatic_reviews

finish_tests
