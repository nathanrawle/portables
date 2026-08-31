#!/usr/bin/env bash

. "$TESTS_DIR/lib/taw_test_helpers.bash"

run_taw_convert() {
  local cwd="$1"
  local taw_path
  shift
  taw_path="${TAW_RUN_PATH:-${TAW_FAKE_TMUX_BIN:+$TAW_FAKE_TMUX_BIN:}$PATH}"

  (
    cd "$cwd" || exit 1
    TAW_FUNC_DIR="$REPO_ROOT/home/.zfuns" \
      PATH="$taw_path" \
      zsh -fc 'fpath=("$TAW_FUNC_DIR" $fpath); autoload -U taw-convert; taw-convert "$@"' \
      taw-convert "$@"
  )
}

make_convert_failing_git() {
  local root="$1"
  local bin="$root/bin"
  local real_git

  real_git="$(command -v git)"
  mkdir -p "$bin"
  cat >"$bin/git" <<EOF
#!/usr/bin/env bash
set -euo pipefail

if [[ "\${TAW_CONVERT_FAIL_STAGE:-worktree}" = worktree \
  && "\${1:-}" = --git-dir && "\${3:-}" = worktree && "\${4:-}" = add \
  && "\${5:-}" = --no-checkout ]]; then
  exit 91
fi
if [[ "\${TAW_CONVERT_FAIL_STAGE:-worktree}" = head \
  && "\${1:-}" = --git-dir && "\${3:-}" = symbolic-ref && "\${4:-}" = HEAD ]]; then
  exit 92
fi
if [[ "\${TAW_CONVERT_FAIL_STAGE:-worktree}" = concurrent \
  && "\${1:-}" = --git-dir && "\${3:-}" = symbolic-ref && "\${4:-}" = HEAD ]]; then
  "$real_git" "\$@"
  printf 'concurrent\n' >"\${TAW_CONCURRENT_FILE:?}"
  exit 0
fi
if [[ "\${TAW_CONVERT_FAIL_STAGE:-worktree}" = late-concurrent \
  && "\${1:-}" = --git-dir && "\${3:-}" = symbolic-ref \
  && "\${4:-}" = --quiet && "\${5:-}" = --short && "\${6:-}" = HEAD ]]; then
  "$real_git" "\$@"
  printf 'late concurrent\n' >"\${TAW_CONCURRENT_FILE:?}"
  exit 0
fi
if [[ "\${TAW_CONVERT_FAIL_STAGE:-worktree}" = default-branch-race \
  && "\${1:-}" = --git-dir && "\${3:-}" = update-ref \
  && "\${4:-}" = refs/heads/trunk ]]; then
  "$real_git" "\$@"
  exit 93
fi
if [[ "\${TAW_CONVERT_FAIL_STAGE:-worktree}" = default-config-failure \
  && "\${1:-}" = --git-dir && "\${3:-}" = config \
  && "\${4:-}" = branch.trunk.remote ]]; then
  exit 94
fi
if [[ "\${TAW_CONVERT_FAIL_STAGE:-worktree}" = remove \
  && "\${1:-}" = --git-dir && "\${3:-}" = symbolic-ref && "\${4:-}" = HEAD ]]; then
  exit 95
fi
  if [[ "\${TAW_CONVERT_FAIL_STAGE:-worktree}" = remove \
    && "\${1:-}" = --git-dir && "\${3:-}" = worktree && "\${4:-}" = remove ]]; then
    exit 96
  fi
  if [[ "\${TAW_CONVERT_FAIL_STAGE:-worktree}" = nonbare \
    && "\${1:-}" = --git-dir && "\${3:-}" = config \
    && "\${4:-}" = core.bare && "\${5:-}" = false ]]; then
    exit 97
  fi

exec "$real_git" "\$@"
EOF
  chmod +x "$bin/git"
  printf '%s\n' "$bin"
}

test_convert_bare_project_promotes_dirty_default_and_moves_worktrees() {
  local project main_worktree develop_worktree external before_main before_develop

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  main_worktree="$project/main"
  external="$TEST_TMPDIR/develop-external"
  git --git-dir "$project/.git" worktree add -q "$main_worktree" main
  git --git-dir "$project/.git" worktree add -q "$external" develop
  printf 'staged\n' >"$main_worktree/staged.txt"
  git -C "$main_worktree" add staged.txt
  printf 'dirty\n' >>"$main_worktree/README.md"
  printf 'untracked\n' >"$external/untracked.txt"
  before_main="$(git -C "$main_worktree" status --porcelain=v2 --branch --untracked-files=all)"
  before_develop="$(git -C "$external" status --porcelain=v2 --branch --untracked-files=all)"

  run_taw_convert "$TEST_TMPDIR" "$project"

  develop_worktree="$project/.worktrees/develop"
  assert_eq "false" "$(git -C "$project" rev-parse --is-bare-repository)" \
    "expected a normal primary repository"
  assert_eq "main" "$(git -C "$project" branch --show-current)" \
    "expected the default branch at the repository root"
  assert_eq "$before_main" \
    "$(git -C "$project" status --porcelain=v2 --branch --untracked-files=all)" \
    "expected promoted default worktree state to be preserved"
  assert_eq "$before_develop" \
    "$(git -C "$develop_worktree" status --porcelain=v2 --branch --untracked-files=all)" \
    "expected linked worktree state to be preserved"
  assert_not_exists "$main_worktree"
  assert_not_exists "$external"
}

