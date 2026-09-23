#!/usr/bin/env bash

make_symlinks_fixture() {
  local fixture_root="$1"
  local repo="$fixture_root/repo"

  mkdir -p \
    "$repo/home/.config/git" \
    "$repo/home/.config/nvim" \
    "$repo/home/.codex" \
    "$repo/home/.claude" \
    "$repo/home/.copilot" \
    "$repo/home/.zfuns" \
    "$repo/home/Library/Application Support/example"

  repo="$(cd "$repo" && pwd -P)" || return 1

  cp "$REPO_ROOT/symlinks" "$REPO_ROOT/log" "$REPO_ROOT/.gitignore" "$repo/"
  cp -R "$REPO_ROOT/lib" "$repo/lib"
  git -C "$repo" init -q
  printf '.DS_Store\n' >"$repo/.global-gitignore"
  git -C "$repo" config core.excludesfile "$repo/.global-gitignore"

  printf 'repo zshrc\n' >"$repo/home/.zshrc"
  printf 'repo bashrc\n' >"$repo/home/.bashrc"
  printf 'repo ds store\n' >"$repo/home/.DS_Store"
  cat >"$repo/home/.config/git/config" <<'EOF'
[core]
  editor = vi
EOF
  printf 'repo git ignore\n' >"$repo/home/.config/git/ignore"
  printf 'repo nvim init\n' >"$repo/home/.config/nvim/init.lua"
  printf 'repo codex ds store\n' >"$repo/home/.codex/.DS_Store"
  printf 'repo function\n' >"$repo/home/.zfuns/plain-func"
  printf 'repo ignored zcp\n' >"$repo/home/.zfuns/zcp"
  printf 'repo ignored zln\n' >"$repo/home/.zfuns/zln"
  printf 'repo library\n' >"$repo/home/Library/Application Support/example/config"

  ln -s plain-func "$repo/home/.zfuns/symlink-func"
  mkdir -p "$repo/home/.agent-generics/skills/test-skill"
  printf 'skill body\n' >"$repo/home/.agent-generics/skills/test-skill/SKILL.md"
  ln -s ../.agent-generics/skills "$repo/home/.codex/skills"
  ln -s ../.agent-generics/skills "$repo/home/.claude/skills"
  ln -s ../.agent-generics/skills "$repo/home/.copilot/skills"

  printf '%s\n' "$repo"
}

run_symlinks() {
  local repo="$1"
  local home="$2"
  local os="${OS:-Darwin}"
  local conflict_mode="${LINK_CONFLICT_MODE:-skip}"
  shift 2

  HOME="$home" OS="$os" LOG_THRESHOLD=4 LINK_CONFLICT_MODE="$conflict_mode" bash "$repo/symlinks" "$@"
}

test_repository_shared_skill_aliases() {
  local provider target

  for provider in codex claude copilot; do
    target="$REPO_ROOT/home/.$provider/skills"
    [[ -L "$target" ]] || fail "missing shared skill alias: $target"
    assert_eq "../.agent-generics/skills" "$(readlink "$target")" \
      "unexpected shared skill alias target: $target"
  done
}

test_default_links_tree_and_preserves_existing_files() {
  local repo home

  repo="$(make_symlinks_fixture "$TEST_TMPDIR")"
  home="$TEST_TMPDIR/home"
  mkdir -p "$home/.config/git"
  printf 'local zshrc\n' >"$home/.zshrc"
  printf 'local only\n' >"$home/.config/git/local-only"

  run_symlinks "$repo" "$home"

  assert_file_contents "$home/.zshrc" "local zshrc"
  assert_symlink_to "$home/.bashrc" "$repo/home/.bashrc"
  assert_symlink_to "$home/.config/git/config" "$repo/home/.config/git/config"
  assert_symlink_to "$home/.config/nvim/init.lua" "$repo/home/.config/nvim/init.lua"
  assert_symlink_to "$home/.zfuns/plain-func" "$repo/home/.zfuns/plain-func"
  assert_symlink_to "$home/.zfuns/symlink-func" "$repo/home/.zfuns/symlink-func"
  assert_not_exists "$home/.DS_Store"
  assert_not_exists "$home/.codex/.DS_Store"
  assert_not_exists "$home/.zfuns/zcp"
  assert_not_exists "$home/.zfuns/zln"
  assert_file_contents "$home/.config/git/local-only" "local only"
}

test_explicit_file_links_only_that_file() {
  local repo home

  repo="$(make_symlinks_fixture "$TEST_TMPDIR")"
  home="$TEST_TMPDIR/home"

  run_symlinks "$repo" "$home" .zshrc

  assert_symlink_to "$home/.zshrc" "$repo/home/.zshrc"
  assert_not_exists "$home/.bashrc"
  assert_not_exists "$home/.config/git/config"
}

test_explicit_directory_links_that_subtree() {
  local repo home

  repo="$(make_symlinks_fixture "$TEST_TMPDIR")"
  home="$TEST_TMPDIR/home"

  run_symlinks "$repo" "$home" .config/git

  assert_symlink_to "$home/.config/git/config" "$repo/home/.config/git/config"
  assert_symlink_to "$home/.config/git/ignore" "$repo/home/.config/git/ignore"
  assert_not_exists "$home/.zshrc"
  assert_not_exists "$home/.config/nvim/init.lua"
}

