#!/usr/bin/env bash

assert_file_contains() {
  local path="$1"
  local expected="$2"

  [[ -f "$path" ]] || fail "expected file: $path"
  grep -F -- "$expected" "$path" >/dev/null ||
    fail "expected $path to contain: $expected"
}

assert_file_not_contains() {
  local path="$1"
  local unexpected="$2"

  [[ -f "$path" ]] || fail "expected file: $path"
  if grep -F -- "$unexpected" "$path" >/dev/null; then
    fail "expected $path not to contain: $unexpected"
  fi
}

make_fake_tmux() {
  local root="$1"
  local bin="$root/bin"

  mkdir -p "$bin"
  cat >"$bin/tmux" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

: "${TAW_TMUX_LOG:?}"

{
  first=1
  for arg in "$@"; do
    if [[ $first -eq 1 ]]; then
      printf '%s' "$arg"
      first=0
    else
      printf '\t%s' "$arg"
    fi
  done
  printf '\n'
} >>"$TAW_TMUX_LOG"

case "${1:-}" in
  has-session)
    if [[ "${TAW_FAKE_TMUX_HAS_SESSION:-0}" = 1 ]]; then
      exit 0
    fi
    exit 1
    ;;
  list-sessions)
    [[ -n "${TAW_FAKE_TMUX_SESSIONS+x}" ]] || exit 1
    printf '%b' "$TAW_FAKE_TMUX_SESSIONS"
    [[ "$TAW_FAKE_TMUX_SESSIONS" = *$'\n' ]] || printf '\n'
    ;;
  new-session|new-window)
    printf '@1 %%1\n'
    ;;
  split-window)
    count_file="${TAW_TMUX_COUNT_FILE:-$TAW_TMUX_LOG.count}"
    count=1
    if [[ -f "$count_file" ]]; then
      count="$(<"$count_file")"
    fi
    count=$((count + 1))
    printf '%s\n' "$count" >"$count_file"
    printf '%%%d\n' "$count"
    ;;
esac
EOF
  chmod +x "$bin/tmux"
  printf '%s\n' "$bin"
}

make_git_repo() {
  local repo="$1"
  local primary_branch="${2:-main}"

  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" config user.email "taw@example.invalid"
  git -C "$repo" config user.name "taw test"
  printf '%s\n' "$primary_branch" >"$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" commit -qm "initial commit"
  git -C "$repo" branch -M "$primary_branch"
  git -C "$repo" checkout -qb develop
  printf 'develop\n' >"$repo/develop.txt"
  git -C "$repo" add develop.txt
  git -C "$repo" commit -qm "develop commit"
  git -C "$repo" checkout -q "$primary_branch"
}

make_bare_wrapper() {
  local root="$1"
  local bare_name="${2:-.git}"
  local primary_branch="${3:-main}"
  local src="$root/src"
  local project="$root/project"

  make_git_repo "$src" "$primary_branch"
  mkdir -p "$project"
  git clone --bare "$src" "$project/$bare_name" >/dev/null 2>&1
  printf '%s\n' "$project"
}

run_taw() {
  local cwd="$1"
  shift

  (
    cd "$cwd" || exit 1
    TAW_FUNC_DIR="$REPO_ROOT/home/.zfuns" \
      PATH="$TAW_FAKE_TMUX_BIN:$PATH" \
      TMUX= \
      zsh -fc 'fpath=("$TAW_FUNC_DIR" $fpath); autoload -U taw; taw "$@"' taw "$@"
  )
}

test_layout_with_overrides_and_shell_panes() {
  local repo repo_real fake_bin log

  repo="$TEST_TMPDIR/repo"
  make_git_repo "$repo"
  repo_real="$(cd "$repo" && pwd -P)"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"

  TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$repo" -p "$repo" -agent "claude --resume" -ed "nvim ." -sh -sh "npm test"

  assert_file_contains "$log" $'has-session\t-t\trepo'
  assert_file_contains "$log" $'new-session\t-d\t-P\t-F\t#{window_id} #{pane_id}\t-s\trepo\t-n\trepo\t-c\t'"$repo_real"$'\tnvim .'
  assert_file_contains "$log" $'set-window-option\t-t\t@1\tautomatic-rename\toff'
  assert_file_contains "$log" $'rename-window\t-t\t@1\trepo'
  assert_file_contains "$log" $'split-window\t-h\t-P\t-F\t#{pane_id}\t-t\t%1\t-c\t'"$repo_real"$'\tclaude --resume'
  assert_file_contains "$log" $'split-window\t-v\t-P\t-F\t#{pane_id}\t-t\t%2\t-c\t'"$repo_real"
  assert_file_contains "$log" $'split-window\t-h\t-P\t-F\t#{pane_id}\t-t\t%3\t-c\t'"$repo_real"$'\tnpm test'
  assert_file_not_contains "$log" $'send-keys\t'
  assert_file_contains "$log" $'select-window\t-t\t@1'
  assert_file_contains "$log" $'attach-session\t-t\trepo'
}