test_convert_bare_project_moves_slash_and_detached_worktrees() {
  local project detached_source detached_commit

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  git --git-dir "$project/.git" worktree add -q "$project/main" main
  git --git-dir "$project/.git" branch feature/topic develop
  git --git-dir "$project/.git" worktree add -q \
    "$TEST_TMPDIR/topic-external" feature/topic
  detached_source="$TEST_TMPDIR/detached-copy"
  git --git-dir "$project/.git" worktree add -q --detach "$detached_source" main
  detached_commit="$(git -C "$detached_source" rev-parse HEAD)"

  run_taw_convert "$TEST_TMPDIR" "$project"

  assert_eq "feature/topic" \
    "$(git -C "$project/.worktrees/feature/topic" branch --show-current)" \
    "expected branch names to determine managed paths"
  assert_eq "$detached_commit" \
    "$(git -C "$project/.worktrees/detached-copy" rev-parse HEAD)" \
    "expected detached worktree commit to be preserved"
  assert_eq "" "$(git -C "$project/.worktrees/detached-copy" branch --show-current)" \
    "expected detached worktree state to be preserved"
}

test_convert_rejects_nondefault_worktree_containing_detached_worktree() {
  local project parent child before_parent before_child before_list output
  local -a backups

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  parent="$project/develop"
  git --git-dir "$project/.git" worktree add -q "$parent" develop
  parent="$(cd "$parent" && pwd -P)"
  child="$parent/scratch"
  git --git-dir "$project/.git" worktree add -q --detach "$child" main
  printf 'dirty\n' >>"$parent/develop.txt"
  printf 'untracked\n' >"$child/untracked.txt"
  before_parent="$(git -C "$parent" status --porcelain=v2 --branch --untracked-files=all)"
  before_child="$(git -C "$child" status --porcelain=v2 --branch --untracked-files=all)"
  before_list="$(git --git-dir "$project/.git" worktree list --porcelain)"

  if output="$(run_taw_convert "$TEST_TMPDIR" "$project" 2>&1)"; then
    fail "expected nested non-default worktrees to reject conversion"
  fi

  assert_string_contains "$output" \
    "cannot move a worktree that contains another registered worktree: $parent"
  assert_eq "true" "$(git --git-dir "$project/.git" rev-parse --is-bare-repository)" \
    "expected nested-source rejection to preserve the bare repository"
  assert_eq "$before_parent" \
    "$(git -C "$parent" status --porcelain=v2 --branch --untracked-files=all)" \
    "expected nested-source rejection to preserve the parent worktree"
  assert_eq "$before_child" \
    "$(git -C "$child" status --porcelain=v2 --branch --untracked-files=all)" \
    "expected nested-source rejection to preserve the child worktree"
  assert_eq "$before_list" "$(git --git-dir "$project/.git" worktree list --porcelain)" \
    "expected nested-source rejection to preserve worktree metadata"
  assert_not_exists "$project/.worktrees"
  shopt -s nullglob
  backups=( "$TEST_TMPDIR"/.project.taw-convert.* )
  shopt -u nullglob
  assert_eq "0" "${#backups[@]}" "expected nested-source rejection before backup creation"
}

test_convert_rejects_nondefault_worktree_containing_default_worktree() {
  local project parent default_worktree before_parent before_default before_list output
  local -a backups

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  parent="$project/develop"
  git --git-dir "$project/.git" worktree add -q "$parent" develop
  parent="$(cd "$parent" && pwd -P)"
  default_worktree="$parent/main"
  git --git-dir "$project/.git" worktree add -q "$default_worktree" main
  before_parent="$(git -C "$parent" status --porcelain=v2 --branch --untracked-files=all)"
  before_default="$(git -C "$default_worktree" status \
    --porcelain=v2 --branch --untracked-files=all)"
  before_list="$(git --git-dir "$project/.git" worktree list --porcelain)"

  if output="$(run_taw_convert "$TEST_TMPDIR" "$project" 2>&1)"; then
    fail "expected a non-default parent of the default worktree to reject conversion"
  fi

  assert_string_contains "$output" \
    "cannot move a worktree that contains another registered worktree: $parent"
  assert_eq "$before_parent" \
    "$(git -C "$parent" status --porcelain=v2 --branch --untracked-files=all)" \
    "expected rejection to preserve the non-default parent worktree"
  assert_eq "$before_default" \
    "$(git -C "$default_worktree" status --porcelain=v2 --branch --untracked-files=all)" \
    "expected rejection to preserve the nested default worktree"
  assert_eq "$before_list" "$(git --git-dir "$project/.git" worktree list --porcelain)" \
    "expected rejection to preserve nested default worktree metadata"
  assert_not_exists "$project/.worktrees"
  shopt -s nullglob
  backups=( "$TEST_TMPDIR"/.project.taw-convert.* )
  shopt -u nullglob
  assert_eq "0" "${#backups[@]}" "expected rejection before backup creation"
}

test_convert_allows_default_worktree_containing_detached_worktree() {
  local project default_worktree child target before_default before_child

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  default_worktree="$project/main"
  child="$default_worktree/scratch"
  target="$project/.worktrees/scratch"
  git --git-dir "$project/.git" worktree add -q "$default_worktree" main
  git --git-dir "$project/.git" worktree add -q --detach "$child" develop
  printf 'dirty\n' >>"$default_worktree/README.md"
  printf 'untracked\n' >"$child/untracked.txt"
  before_default="$(git -C "$default_worktree" status \
    --porcelain=v2 --branch --untracked-files=all)"
  before_child="$(git -C "$child" status --porcelain=v2 --branch --untracked-files=all)"

  run_taw_convert "$TEST_TMPDIR" "$project"

  assert_eq "$before_default" \
    "$(git -C "$project" status --porcelain=v2 --branch --untracked-files=all)" \
    "expected the containing default worktree state to be preserved"
  assert_eq "$before_child" \
    "$(git -C "$target" status --porcelain=v2 --branch --untracked-files=all)" \
    "expected the nested detached worktree state to be preserved"
  assert_not_exists "$default_worktree"
  assert_exists "$target"
}

