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
  assert_eq "~/…/src/module" \
    "$(run_wspath "$TEST_TMPDIR/home/project/src/module")"
  assert_eq "~/project/src" "$(run_wspath "$TEST_TMPDIR/home/project/src")"
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
  [[ "$output" == 'project/'*'/…/foo/src' ]] || \
    fail "unexpected nested worktree shortening: $output"

  output="$(run_wspath "$TEST_TMPDIR/home/project/.worktrees/feature/a/b/src")"
  [[ "$output" == 'project/'*'/…/b/src' ]] || \
    fail "repository anchor changed at greater depth: $output"
}

test_similar_component_is_not_replaced() {
  local output

  mkdir -p "$TEST_TMPDIR/home"
  output="$(run_wspath "$TEST_TMPDIR/home/project/.worktrees-old/foo")"

  assert_eq "~/…/.worktrees-old/foo" "$output"
  assert_eq "~/…/.worktree/foo" \
    "$(run_wspath "$TEST_TMPDIR/home/project/.worktree/foo")"
}

setup_repo() {
  mkdir -p "$TEST_TMPDIR/home" "$TEST_TMPDIR/repo/a/b/src"
  git init -q "$TEST_TMPDIR/repo"
}

test_git_paths_anchor_at_root() {
  setup_repo

  assert_eq "repo" "$(run_wspath "$TEST_TMPDIR/repo")"
  assert_eq "repo/a" "$(run_wspath "$TEST_TMPDIR/repo/a")"
  assert_eq "repo/a/b" "$(run_wspath "$TEST_TMPDIR/repo/a/b")"
  assert_eq "repo/…/b/src" "$(run_wspath "$TEST_TMPDIR/repo/a/b/src")"
}

test_named_aliases_contract_before_shortening() {
  local repo

  setup_repo
  repo="$(cd "$TEST_TMPDIR/repo" && pwd -P)"
  printf 'hash -d code=%q\n' "${repo%/*}" >"$TEST_TMPDIR/home/.named-dirs.zsh"
  assert_eq "~code/repo" "$(run_wspath "$repo")"
  assert_eq "~code/repo/a" "$(run_wspath "$repo/a")"
  assert_eq "repo/a/b" "$(run_wspath "$repo/a/b")"
  assert_eq "repo/…/b/src" "$(run_wspath "$repo/a/b/src")"

  printf 'hash -d project=%q\n' "$repo" >"$TEST_TMPDIR/home/.named-dirs.zsh"
  assert_eq "~project" "$(run_wspath "$repo")"
  assert_eq "~project/a/b" "$(run_wspath "$repo/a/b")"
  assert_eq "~project/…/b/src" "$(run_wspath "$repo/a/b/src")"

  mkdir -p "$repo/a/b/c/d"
  printf 'hash -d src=%q\n' "$repo/a" >"$TEST_TMPDIR/home/.named-dirs.zsh"
  assert_eq "~src/b/c" "$(run_wspath "$repo/a/b/c")"
  assert_eq "~src/…/c/d" "$(run_wspath "$repo/a/b/c/d")"
}

test_short_home_and_named_git_paths_keep_context() {
  local repo

  mkdir -p "$TEST_TMPDIR/home/code"
  printf 'hash -d code="$HOME/code"\n' >"$TEST_TMPDIR/home/.named-dirs.zsh"
  for repo in rig autoplatform; do
    git init -q "$TEST_TMPDIR/home/code/$repo"
    assert_eq "~code/$repo" "$(run_wspath "$TEST_TMPDIR/home/code/$repo")"
  done

  git init -q "$TEST_TMPDIR/home/project"
  mkdir -p "$TEST_TMPDIR/home/project/src/module"
  assert_eq "~/project/src" "$(run_wspath "$TEST_TMPDIR/home/project/src")"
  assert_eq "project/src/module" \
    "$(run_wspath "$TEST_TMPDIR/home/project/src/module")"
}