test_existing_session_adds_window_and_selects_it_before_attach() {
  local repo repo_real fake_bin log

  repo="$TEST_TMPDIR/repo"
  make_git_repo "$repo"
  repo_real="$(cd "$repo" && pwd -P)"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"

  EDITOR=vim TAW_FAKE_TMUX_HAS_SESSION=1 TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$repo" -p "$repo"

  assert_file_contains "$log" $'has-session\t-t\trepo'
  assert_file_contains "$log" $'new-window\t-d\t-P\t-F\t#{window_id} #{pane_id}\t-t\trepo:\t-n\trepo\t-c\t'"$repo_real"$'\tvim'
  assert_file_contains "$log" $'set-window-option\t-t\t@1\tautomatic-rename\toff'
  assert_file_contains "$log" $'rename-window\t-t\t@1\trepo'
  assert_file_contains "$log" $'select-window\t-t\t@1'
  assert_file_contains "$log" $'attach-session\t-t\trepo'
}

test_named_branch_checks_out_normal_repo() {
  local repo repo_real fake_bin log branch

  repo="$TEST_TMPDIR/repo"
  make_git_repo "$repo"
  repo_real="$(cd "$repo" && pwd -P)"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"

  EDITOR="vim -u NONE" TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$repo" -p "$repo" -b develop

  branch="$(git -C "$repo" branch --show-current)"
  assert_eq "develop" "$branch" "expected named branch checkout"
  assert_file_contains "$log" $'new-session\t-d\t-P\t-F\t#{window_id} #{pane_id}\t-s\trepo\t-n\trepo\t-c\t'"$repo_real"$'\tvim -u NONE'
  assert_file_contains "$log" $'rename-window\t-t\t@1\trepo'
  assert_file_contains "$log" $'split-window\t-h\t-P\t-F\t#{pane_id}\t-t\t%1\t-c\t'"$repo_real"$'\tcodex'
  assert_file_not_contains "$log" $'send-keys\t'
}

test_project_arg_resolves_from_projects_home() {
  local projects_home repo repo_real fake_bin log

  projects_home="$TEST_TMPDIR/projects"
  repo="$projects_home/foo"
  make_git_repo "$repo"
  repo_real="$(cd "$repo" && pwd -P)"
  mkdir -p "$TEST_TMPDIR/elsewhere"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"

  PROJECTS_HOME="$projects_home" EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$TEST_TMPDIR/elsewhere" -p foo

  assert_file_contains "$log" $'new-session\t-d\t-P\t-F\t#{window_id} #{pane_id}\t-s\tfoo\t-n\tfoo\t-c\t'"$repo_real"$'\tvim'
  assert_file_not_contains "$log" $'list-sessions\t'
}

test_project_arg_direct_path_precedes_projects_home() {
  local projects_home direct_repo projects_repo direct_real projects_real fake_bin log

  projects_home="$TEST_TMPDIR/projects"
  direct_repo="$TEST_TMPDIR/current/foo"
  projects_repo="$projects_home/foo"
  make_git_repo "$direct_repo"
  make_git_repo "$projects_repo"
  direct_real="$(cd "$direct_repo" && pwd -P)"
  projects_real="$(cd "$projects_repo" && pwd -P)"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"

  PROJECTS_HOME="$projects_home" EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$TEST_TMPDIR/current" -p foo

  assert_file_contains "$log" $'-c\t'"$direct_real"$'\tvim'
  assert_file_not_contains "$log" $'-c\t'"$projects_real"$'\tvim'
}