test_convert_conventional_bare_repository() {
  local bare project

  bare="$(make_conventional_bare_clone "$TEST_TMPDIR" "project")"
  project="${bare%.git}"
  git --git-dir "$bare" worktree add -q "$TEST_TMPDIR/main-external" main
  git --git-dir "$bare" worktree add -q "$TEST_TMPDIR/develop-external" develop

  run_taw_convert "$TEST_TMPDIR" "$bare"

  assert_exists "$project/.git"
  assert_not_exists "$bare"
  assert_eq "false" "$(git -C "$project" rev-parse --is-bare-repository)" \
    "expected conventional bare repository to become a normal clone"
  assert_eq "develop" \
    "$(git -C "$project/.worktrees/develop" branch --show-current)" \
    "expected external linked worktree to move under the normal clone"
}

test_convert_rejects_suffixless_bare_repository_before_mutation() {
  local source container bare default_worktree before output
  local -a backups

  source="$TEST_TMPDIR/source"
  container="$TEST_TMPDIR/container"
  bare="$container/foo"
  default_worktree="$TEST_TMPDIR/main-external"
  make_git_repo "$source"
  mkdir -p "$container"
  git clone --bare "$source" "$bare" >/dev/null 2>&1
  git --git-dir "$bare" worktree add -q "$default_worktree" main
  printf 'sibling\n' >"$container/sibling.txt"
  before="$(git -C "$default_worktree" status --porcelain=v2 --branch --untracked-files=all)"

  if output="$(run_taw_convert "$TEST_TMPDIR" "$bare" 2>&1)"; then
    fail "expected suffixless bare conversion to fail"
  fi

  assert_string_contains "$output" "does not support suffixless bare repositories"
  assert_eq "true" "$(git --git-dir "$bare" rev-parse --is-bare-repository)" \
    "expected suffixless rejection to preserve the bare repository"
  assert_not_exists "$container/.git"
  assert_file_contents "$container/sibling.txt" "sibling"
  assert_exists "$default_worktree"
  assert_eq "$before" \
    "$(git -C "$default_worktree" status --porcelain=v2 --branch --untracked-files=all)" \
    "expected suffixless rejection to preserve the registered worktree"
  shopt -s nullglob
  backups=( "$TEST_TMPDIR"/.container.taw-convert.* )
  shopt -u nullglob
  assert_eq "0" "${#backups[@]}" "expected suffixless rejection before backup creation"
}

test_convert_bare_child_not_named_git() {
  local project external

  project="$(make_bare_wrapper "$TEST_TMPDIR" ".bare")"
  external="$TEST_TMPDIR/develop-external"
  git --git-dir "$project/.bare" worktree add -q "$project/main" main
  git --git-dir "$project/.bare" worktree add -q "$external" develop

  run_taw_convert "$TEST_TMPDIR" "$project"

  assert_exists "$project/.git"
  assert_not_exists "$project/.bare"
  assert_eq "false" "$(git -C "$project" rev-parse --is-bare-repository)" \
    "expected .bare wrapper to become a normal clone"
  assert_eq "main" "$(git -C "$project" branch --show-current)" \
    "expected .bare wrapper default branch at the repository root"
  assert_eq "develop" \
    "$(git -C "$project/.worktrees/develop" branch --show-current)" \
    "expected .bare wrapper linked worktree under the normal clone"
  assert_not_exists "$project/main"
  assert_not_exists "$external"
}

test_convert_without_default_worktree_checks_out_root() {
  local project

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  git --git-dir "$project/.git" worktree add -q "$TEST_TMPDIR/develop" develop

  run_taw_convert "$TEST_TMPDIR" "$project"

  assert_eq "main" "$(git -C "$project" branch --show-current)" \
    "expected a fresh default checkout at the repository root"
  assert_eq "" "$(git -C "$project" status --porcelain --untracked-files=all)" \
    "expected the fresh default checkout to be clean"
  assert_exists "$project/.worktrees/develop"
}

test_convert_without_default_worktree_rejects_tracked_managed_path() {
  local project default_worktree external before output
  local -a backups

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  default_worktree="$TEST_TMPDIR/main"
  external="$TEST_TMPDIR/develop"
  git --git-dir "$project/.git" worktree add -q "$default_worktree" main
  mkdir -p "$default_worktree/.worktrees/develop"
  printf 'owned by main\n' >"$default_worktree/.worktrees/develop/main-owned.txt"
  git -C "$default_worktree" add -f .worktrees/develop/main-owned.txt
  git -C "$default_worktree" commit -qm "track managed path"
  git --git-dir "$project/.git" worktree remove "$default_worktree"
  git --git-dir "$project/.git" worktree add -q "$external" develop
  before="$(git -C "$external" status --porcelain=v2 --branch --untracked-files=all)"

  if output="$(run_taw_convert "$TEST_TMPDIR" "$project" 2>&1)"; then
    fail "expected tracked managed path to reject conversion"
  fi

  assert_string_contains "$output" \
    "cannot check out a default branch that tracks .worktrees"
  assert_eq "true" "$(git --git-dir "$project/.git" rev-parse --is-bare-repository)" \
    "expected tracked managed path rejection before mutation"
  assert_exists "$external"
  assert_not_exists "$project/.worktrees"
  assert_not_exists "$external/main-owned.txt"
  assert_eq "$before" \
    "$(git -C "$external" status --porcelain=v2 --branch --untracked-files=all)" \
    "expected tracked managed path rejection to preserve linked worktree state"
  shopt -s nullglob
  backups=( "$TEST_TMPDIR"/.project.taw-convert.* )
  shopt -u nullglob
  assert_eq "0" "${#backups[@]}" "expected rejection before backup creation"
}