test_explicit_dot_links_root_with_clean_targets() {
  local repo home
  local target

  repo="$(make_symlinks_fixture "$TEST_TMPDIR")"
  home="$TEST_TMPDIR/home"

  run_symlinks "$repo" "$home" .

  assert_symlink_to "$home/.zshrc" "$repo/home/.zshrc"
  target="$(readlink "$home/.zshrc")"
  [[ "$target" != *'/./'* ]] || fail "explicit dot produced unclean target: $target"
  assert_symlink_to "$home/.config/git/config" "$repo/home/.config/git/config"
}

test_backup_conflict_mode_preserves_conflict_as_backup() {
  local repo home
  local -a backups

  repo="$(make_symlinks_fixture "$TEST_TMPDIR")"
  home="$TEST_TMPDIR/home"
  mkdir -p "$home"
  printf 'local zshrc\n' >"$home/.zshrc"

  LINK_CONFLICT_MODE=backup run_symlinks "$repo" "$home" .zshrc

  assert_symlink_to "$home/.zshrc" "$repo/home/.zshrc"
  shopt -s nullglob
  backups=( "$home"/.zshrc.bak.* )
  shopt -u nullglob
  [[ ${#backups[@]} -eq 1 ]] || fail "expected exactly one backup for .zshrc"
  assert_file_contents "${backups[0]}" "local zshrc"
}

test_force_conflict_mode_replaces_existing_path() {
  local repo home

  repo="$(make_symlinks_fixture "$TEST_TMPDIR")"
  home="$TEST_TMPDIR/home"
  mkdir -p "$home"
  printf 'local zshrc\n' >"$home/.zshrc"

  LINK_CONFLICT_MODE=force run_symlinks "$repo" "$home" .zshrc

  assert_symlink_to "$home/.zshrc" "$repo/home/.zshrc"
}

test_non_darwin_default_prunes_library_payload() {
  local repo home

  repo="$(make_symlinks_fixture "$TEST_TMPDIR")"
  home="$TEST_TMPDIR/home"

  OS=Linux run_symlinks "$repo" "$home"

  assert_symlink_to "$home/.config/git/config" "$repo/home/.config/git/config"
  assert_not_exists "$home/Library"
  assert_not_exists "$home/Library/Application Support/example/config"
}

test_darwin_default_links_library_payload() {
  local repo home

  repo="$(make_symlinks_fixture "$TEST_TMPDIR")"
  home="$TEST_TMPDIR/home"

  OS=Darwin run_symlinks "$repo" "$home"

  assert_symlink_to \
    "$home/Library/Application Support/example/config" \
    "$repo/home/Library/Application Support/example/config"
}

test_symlinked_directory_tree_links_into_existing_destination() {
  local repo home

  repo="$(make_symlinks_fixture "$TEST_TMPDIR")"
  home="$TEST_TMPDIR/home"
  mkdir -p "$home/.codex/skills/.system" "$home/.claude/skills" "$home/.copilot/skills"
  printf 'keep\n' >"$home/.codex/skills/.system/existing"

  run_symlinks "$repo" "$home" .codex .claude .copilot

  assert_file_contents "$home/.codex/skills/.system/existing" "keep"
  assert_symlink_to \
    "$home/.codex/skills/test-skill/SKILL.md" \
    "$repo/home/.codex/skills/test-skill/SKILL.md"
  assert_symlink_to \
    "$home/.claude/skills/test-skill/SKILL.md" \
    "$repo/home/.claude/skills/test-skill/SKILL.md"
  assert_symlink_to \
    "$home/.copilot/skills/test-skill/SKILL.md" \
    "$repo/home/.copilot/skills/test-skill/SKILL.md"
  [[ ! -L "$home/.codex/skills" ]] || fail "expected .codex/skills directory to remain real"
}

test_no_ignore_overrides_default_ignore_behavior() {
  local repo home

  repo="$(make_symlinks_fixture "$TEST_TMPDIR")"
  home="$TEST_TMPDIR/home"

  run_symlinks "$repo" "$home" --no-ignore .

  assert_symlink_to "$home/.DS_Store" "$repo/home/.DS_Store"
  assert_symlink_to "$home/.codex/.DS_Store" "$repo/home/.codex/.DS_Store"
  assert_symlink_to "$home/.zfuns/zcp" "$repo/home/.zfuns/zcp"
  assert_symlink_to "$home/.zfuns/zln" "$repo/home/.zfuns/zln"
}

test_case "symlinks: default run links tree and preserves existing files" \
  test_default_links_tree_and_preserves_existing_files
test_case "symlinks: repository agent skill aliases stay shared" \
  test_repository_shared_skill_aliases
test_case "symlinks: explicit file links only that file" \
  test_explicit_file_links_only_that_file
test_case "symlinks: explicit directory links that subtree" \
  test_explicit_directory_links_that_subtree
test_case "symlinks: explicit dot links root with clean targets" \
  test_explicit_dot_links_root_with_clean_targets
test_case "symlinks: backup conflict mode preserves conflict as backup" \
  test_backup_conflict_mode_preserves_conflict_as_backup
test_case "symlinks: force conflict mode replaces existing path" \
  test_force_conflict_mode_replaces_existing_path
test_case "symlinks: non-Darwin default prunes Library payload" \
  test_non_darwin_default_prunes_library_payload
test_case "symlinks: Darwin default links Library payload" \
  test_darwin_default_links_library_payload
test_case "symlinks: symlinked directory trees merge into existing destinations" \
  test_symlinked_directory_tree_links_into_existing_destination
test_case "symlinks: --no-ignore links ignored paths" \
  test_no_ignore_overrides_default_ignore_behavior

test_alias_cannot_damage_source() {
  local repo home mode
  repo="$(make_symlinks_fixture "$TEST_TMPDIR")"
  home="$TEST_TMPDIR/home"
  mkdir -p "$home/.config"
  ln -s "$repo/home/.config/nvim" "$home/.config/nvim"
  for mode in force backup; do
    LINK_CONFLICT_MODE="$mode" run_symlinks "$repo" "$home" .config/nvim
    assert_file_contents "$repo/home/.config/nvim/init.lua" 'repo nvim init'
    [[ ! -L "$repo/home/.config/nvim/init.lua" ]] || fail 'source replaced with link'
  done
}

test_git_negations_and_builtin_ignores() {
  local repo home
  repo="$(make_symlinks_fixture "$TEST_TMPDIR")"
  home="$TEST_TMPDIR/home"
  git -C "$repo" config core.excludesfile /dev/null
  printf 'home/*.txt\n!home/keep.txt\n' >>"$repo/.gitignore"
  printf keep >"$repo/home/keep.txt"
  printf ignore >"$repo/home/ignore.txt"
  run_symlinks "$repo" "$home"
  assert_symlink_to "$home/keep.txt" "$repo/home/keep.txt"
  assert_not_exists "$home/ignore.txt"
  assert_not_exists "$home/.DS_Store"
}

test_link_failure_continues_independent_paths() {
  local repo home
  repo="$(make_symlinks_fixture "$TEST_TMPDIR")"
  home="$TEST_TMPDIR/home"
  mkdir -p "$home"
  printf blocker >"$home/.config"
  if run_symlinks "$repo" "$home" .config/nvim .bashrc; then fail 'failure hidden'; fi
  assert_symlink_to "$home/.bashrc" "$repo/home/.bashrc"
  assert_file_contents "$home/.config" blocker
}

test_backup_does_not_overwrite_previous_backup() {
  local repo home
  repo="$(make_symlinks_fixture "$TEST_TMPDIR")"
  home="$TEST_TMPDIR/home"
  mkdir -p "$home" "$TEST_TMPDIR/bin"
  printf '#!/bin/sh\nprintf "fixed\\n"\n' >"$TEST_TMPDIR/bin/date"
  chmod +x "$TEST_TMPDIR/bin/date"
  printf previous >"$home/.zshrc.bak.fixed"
  printf current >"$home/.zshrc"
  PATH="$TEST_TMPDIR/bin:$PATH" LINK_CONFLICT_MODE=backup run_symlinks "$repo" "$home" .zshrc
  assert_file_contents "$home/.zshrc.bak.fixed" previous
  assert_file_contents "$home/.zshrc.bak.fixed.1" current
}

test_unusual_filenames_and_mount_ignores() {
  local repo home name
  repo="$(make_symlinks_fixture "$TEST_TMPDIR")"
  home="$TEST_TMPDIR/home"
  name=$'a # [file]\twith\nnewlines'
  printf unusual >"$repo/home/$name"
  printf 'home/.agent-generics/skills/test-skill/ignored\n' >>"$repo/.gitignore"
  printf hidden >"$repo/home/.agent-generics/skills/test-skill/ignored"
  run_symlinks "$repo" "$home"
  assert_symlink_to "$home/$name" "$repo/home/$name"
  assert_not_exists "$home/.codex/skills/test-skill/ignored"
}

test_loop_reports_failure_without_hiding_other_links() {
  local repo home
  repo="$(make_symlinks_fixture "$TEST_TMPDIR")"
  home="$TEST_TMPDIR/home"
  ln -s . "$repo/home/loop"
  if run_symlinks "$repo" "$home"; then fail 'loop not reported'; fi
  assert_symlink_to "$home/.bashrc" "$repo/home/.bashrc"
}

test_case 'symlinks: directory aliases cannot damage sources in force or backup mode' test_alias_cannot_damage_source
test_case 'symlinks: negation and built-in ignore rules work independently' test_git_negations_and_builtin_ignores
test_case 'symlinks: errors preserve independent links and return failure' test_link_failure_continues_independent_paths
test_case 'symlinks: backup collisions preserve both versions' test_backup_does_not_overwrite_previous_backup
test_case 'symlinks: NUL records preserve unusual names and mounted ignore rules' test_unusual_filenames_and_mount_ignores
test_case 'symlinks: loops fail while other links continue' test_loop_reports_failure_without_hiding_other_links