test_project_arg_resolves_by_tmux_session_name() {
  local repo repo_real fake_bin log sessions

  repo="$TEST_TMPDIR/session-repo"
  make_git_repo "$repo"
  repo_real="$(cd "$repo" && pwd -P)"
  mkdir -p "$TEST_TMPDIR/elsewhere"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"
  sessions=$'agent\t'"$repo_real"$'\n'

  EDITOR=vim TAW_FAKE_TMUX_HAS_SESSION=1 TAW_FAKE_TMUX_SESSIONS="$sessions" \
    TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$TEST_TMPDIR/elsewhere" -p agent

  assert_file_contains "$log" $'list-sessions\t-F\t#{session_name}\t#{session_path}'
  assert_file_contains "$log" $'has-session\t-t\tagent'
  assert_file_contains "$log" $'new-window\t-d\t-P\t-F\t#{window_id} #{pane_id}\t-t\tagent:\t-n\tsession-repo\t-c\t'"$repo_real"$'\tvim'
  assert_file_contains "$log" $'rename-window\t-t\t@1\tsession-repo'
}

test_project_arg_resolves_by_tmux_session_path_basename() {
  local repo repo_real fake_bin log sessions

  repo="$TEST_TMPDIR/path-match"
  make_git_repo "$repo"
  repo_real="$(cd "$repo" && pwd -P)"
  mkdir -p "$TEST_TMPDIR/elsewhere"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"
  sessions=$'alpha\t'"$repo_real"$'\n'

  EDITOR=vim TAW_FAKE_TMUX_HAS_SESSION=1 TAW_FAKE_TMUX_SESSIONS="$sessions" \
    TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$TEST_TMPDIR/elsewhere" -p path-match

  assert_file_contains "$log" $'has-session\t-t\talpha'
  assert_file_contains "$log" $'new-window\t-d\t-P\t-F\t#{window_id} #{pane_id}\t-t\talpha:\t-n\tpath-match\t-c\t'"$repo_real"$'\tvim'
}

test_project_arg_unresolved_fails_without_creating_window() {
  local repo repo_real fake_bin log sessions

  repo="$TEST_TMPDIR/other"
  make_git_repo "$repo"
  repo_real="$(cd "$repo" && pwd -P)"
  mkdir -p "$TEST_TMPDIR/elsewhere"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"
  sessions=$'alpha\t'"$repo_real"$'\n'

  if EDITOR=vim TAW_FAKE_TMUX_SESSIONS="$sessions" TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$TEST_TMPDIR/elsewhere" -p missing; then
    fail "expected unresolved -p project to fail"
  fi

  assert_file_contains "$log" $'list-sessions\t-F\t#{session_name}\t#{session_path}'
  assert_file_not_contains "$log" $'new-session\t'
  assert_file_not_contains "$log" $'new-window\t'
}

test_creates_bare_worktree_from_positional_base_ref() {
  local project fake_bin log expected actual branch worktree_real

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"

  EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$TEST_TMPDIR" -p "$project" feature-x develop

  branch="$(git -C "$project/feature-x" branch --show-current)"
  expected="$(git -C "$project" rev-parse develop)"
  actual="$(git -C "$project/feature-x" rev-parse HEAD)"
  worktree_real="$(cd "$project/feature-x" && pwd -P)"
  assert_eq "feature-x" "$branch" "expected worktree branch named after worktree"
  assert_eq "$expected" "$actual" "expected worktree branch to start from positional base ref"
  assert_file_contains "$log" $'new-session\t-d\t-P\t-F\t#{window_id} #{pane_id}\t-s\tproject\t-n\tfeature-x'
  assert_file_contains "$log" $'rename-window\t-t\t@1\tfeature-x'
  assert_file_contains "$log" $'-c\t'"$worktree_real"
}

test_positional_base_ref_overrides_named_branch() {
  local project fake_bin log expected actual

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"

  EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$TEST_TMPDIR" -p "$project" -b main feature-x develop

  expected="$(git -C "$project" rev-parse develop)"
  actual="$(git -C "$project/feature-x" rev-parse HEAD)"
  assert_eq "$expected" "$actual" "expected positional base ref to override -b"
}