test_convert_unborn_default_worktree_preserves_index() {
  local project before

  project="$TEST_TMPDIR/project"
  mkdir -p "$project"
  git init -q --bare -b main "$project/.git"
  git --git-dir "$project/.git" worktree add -q --orphan -b main "$project/main"
  printf 'staged\n' >"$project/main/staged.txt"
  git -C "$project/main" add staged.txt
  printf 'untracked\n' >"$project/main/untracked.txt"
  before="$(git -C "$project/main" status --porcelain=v2 --branch --untracked-files=all)"

  run_taw_convert "$TEST_TMPDIR" "$project"

  assert_eq "$before" \
    "$(git -C "$project" status --porcelain=v2 --branch --untracked-files=all)" \
    "expected unborn default worktree index and files to be preserved"
  assert_eq "main" "$(git -C "$project" branch --show-current)" \
    "expected the unborn default branch at the repository root"
}

test_convert_creates_remote_only_default_branch() {
  local project

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  git --git-dir "$project/.git" update-ref refs/remotes/origin/trunk refs/heads/main
  git --git-dir "$project/.git" symbolic-ref \
    refs/remotes/origin/HEAD refs/remotes/origin/trunk
  git --git-dir "$project/.git" update-ref -d refs/heads/main
  git --git-dir "$project/.git" symbolic-ref HEAD refs/heads/missing
  git --git-dir "$project/.git" config --unset-all remote.origin.fetch || true

  run_taw_convert "$TEST_TMPDIR" "$project"

  assert_eq "trunk" "$(git -C "$project" branch --show-current)" \
    "expected origin HEAD to provide the normal default branch"
  assert_eq "origin/trunk" "$(git -C "$project" rev-parse --abbrev-ref '@{upstream}')" \
    "expected the remote-only default branch to track origin"
  assert_eq "+refs/heads/*:refs/remotes/origin/*" \
    "$(git -C "$project" config --get-all remote.origin.fetch)" \
    "expected conversion to add a missing origin fetch refspec"
}

test_convert_preserves_narrow_origin_fetch_refspec() {
  local project refspec

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  refspec='+refs/heads/trunk:refs/remotes/origin/trunk'
  git --git-dir "$project/.git" update-ref refs/remotes/origin/trunk refs/heads/main
  git --git-dir "$project/.git" symbolic-ref \
    refs/remotes/origin/HEAD refs/remotes/origin/trunk
  git --git-dir "$project/.git" update-ref -d refs/heads/main
  git --git-dir "$project/.git" symbolic-ref HEAD refs/heads/missing
  git --git-dir "$project/.git" config --unset-all remote.origin.fetch || true
  git --git-dir "$project/.git" config --add remote.origin.fetch "$refspec"

  run_taw_convert "$TEST_TMPDIR" "$project"

  assert_eq "$refspec" "$(git -C "$project" config --get-all remote.origin.fetch)" \
    "expected conversion to preserve a narrow origin fetch refspec"
  assert_eq "origin/trunk" "$(git -C "$project" rev-parse --abbrev-ref '@{upstream}')" \
    "expected the remote-only default branch to track origin"
}

test_convert_preserves_multiple_origin_fetch_refspecs() {
  local project before

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  git --git-dir "$project/.git" update-ref refs/remotes/origin/trunk refs/heads/main
  git --git-dir "$project/.git" symbolic-ref \
    refs/remotes/origin/HEAD refs/remotes/origin/trunk
  git --git-dir "$project/.git" update-ref -d refs/heads/main
  git --git-dir "$project/.git" symbolic-ref HEAD refs/heads/missing
  git --git-dir "$project/.git" config --unset-all remote.origin.fetch || true
  git --git-dir "$project/.git" config --add remote.origin.fetch \
    '+refs/heads/trunk:refs/remotes/origin/trunk'
  git --git-dir "$project/.git" config --add remote.origin.fetch \
    '+refs/heads/release/*:refs/remotes/origin/release/*'
  before="$(git --git-dir "$project/.git" config --get-all remote.origin.fetch)"

  run_taw_convert "$TEST_TMPDIR" "$project"

  assert_eq "$before" "$(git -C "$project" config --get-all remote.origin.fetch)" \
    "expected conversion to preserve multiple origin fetch refspecs"
  assert_eq "origin/trunk" "$(git -C "$project" rev-parse --abbrev-ref '@{upstream}')" \
    "expected the remote-only default branch to track origin"
}

test_convert_preserves_unmanaged_wrapper_entries() {
  local project

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  git --git-dir "$project/.git" worktree add -q "$project/main" main
  printf 'wrapper note\n' >"$project/note.txt"

  run_taw_convert "$TEST_TMPDIR" "$project"

  assert_eq "wrapper note" "$(<"$project/note.txt")" \
    "expected unmanaged wrapper content at the normal repository root"
  assert_eq "?? note.txt" "$(git -C "$project" status --porcelain)" \
    "expected unmanaged wrapper content to remain untracked"
}

test_convert_rejects_fallback_wrapper_conflict_without_data_loss() {
  local project output
  local -a backups

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  printf 'keep me\n' >"$project/00-keep.txt"
  printf 'wrapper README\n' >"$project/README.md"

  if output="$(run_taw_convert "$TEST_TMPDIR" "$project" 2>&1)"; then
    fail "expected wrapper/default conflict to reject conversion"
  fi

  assert_string_contains "$output" \
    "wrapper entry conflicts with default checkout: README.md"
  assert_string_not_contains "$output" "HEAD is now at"
  assert_eq "true" "$(git --git-dir "$project/.git" rev-parse --is-bare-repository)" \
    "expected wrapper conflict rejection to preserve the bare repository"
  assert_file_contents "$project/00-keep.txt" "keep me"
  assert_file_contents "$project/README.md" "wrapper README"
  shopt -s nullglob
  backups=( "$TEST_TMPDIR"/.project.taw-convert.* )
  shopt -u nullglob
  assert_eq "0" "${#backups[@]}" "expected wrapper conflict rollback to remove its backup"
}