test_worktree_examples_and_short_named_paths() {
  local output tree

  mkdir -p "$TEST_TMPDIR/home/code"
  printf 'hash -d code="$HOME/code"\nhash -d arrow="$HOME/code/arrow"\n' \
    >"$TEST_TMPDIR/home/.named-dirs.zsh"

  output="$(run_wspath "$TEST_TMPDIR/home/code/managed-platforms/.worktrees/my-feature")"
  assert_contains_tree "$output"
  tree="${output#managed-platforms/}"
  tree="${tree%/my-feature}"
  assert_eq "managed-platforms/$tree/my-feature" "$output"

  output="$(run_wspath "$TEST_TMPDIR/home/code/arrow/.worktrees/feat/BCOP-123/implement-the-thing/infra")"
  assert_contains_tree "$output"
  [[ "$output" == '~arrow/'*'/…/implement-the-thing/infra' ]] || \
    fail "unexpected named worktree shortening: $output"

  output="$(run_wspath "$TEST_TMPDIR/home/code/arrow/.worktrees/feat")"
  assert_contains_tree "$output"
  tree="${output#\~arrow/}"
  tree="${tree%/feat}"
  assert_eq "~arrow/$tree/feat" "$output"
  output="$(run_wspath "$TEST_TMPDIR/home/code/arrow/.worktrees")"
  assert_contains_tree "$output"
  [[ "$output" == '~arrow/'* && "$output" != *'.worktrees'* ]] || \
    fail "unexpected short named worktree path: $output"
}

test_worktree_shallow_paths_and_aliases() {
  local repo output tree

  setup_repo
  repo="$(cd "$TEST_TMPDIR/repo" && pwd -P)"
  git -C "$repo" -c user.name=Test -c user.email=test@example.invalid \
    -c commit.gpgsign=false commit -q --allow-empty -m fixture
  git -C "$repo" worktree add -q -b feature "$repo/.worktrees/feature"
  mkdir -p "$repo/.worktrees/feature/foo/src/a/b"
  output="$(run_wspath "$repo/.worktrees/feature")"
  assert_contains_tree "$output"
  tree="${output#repo/}"
  tree="${tree%/feature}"
  assert_eq "repo/$tree/feature" "$output"
  output="$(run_wspath "$repo/.worktrees/feature/foo")"
  [[ "$output" == repo/*/feature/foo && "$output" != *'…'* ]] || \
    fail "unexpected shallow worktree path: $output"

  printf 'hash -d project=%q\n' "$repo" >"$TEST_TMPDIR/home/.named-dirs.zsh"
  output="$(run_wspath "$repo/.worktrees/feature/foo/src")"
  assert_contains_tree "$output"
  [[ "$output" == '~project/'*'/…/foo/src' ]] || \
    fail "worktree did not preserve its contracted anchor: $output"

  printf 'hash -d src=%q\n' "$repo/.worktrees/feature/foo" \
    >"$TEST_TMPDIR/home/.named-dirs.zsh"
  assert_eq "~src/…/a/b" \
    "$(run_wspath "$repo/.worktrees/feature/foo/src/a/b")"
}

test_git_lookup_failure_keeps_fallback() {
  setup_repo
  mkdir -p "$TEST_TMPDIR/bin"
  printf '#!/bin/sh\nexit 127\n' >"$TEST_TMPDIR/bin/git"
  chmod +x "$TEST_TMPDIR/bin/git"
  assert_eq "/…/b/src" \
    "$(PATH="$TEST_TMPDIR/bin:$PATH" run_wspath "$TEST_TMPDIR/repo/a/b/src")"
}

test_case "wspath: ordinary paths keep existing shortening" \
  test_ordinary_paths_keep_existing_shortening
test_case "wspath: worktree path uses stable allowed tree" \
  test_worktree_path_uses_stable_allowed_tree
test_case "wspath: nested worktree path uses tree for shortening" \
  test_nested_worktree_path_uses_tree_for_shortening
test_case "wspath: similar component is not replaced" \
  test_similar_component_is_not_replaced
test_case "wspath: Git paths anchor at root" test_git_paths_anchor_at_root
test_case "wspath: named aliases contract before shortening" \
  test_named_aliases_contract_before_shortening
test_case "wspath: short home and named Git paths keep context" \
  test_short_home_and_named_git_paths_keep_context
test_case "wspath: worktree examples and short named paths" \
  test_worktree_examples_and_short_named_paths
test_case "wspath: shallow worktrees and named aliases" \
  test_worktree_shallow_paths_and_aliases
test_case "wspath: failed Git lookup keeps fallback" \
  test_git_lookup_failure_keeps_fallback