test_supports_bare_child_not_named_git() {
  local project fake_bin log branch

  project="$(make_bare_wrapper "$TEST_TMPDIR" ".bare")"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"

  EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$TEST_TMPDIR" -p "$project" feature-x develop

  branch="$(git -C "$project/feature-x" branch --show-current)"
  assert_eq "feature-x" "$branch" "expected worktree branch from .bare repo"
  assert_file_contains "$log" $'new-session\t-d\t-P\t-F\t#{window_id} #{pane_id}\t-s\tproject\t-n\tfeature-x'
}

test_bare_project_without_worktree_opens_default_branch_worktree() {
  local project fake_bin log branch worktree_real

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"

  EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$TEST_TMPDIR" -p "$project"

  branch="$(git -C "$project/main" branch --show-current)"
  worktree_real="$(cd "$project/main" && pwd -P)"
  assert_eq "main" "$branch" "expected bare project default branch worktree"
  assert_file_contains "$log" $'new-session\t-d\t-P\t-F\t#{window_id} #{pane_id}\t-s\tproject\t-n\tmain'
  assert_file_contains "$log" $'-c\t'"$worktree_real"$'\tvim'
}

test_bare_project_without_default_falls_back_to_master() {
  local project fake_bin log branch worktree_real

  project="$(make_bare_wrapper "$TEST_TMPDIR" ".git" "master")"
  git --git-dir "$project/.git" symbolic-ref HEAD refs/heads/missing
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"

  EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$TEST_TMPDIR" -p "$project"

  branch="$(git -C "$project/master" branch --show-current)"
  worktree_real="$(cd "$project/master" && pwd -P)"
  assert_eq "master" "$branch" "expected bare project to fall back to master"
  assert_file_contains "$log" $'new-session\t-d\t-P\t-F\t#{window_id} #{pane_id}\t-s\tproject\t-n\tmaster'
  assert_file_contains "$log" $'-c\t'"$worktree_real"$'\tvim'
}

test_bare_project_origin_head_only_creates_local_default_worktree() {
  local project fake_bin log branch worktree_real

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  git --git-dir "$project/.git" update-ref refs/remotes/origin/main refs/heads/main
  git --git-dir "$project/.git" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
  git --git-dir "$project/.git" symbolic-ref HEAD refs/heads/missing
  git --git-dir "$project/.git" update-ref -d refs/heads/main
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"

  EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$TEST_TMPDIR" -p "$project"

  branch="$(git -C "$project/main" branch --show-current)"
  worktree_real="$(cd "$project/main" && pwd -P)"
  assert_eq "main" "$branch" "expected origin/HEAD-only repo to create local main worktree"
  assert_file_contains "$log" $'new-session\t-d\t-P\t-F\t#{window_id} #{pane_id}\t-s\tproject\t-n\tmain'
  assert_file_contains "$log" $'-c\t'"$worktree_real"$'\tvim'
}

test_bare_project_named_branch_without_worktree_opens_branch_worktree() {
  local project fake_bin log branch worktree_real

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"

  EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$TEST_TMPDIR" -p "$project" -b develop

  branch="$(git -C "$project/develop" branch --show-current)"
  worktree_real="$(cd "$project/develop" && pwd -P)"
  assert_eq "develop" "$branch" "expected bare -b to open branch worktree"
  assert_file_contains "$log" $'new-session\t-d\t-P\t-F\t#{window_id} #{pane_id}\t-s\tproject\t-n\tdevelop'
  assert_file_contains "$log" $'-c\t'"$worktree_real"$'\tvim'
}

test_bare_project_reuses_existing_default_branch_worktree_when_confirmed() {
  local project fake_bin log branch existing_real

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  git --git-dir "$project/.git" worktree add "$TEST_TMPDIR/main-existing" main >/dev/null 2>&1
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"

  printf 'y\n' | EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$TEST_TMPDIR" -p "$project"

  branch="$(git -C "$TEST_TMPDIR/main-existing" branch --show-current)"
  existing_real="$(cd "$TEST_TMPDIR/main-existing" && pwd -P)"
  assert_eq "main" "$branch" "expected accepted existing worktree to stay on main"
  assert_not_exists "$project/main"
  assert_file_contains "$log" $'new-session\t-d\t-P\t-F\t#{window_id} #{pane_id}\t-s\tproject\t-n\tmain-existing'
  assert_file_contains "$log" $'-c\t'"$existing_real"$'\tvim'
}