test_convert_rejects_deleted_default_wrapper_conflict_without_data_loss() {
  local project output before
  local -a backups

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  git --git-dir "$project/.git" worktree add -q "$project/main" main
  rm -- "$project/main/README.md"
  printf 'wrapper README\n' >"$project/README.md"
  before="$(git -C "$project/main" status --porcelain=v2 --branch --untracked-files=all)"

  if output="$(run_taw_convert "$TEST_TMPDIR" "$project" 2>&1)"; then
    fail "expected deleted default path to conflict with wrapper entry"
  fi

  assert_string_contains "$output" \
    "wrapper entry conflicts with default checkout: README.md"
  assert_eq "true" "$(git --git-dir "$project/.git" rev-parse --is-bare-repository)" \
    "expected deleted-path conflict to preserve the bare repository"
  assert_file_contents "$project/README.md" "wrapper README"
  assert_not_exists "$project/main/README.md"
  assert_eq "$before" \
    "$(git -C "$project/main" status --porcelain=v2 --branch --untracked-files=all)" \
    "expected deleted-path conflict to preserve the default worktree status"
  shopt -s nullglob
  backups=( "$TEST_TMPDIR"/.project.taw-convert.* )
  shopt -u nullglob
  assert_eq "0" "${#backups[@]}" "expected deleted-path conflict rollback to remove its backup"
}

test_convert_allows_staged_delete_with_wrapper_entry() {
  local project

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  git --git-dir "$project/.git" worktree add -q "$project/main" main
  git -C "$project/main" rm -q README.md
  printf 'wrapper README\n' >"$project/README.md"

  run_taw_convert "$TEST_TMPDIR" "$project"

  assert_eq "false" "$(git -C "$project" rev-parse --is-bare-repository)" \
    "expected staged deletion to remain convertible"
  assert_file_contents "$project/README.md" "wrapper README"
  assert_eq $'D\tREADME.md' "$(git -C "$project" diff --cached --name-status)" \
    "expected the staged deletion to remain staged"
  assert_eq "README.md" "$(git -C "$project" ls-files --others --exclude-standard)" \
    "expected the wrapper entry to remain untracked"
}

test_convert_rejects_destination_collision_before_mutation() {
  local project output

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  git --git-dir "$project/.git" worktree add -q "$project/main" main
  git --git-dir "$project/.git" worktree add -q "$TEST_TMPDIR/develop" develop
  mkdir -p "$project/.worktrees/develop"
  printf 'collision\n' >"$project/.worktrees/develop/file.txt"

  if output="$(run_taw_convert "$TEST_TMPDIR" "$project" 2>&1)"; then
    fail "expected destination collision to reject conversion"
  fi

  assert_string_contains "$output" "worktree destination already exists"
  assert_eq "true" "$(git --git-dir "$project/.git" rev-parse --is-bare-repository)" \
    "expected collision rejection before mutation"
  assert_exists "$TEST_TMPDIR/develop"
}

test_convert_rejects_overlapping_destinations_before_mutation() {
  local project topic detached output
  local -a backups

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  topic="$TEST_TMPDIR/topic"
  detached="$TEST_TMPDIR/detached/feature"
  mkdir -p "${detached%/*}"
  git --git-dir "$project/.git" branch feature/foo develop
  git --git-dir "$project/.git" worktree add -q "$project/main" main
  git --git-dir "$project/.git" worktree add -q "$topic" feature/foo
  git --git-dir "$project/.git" worktree add -q --detach "$detached" main

  if output="$(run_taw_convert "$TEST_TMPDIR" "$project" 2>&1)"; then
    fail "expected overlapping destinations to reject conversion"
  fi

  assert_string_contains "$output" "worktree destination collision"
  assert_eq "true" "$(git --git-dir "$project/.git" rev-parse --is-bare-repository)" \
    "expected overlap rejection before mutation"
  assert_exists "$project/main"
  assert_exists "$topic"
  assert_exists "$detached"
  assert_not_exists "$project/.worktrees"
  shopt -s nullglob
  backups=( "$TEST_TMPDIR"/.project.taw-convert.* )
  shopt -u nullglob
  assert_eq "0" "${#backups[@]}" "expected overlap rejection before backup creation"
}

test_convert_prunes_empty_in_wrapper_worktree_parents() {
  local project nested before

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  nested="$project/docs/feature"
  git --git-dir "$project/.git" branch docs/feature develop
  git --git-dir "$project/.git" worktree add -q "$project/main" main
  git --git-dir "$project/.git" worktree add -q "$nested" docs/feature
  mkdir -p "$project/main/docs"
  printf 'default docs\n' >"$project/main/docs/note.txt"
  before="$(git -C "$project/main" status --porcelain=v2 --branch --untracked-files=all)"

  run_taw_convert "$TEST_TMPDIR" "$project"

  assert_eq "$before" \
    "$(git -C "$project" status --porcelain=v2 --branch --untracked-files=all)" \
    "expected default worktree content to survive nested source pruning"
  assert_eq "default docs" "$(<"$project/docs/note.txt")" \
    "expected the default worktree docs directory at the repository root"
  assert_eq "docs/feature" \
    "$(git -C "$project/.worktrees/docs/feature" branch --show-current)" \
    "expected the nested worktree under the managed root"
  assert_not_exists "$nested"
}

