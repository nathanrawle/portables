#!/usr/bin/env bash

. "$TESTS_DIR/lib/taw_test_helpers.bash"

test_git_fixture_copies_are_independent() {
  local first second slash_branch prefix nested prefix_copy

  first="$TEST_TMPDIR/first"
  second="$TEST_TMPDIR/second"
  slash_branch="$TEST_TMPDIR/slash-branch"
  prefix="$TEST_TMPDIR/prefix"
  nested="$TEST_TMPDIR/nested"
  prefix_copy="$TEST_TMPDIR/prefix-copy"

  make_git_repo "$first"
  printf 'changed\n' >"$first/README.md"
  make_git_repo "$second"

  assert_file_contents "$second/README.md" main
  assert_eq '' "$(git -C "$second" status --porcelain)" \
    "expected a clean independent fixture copy"

  make_git_repo "$slash_branch" docs/feature
  assert_eq docs/feature "$(git -C "$slash_branch" branch --show-current)" \
    "expected slash branch fixture caching"

  make_git_repo "$prefix" topic
  make_git_repo "$nested" topic/child
  make_git_repo "$prefix_copy" topic
  assert_not_exists "$prefix_copy/child"
  assert_eq topic/child "$(git -C "$nested" branch --show-current)" \
    "expected prefix branch fixtures to remain independent"
}

test_case 'taw helpers: Git fixture copies are clean and independent' \
  test_git_fixture_copies_are_independent