test_bare_project_branch_with_slash_creates_nested_worktree() {
  local project fake_bin log branch worktree_real

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  git --git-dir "$project/.git" branch "feature/nested" main
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"

  EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$TEST_TMPDIR" -p "$project" -b "feature/nested"

  branch="$(git -C "$project/feature/nested" branch --show-current)"
  worktree_real="$(cd "$project/feature/nested" && pwd -P)"
  assert_eq "feature/nested" "$branch" "expected branch with slash to create nested worktree"
  assert_file_contains "$log" $'new-session\t-d\t-P\t-F\t#{window_id} #{pane_id}\t-s\tproject\t-n\tnested'
  assert_file_contains "$log" $'-c\t'"$worktree_real"$'\tvim'
}

test_bare_project_invalid_branch_does_not_create_parent_dirs() {
  local project fake_bin log

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"

  if EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$TEST_TMPDIR" -p "$project" -b "../outside/foo"; then
    fail "expected invalid bare branch to fail"
  fi
  assert_not_exists "$TEST_TMPDIR/outside"
  [[ ! -f "$log" ]] || fail "expected tmux not to run after invalid bare branch"
}

test_normal_repo_rejects_worktree_creation() {
  local repo fake_bin log

  repo="$TEST_TMPDIR/repo"
  make_git_repo "$repo"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"

  if EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$repo" -p "$repo" feature-x; then
    fail "expected normal repo worktree creation to fail"
  fi
  [[ ! -f "$log" ]] || fail "expected tmux not to run after worktree error"
}

test_normal_repo_rejects_existing_worktree_path() {
  local repo fake_bin log

  repo="$TEST_TMPDIR/repo"
  make_git_repo "$repo"
  git -C "$repo" worktree add -b feature-x "$repo/feature-x" >/dev/null 2>&1
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"

  if EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$repo" -p "$repo" feature-x; then
    fail "expected normal repo existing worktree path to fail"
  fi
  [[ ! -f "$log" ]] || fail "expected tmux not to run after existing worktree error"
}

test_rejects_unrelated_git_repo_at_worktree_path() {
  local project fake_bin log unrelated

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  unrelated="$project/feature-x"
  make_git_repo "$unrelated"
  git -C "$unrelated" checkout -qb feature-x
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"

  if EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$TEST_TMPDIR" -p "$project" feature-x; then
    fail "expected unrelated git repo at worktree path to fail"
  fi
  [[ ! -f "$log" ]] || fail "expected tmux not to run for unrelated git repo"
}

test_rejects_empty_required_command_values() {
  local repo fake_bin log

  repo="$TEST_TMPDIR/repo"
  make_git_repo "$repo"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"

  if EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$repo" -p "$repo" -agent=; then
    fail "expected empty -agent= to fail"
  fi
  [[ ! -f "$log" ]] || fail "expected tmux not to run after empty -agent="

  if EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$repo" -p "$repo" -ed=; then
    fail "expected empty -ed= to fail"
  fi
  [[ ! -f "$log" ]] || fail "expected tmux not to run after empty -ed="
}

test_existing_worktree_branch_switch_prompts() {
  local project fake_bin log branch

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  git -C "$project" branch feature-x develop
  git -C "$project" worktree add -b other "$project/feature-x" main >/dev/null 2>&1
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"

  printf 'y\n' | EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$TEST_TMPDIR" -p "$project" feature-x develop

  branch="$(git -C "$project/feature-x" branch --show-current)"
  assert_eq "feature-x" "$branch" "expected existing worktree to switch after confirmation"
  assert_file_contains "$log" $'new-session\t-d\t-P\t-F\t#{window_id} #{pane_id}\t-s\tproject\t-n\tfeature-x'
}

test_existing_worktree_without_base_uses_project_head() {
  local project fake_bin log expected actual branch

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  git -C "$project" branch other develop
  git -C "$project" worktree add "$project/feature-x" other >/dev/null 2>&1
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"

  printf 'y\n' | EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$TEST_TMPDIR" -p "$project" feature-x

  branch="$(git -C "$project/feature-x" branch --show-current)"
  expected="$(git -C "$project" rev-parse HEAD)"
  actual="$(git -C "$project/feature-x" rev-parse HEAD)"
  assert_eq "feature-x" "$branch" "expected existing worktree to switch to basename branch"
  assert_eq "$expected" "$actual" "expected missing basename branch to start from project HEAD"
}