test_convert_failure_restores_pruned_worktree_parents() {
  local project nested fake_bin
  local -a backups

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  nested="$project/docs/feature"
  git --git-dir "$project/.git" branch docs/feature develop
  git --git-dir "$project/.git" worktree add -q "$project/main" main
  git --git-dir "$project/.git" worktree add -q "$nested" docs/feature
  mkdir -p "$project/main/docs"
  printf 'default docs\n' >"$project/main/docs/note.txt"
  fake_bin="$(make_convert_failing_git "$TEST_TMPDIR/failing")"

  if TAW_CONVERT_FAIL_STAGE=nonbare TAW_RUN_PATH="$fake_bin:$PATH" \
    run_taw_convert "$TEST_TMPDIR" "$project"; then
    fail "expected injected conversion failure"
  fi

  assert_eq "true" "$(git --git-dir "$project/.git" rev-parse --is-bare-repository)" \
    "expected rollback to restore the bare repository"
  assert_eq "docs/feature" "$(git -C "$nested" branch --show-current)" \
    "expected rollback to recreate the pruned source parents"
  assert_not_exists "$project/.worktrees/docs/feature"
  shopt -s nullglob
  backups=( "$TEST_TMPDIR"/.project.taw-convert.* )
  shopt -u nullglob
  assert_eq "0" "${#backups[@]}" "expected successful rollback to remove its backup"
}

test_convert_prunes_empty_default_worktree_parents() {
  local project default_worktree before

  project="$(make_bare_wrapper "$TEST_TMPDIR" ".git" "docs/feature")"
  default_worktree="$project/docs/feature"
  git --git-dir "$project/.git" worktree add -q "$default_worktree" docs/feature
  mkdir -p "$default_worktree/docs"
  printf 'default docs\n' >"$default_worktree/docs/note.txt"
  before="$(git -C "$default_worktree" status \
    --porcelain=v2 --branch --untracked-files=all)"

  run_taw_convert "$TEST_TMPDIR" "$project"

  assert_eq "docs/feature" "$(git -C "$project" branch --show-current)" \
    "expected the slash-named default branch at the repository root"
  assert_eq "$before" \
    "$(git -C "$project" status --porcelain=v2 --branch --untracked-files=all)" \
    "expected nested default worktree content to survive parent pruning"
  assert_eq "default docs" "$(<"$project/docs/note.txt")" \
    "expected default worktree docs at the repository root"
  assert_not_exists "$default_worktree"
}

test_convert_failure_restores_pruned_default_worktree_parents() {
  local project default_worktree fake_bin
  local -a backups

  project="$(make_bare_wrapper "$TEST_TMPDIR" ".git" "docs/feature")"
  default_worktree="$project/docs/feature"
  git --git-dir "$project/.git" worktree add -q "$default_worktree" docs/feature
  mkdir -p "$default_worktree/docs"
  printf 'default docs\n' >"$default_worktree/docs/note.txt"
  fake_bin="$(make_convert_failing_git "$TEST_TMPDIR/failing")"

  if TAW_CONVERT_FAIL_STAGE=nonbare TAW_RUN_PATH="$fake_bin:$PATH" \
    run_taw_convert "$TEST_TMPDIR" "$project"; then
    fail "expected injected conversion failure"
  fi

  assert_eq "true" "$(git --git-dir "$project/.git" rev-parse --is-bare-repository)" \
    "expected rollback to restore the bare repository"
  assert_eq "docs/feature" "$(git -C "$default_worktree" branch --show-current)" \
    "expected rollback to recreate the pruned default worktree parents"
  assert_eq "default docs" "$(<"$default_worktree/docs/note.txt")" \
    "expected rollback to preserve default worktree content"
  shopt -s nullglob
  backups=( "$TEST_TMPDIR"/.project.taw-convert.* )
  shopt -u nullglob
  assert_eq "0" "${#backups[@]}" "expected successful rollback to remove its backup"
}

test_convert_from_linked_worktree_remaps_cwd() {
  local project output after

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  git --git-dir "$project/.git" worktree add -q "$project/main" main
  git --git-dir "$project/.git" worktree add -q "$project/develop" develop
  mkdir -p "$project/develop/nested"

  output="$(
    cd "$project/develop/nested" || exit 1
    TAW_FUNC_DIR="$REPO_ROOT/home/.zfuns" zsh -fc \
      'fpath=("$TAW_FUNC_DIR" $fpath); autoload -U taw-convert; taw-convert "$1" || exit; pwd -P' \
      taw-convert "$project"
  )"
  after="${output##*$'\n'}"

  assert_eq "$(cd "$project/.worktrees/develop/nested" && pwd -P)" "$after" \
    "expected invoking shell to follow the relocated worktree"
}

test_convert_from_nested_worktree_remaps_cwd() {
  local project child output after
  local -a backups

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  git --git-dir "$project/.git" worktree add -q "$project/main" main
  child="$project/main/scratch"
  git --git-dir "$project/.git" worktree add -q --detach "$child" develop
  mkdir -p "$child/nested"

  output="$(
    cd "$child/nested" || exit 1
    TAW_FUNC_DIR="$REPO_ROOT/home/.zfuns" zsh -fc \
      'fpath=("$TAW_FUNC_DIR" $fpath); autoload -U taw-convert; taw-convert "$1" || exit; pwd -P' \
      taw-convert "$project" 2>&1
  )"
  after="${output##*$'\n'}"

  assert_eq "$(cd "$project/.worktrees/scratch/nested" && pwd -P)" "$after" \
    "expected invoking shell to follow the relocated nested worktree"
  assert_eq "false" "$(git -C "$project" rev-parse --is-bare-repository)" \
    "expected conversion from the nested worktree to succeed"
  assert_not_exists "$project/main"
  shopt -s nullglob
  backups=( "$TEST_TMPDIR"/.project.taw-convert.* )
  shopt -u nullglob
  assert_eq "0" "${#backups[@]}" "expected successful conversion to remove its backup"
}

