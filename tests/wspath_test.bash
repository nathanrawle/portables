run_wspath() {
  HOME="$TEST_TMPDIR/home" zsh "$REPO_ROOT/home/.config/tmux/wspath" "$1"
}

assert_contains_tree() {
  local output="$1"

  case "$output" in
    *🌲*|*🌳*|*🌴*|*🪾*|*🎄*|*🎋*) ;;
    *) fail "expected an allowed tree in output: $output" ;;
  esac
}

test_ordinary_paths_keep_existing_shortening() {
  mkdir -p "$TEST_TMPDIR/home"

  assert_eq "/project/src" \
    "$(run_wspath "/project/src")"
  assert_eq "/…/src/module" \
    "$(run_wspath "$TEST_TMPDIR/home/project/src/module")"
}

test_worktree_path_uses_stable_allowed_tree() {
  local input first second

  mkdir -p "$TEST_TMPDIR/home"
  input="$TEST_TMPDIR/home/project/.worktrees/develop"
  first="$(run_wspath "$input")"
  second="$(run_wspath "$input")"

  assert_eq "$first" "$second" "expected the tree to be stable for a path"
  assert_contains_tree "$first"
  [[ "$first" != *'.worktrees'* ]] || fail "worktree component was not replaced: $first"
}

test_nested_worktree_path_uses_tree_for_shortening() {
  local output

  mkdir -p "$TEST_TMPDIR/home"
  output="$(run_wspath "$TEST_TMPDIR/home/project/.worktrees/feature/foo/src")"

  assert_contains_tree "$output"
  [[ "$output" == '/'*'/foo/src' ]] || \
    fail "unexpected nested worktree shortening: $output"
  [[ "$output" != *'…'* ]] || fail "worktree path retained the ellipsis: $output"
}

test_similar_component_is_not_replaced() {
  local output

  mkdir -p "$TEST_TMPDIR/home"
  output="$(run_wspath "$TEST_TMPDIR/home/project/.worktrees-old/foo")"

  assert_eq "/…/.worktrees-old/foo" "$output"
}

test_case "wspath: ordinary paths keep existing shortening" \
  test_ordinary_paths_keep_existing_shortening
test_case "wspath: worktree path uses stable allowed tree" \
  test_worktree_path_uses_stable_allowed_tree
test_case "wspath: nested worktree path uses tree for shortening" \
  test_nested_worktree_path_uses_tree_for_shortening
test_case "wspath: similar component is not replaced" \
  test_similar_component_is_not_replaced