test_rejects_empty_project_and_branch_values() {
  local repo fake_bin log

  repo="$TEST_TMPDIR/repo"
  make_git_repo "$repo"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"

  if EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$repo" -p ""; then
    fail "expected empty -p value to fail"
  fi
  [[ ! -f "$log" ]] || fail "expected tmux not to run after empty -p value"

  if EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$repo" -p=; then
    fail "expected empty -p= value to fail"
  fi
  [[ ! -f "$log" ]] || fail "expected tmux not to run after empty -p= value"

  if EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$repo" -p "$repo" -b ""; then
    fail "expected empty -b value to fail"
  fi
  [[ ! -f "$log" ]] || fail "expected tmux not to run after empty -b value"

  if EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$repo" -p "$repo" -b=; then
    fail "expected empty -b= value to fail"
  fi
  [[ ! -f "$log" ]] || fail "expected tmux not to run after empty -b= value"
}

test_prompts_for_existing_repo_when_not_inside_git() {
  local repo fake_bin log

  repo="$TEST_TMPDIR/repo"
  make_git_repo "$repo"
  mkdir -p "$TEST_TMPDIR/elsewhere"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"

  printf '%s\n' "$repo" | EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$TEST_TMPDIR/elsewhere"

  assert_file_contains "$log" $'new-session\t-d\t-P\t-F\t#{window_id} #{pane_id}\t-s\trepo\t-n\trepo'
}

test_case "taw: creates tmux layout with overrides and shell panes" \
  test_layout_with_overrides_and_shell_panes
test_case "taw: existing session selects new window before attach" \
  test_existing_session_adds_window_and_selects_it_before_attach
test_case "taw: named branch checks out normal repo" \
  test_named_branch_checks_out_normal_repo
test_case "taw: -p resolves from PROJECTS_HOME" \
  test_project_arg_resolves_from_projects_home
test_case "taw: direct -p path precedes PROJECTS_HOME" \
  test_project_arg_direct_path_precedes_projects_home
test_case "taw: -p resolves by tmux session name" \
  test_project_arg_resolves_by_tmux_session_name
test_case "taw: -p resolves by tmux session path basename" \
  test_project_arg_resolves_by_tmux_session_path_basename
test_case "taw: unresolved -p fails without creating window" \
  test_project_arg_unresolved_fails_without_creating_window
test_case "taw: creates bare worktree from positional base ref" \
  test_creates_bare_worktree_from_positional_base_ref
test_case "taw: positional base ref overrides named branch" \
  test_positional_base_ref_overrides_named_branch
test_case "taw: supports bare child not named .git" \
  test_supports_bare_child_not_named_git
test_case "taw: bare project without worktree opens default branch worktree" \
  test_bare_project_without_worktree_opens_default_branch_worktree
test_case "taw: bare project without default falls back to master" \
  test_bare_project_without_default_falls_back_to_master
test_case "taw: bare project with only origin HEAD creates local default worktree" \
  test_bare_project_origin_head_only_creates_local_default_worktree
test_case "taw: bare project -b opens branch worktree" \
  test_bare_project_named_branch_without_worktree_opens_branch_worktree
test_case "taw: bare project reuses existing default branch worktree when confirmed" \
  test_bare_project_reuses_existing_default_branch_worktree_when_confirmed
test_case "taw: bare project branch with slash creates nested worktree" \
  test_bare_project_branch_with_slash_creates_nested_worktree
test_case "taw: bare project invalid branch does not create parent dirs" \
  test_bare_project_invalid_branch_does_not_create_parent_dirs
test_case "taw: normal repo rejects worktree creation" \
  test_normal_repo_rejects_worktree_creation
test_case "taw: normal repo rejects existing worktree path" \
  test_normal_repo_rejects_existing_worktree_path
test_case "taw: rejects unrelated git repo at worktree path" \
  test_rejects_unrelated_git_repo_at_worktree_path
test_case "taw: rejects empty required command values" \
  test_rejects_empty_required_command_values
test_case "taw: existing worktree branch switch prompts" \
  test_existing_worktree_branch_switch_prompts
test_case "taw: existing worktree without base uses project head" \
  test_existing_worktree_without_base_uses_project_head
test_case "taw: rejects empty project and branch values" \
  test_rejects_empty_project_and_branch_values
test_case "taw: prompts for repo path outside git" \
  test_prompts_for_existing_repo_when_not_inside_git