test_convert_from_default_worktree_root_remaps_cwd() {
  local project output after
  local -a backups

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  git --git-dir "$project/.git" worktree add -q "$project/main" main

  output="$(
    cd "$project/main" || exit 1
    TAW_FUNC_DIR="$REPO_ROOT/home/.zfuns" zsh -fc \
      'fpath=("$TAW_FUNC_DIR" $fpath); autoload -U taw-convert; taw-convert "$1" || exit; pwd -P' \
      taw-convert "$project" 2>&1
  )"
  after="${output##*$'\n'}"

  assert_string_not_contains "$output" "Unable to read current working directory"
  assert_eq "$(cd "$project" && pwd -P)" "$after" \
    "expected invoking shell to follow the promoted default worktree"
  assert_eq "false" "$(git -C "$project" rev-parse --is-bare-repository)" \
    "expected conversion from the default worktree root to succeed"
  assert_not_exists "$project/main"
  shopt -s nullglob
  backups=( "$TEST_TMPDIR"/.project.taw-convert.* )
  shopt -u nullglob
  assert_eq "0" "${#backups[@]}" "expected successful conversion to remove its backup"
}

test_convert_failure_from_default_worktree_root_restores_cwd() {
  local project fake_bin before output after
  local -a backups

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  git --git-dir "$project/.git" worktree add -q "$project/main" main
  printf 'dirty\n' >>"$project/main/README.md"
  before="$(git -C "$project/main" status --porcelain=v2 --branch --untracked-files=all)"
  fake_bin="$(make_convert_failing_git "$TEST_TMPDIR/failing")"

  output="$(
    cd "$project/main" || exit 1
    TAW_FUNC_DIR="$REPO_ROOT/home/.zfuns" \
      TAW_CONVERT_FAIL_STAGE=nonbare PATH="$fake_bin:$PATH" zsh -fc \
      'fpath=("$TAW_FUNC_DIR" $fpath); autoload -U taw-convert;
       if taw-convert "$1"; then exit 1; fi; pwd -P' taw-convert "$project" 2>&1
  )"
  after="${output##*$'\n'}"

  assert_string_contains "$output" "original bare project restored"
  assert_string_not_contains "$output" "Unable to read current working directory"
  assert_eq "$(cd "$project/main" && pwd -P)" "$after" \
    "expected rollback to restore the invoking shell cwd"
  assert_eq "true" "$(git --git-dir "$project/.git" rev-parse --is-bare-repository)" \
    "expected rollback to restore the bare repository"
  assert_eq "$before" \
    "$(git -C "$project/main" status --porcelain=v2 --branch --untracked-files=all)" \
    "expected rollback to preserve the default worktree state"
  shopt -s nullglob
  backups=( "$TEST_TMPDIR"/.project.taw-convert.* )
  shopt -u nullglob
  assert_eq "0" "${#backups[@]}" "expected successful rollback to remove its backup"
}

test_convert_nonbare_failure_restores_original_layout() {
  local project fake_bin before backups

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  git --git-dir "$project/.git" worktree add -q "$project/main" main
  git --git-dir "$project/.git" worktree add -q "$project/develop" develop
  printf 'dirty\n' >>"$project/main/README.md"
  before="$(git -C "$project/main" status --porcelain=v2 --branch --untracked-files=all)"
  fake_bin="$(make_convert_failing_git "$TEST_TMPDIR/failing")"

  if TAW_CONVERT_FAIL_STAGE=nonbare TAW_RUN_PATH="$fake_bin:$PATH" \
    run_taw_convert "$TEST_TMPDIR" "$project"; then
    fail "expected injected conversion failure"
  fi

  assert_eq "true" "$(git --git-dir "$project/.git" rev-parse --is-bare-repository)" \
    "expected rollback to restore the bare repository"
  assert_eq "$before" \
    "$(git -C "$project/main" status --porcelain=v2 --branch --untracked-files=all)" \
    "expected rollback to preserve default worktree state"
  assert_exists "$project/develop"
  shopt -s nullglob
  backups=( "$TEST_TMPDIR"/.project.taw-convert.* )
  shopt -u nullglob
  assert_eq "0" "${#backups[@]}" "expected successful rollback to remove its backup"
}

test_convert_rejects_normal_project() {
  local repo output

  repo="$TEST_TMPDIR/project"
  make_git_repo "$repo"

  if output="$(run_taw_convert "$TEST_TMPDIR" "$repo" 2>&1)"; then
    fail "expected normal project conversion to fail"
  fi

  assert_string_contains "$output" "conversion requires a bare git project"
  assert_eq "false" "$(git -C "$repo" rev-parse --is-bare-repository)" \
    "expected the normal project to remain unchanged"
}

test_convert_rejects_unknown_options_before_mutation() {
  local project output

  project="$(make_bare_wrapper "$TEST_TMPDIR")"

  if output="$(run_taw_convert "$TEST_TMPDIR" "$project" --peer 2>&1)"; then
    fail "expected an unsupported option to fail"
  fi

  assert_string_contains "$output" "taw-convert: unknown option: --peer"
  assert_eq "true" "$(git --git-dir "$project/.git" rev-parse --is-bare-repository)" \
    "expected invalid arguments not to mutate the repository"
}

test_convert_resolves_projects_home_name() {
  local project cwd

  project="$(make_bare_wrapper "$TEST_TMPDIR/projects")"
  cwd="$TEST_TMPDIR/cwd"
  mkdir -p "$cwd"

  PROJECTS_HOME="$TEST_TMPDIR/projects" run_taw_convert "$cwd" project

  assert_eq "false" "$(git -C "$project" rev-parse --is-bare-repository)" \
    "expected PROJECTS_HOME project resolution to convert the wrapper"
}

test_convert_resolves_tmux_session_name() {
  local project cwd fake_bin log sessions

  project="$(make_bare_wrapper "$TEST_TMPDIR/projects")"
  cwd="$TEST_TMPDIR/cwd"
  mkdir -p "$cwd"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"
  sessions=$'$1\tlegacy\t'"$project"$'\n'

  TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    TAW_FAKE_TMUX_SESSIONS="$sessions" run_taw_convert "$cwd" legacy

  assert_eq "false" "$(git -C "$project" rev-parse --is-bare-repository)" \
    "expected tmux session resolution to convert the wrapper"
  assert_no_tmux_work_window "$log"
}

test_convert_debug_reports_resolved_project() {
  local project output

  project="$(make_bare_wrapper "$TEST_TMPDIR")"

  output="$(run_taw_convert "$TEST_TMPDIR" --debug "$project" 2>&1)"

  assert_string_contains "$output" "taw-convert debug: resolved project"
  assert_string_contains "$output" "_taw_convert_project_kind=bare"
  assert_eq "false" "$(git -C "$project" rev-parse --is-bare-repository)" \
    "expected debug mode to complete conversion"
}

test_case "taw-convert: promotes dirty default and moves worktrees" \
  test_convert_bare_project_promotes_dirty_default_and_moves_worktrees
test_case "taw-convert: moves slash and detached worktrees" \
  test_convert_bare_project_moves_slash_and_detached_worktrees
test_case "taw-convert: rejects nested non-default worktrees before mutation" \
  test_convert_rejects_nondefault_worktree_containing_detached_worktree
test_case "taw-convert: rejects non-default parent of default before mutation" \
  test_convert_rejects_nondefault_worktree_containing_default_worktree
test_case "taw-convert: allows default worktree containing detached worktree" \
  test_convert_allows_default_worktree_containing_detached_worktree
test_case "taw-convert: handles conventional bare repositories" \
  test_convert_conventional_bare_repository
test_case "taw-convert: rejects suffixless bare repositories before mutation" \
  test_convert_rejects_suffixless_bare_repository_before_mutation
test_case "taw-convert: handles .bare wrappers" \
  test_convert_bare_child_not_named_git
test_case "taw-convert: checks out missing default worktree" \
  test_convert_without_default_worktree_checks_out_root
test_case "taw-convert: rejects tracked managed path without default worktree" \
  test_convert_without_default_worktree_rejects_tracked_managed_path
test_case "taw-convert: preserves unborn default worktree" \
  test_convert_unborn_default_worktree_preserves_index
test_case "taw-convert: creates remote-only default branch" \
  test_convert_creates_remote_only_default_branch
test_case "taw-convert: preserves narrow origin fetch refspec" \
  test_convert_preserves_narrow_origin_fetch_refspec
test_case "taw-convert: preserves multiple origin fetch refspecs" \
  test_convert_preserves_multiple_origin_fetch_refspecs
test_case "taw-convert: preserves unmanaged wrapper entries" \
  test_convert_preserves_unmanaged_wrapper_entries
test_case "taw-convert: rejects fallback wrapper conflicts without data loss" \
  test_convert_rejects_fallback_wrapper_conflict_without_data_loss
test_case "taw-convert: rejects deleted default wrapper conflicts without data loss" \
  test_convert_rejects_deleted_default_wrapper_conflict_without_data_loss
test_case "taw-convert: allows staged deletes with wrapper entries" \
  test_convert_allows_staged_delete_with_wrapper_entry
test_case "taw-convert: rejects destination collisions" \
  test_convert_rejects_destination_collision_before_mutation
test_case "taw-convert: rejects overlapping destinations" \
  test_convert_rejects_overlapping_destinations_before_mutation
test_case "taw-convert: prunes empty in-wrapper worktree parents" \
  test_convert_prunes_empty_in_wrapper_worktree_parents
test_case "taw-convert: rollback restores pruned worktree parents" \
  test_convert_failure_restores_pruned_worktree_parents
test_case "taw-convert: prunes empty default worktree parents" \
  test_convert_prunes_empty_default_worktree_parents
test_case "taw-convert: rollback restores pruned default worktree parents" \
  test_convert_failure_restores_pruned_default_worktree_parents
test_case "taw-convert: remaps linked-worktree cwd" \
  test_convert_from_linked_worktree_remaps_cwd
test_case "taw-convert: remaps nested-worktree cwd" \
  test_convert_from_nested_worktree_remaps_cwd
test_case "taw-convert: remaps default-worktree-root cwd" \
  test_convert_from_default_worktree_root_remaps_cwd
test_case "taw-convert: rollback restores default-worktree-root cwd" \
  test_convert_failure_from_default_worktree_root_restores_cwd
test_case "taw-convert: failure restores bare layout" \
  test_convert_nonbare_failure_restores_original_layout
test_case "taw-convert: rejects normal projects" \
  test_convert_rejects_normal_project
test_case "taw-convert: rejects unknown options before mutation" \
  test_convert_rejects_unknown_options_before_mutation
test_case "taw-convert: resolves PROJECTS_HOME names" \
  test_convert_resolves_projects_home_name
test_case "taw-convert: resolves tmux session names" \
  test_convert_resolves_tmux_session_name
test_case "taw-convert: debug reports the resolved project" \
  test_convert_debug_reports_resolved_project
