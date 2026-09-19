#!/usr/bin/env bash

maintenance_fixture() {
  export FIXTURE="$TEST_TMPDIR/repo with spaces"
  export HOME="$TEST_TMPDIR/home with spaces"
  export TRACE="$TEST_TMPDIR/trace"
  export PACKAGE_STATE="$TEST_TMPDIR/package-state"
  export OS=Darwin ID= VERSION_ID= HOST=maintenance-test
  export PATH="$TEST_TMPDIR/bin:$PATH"
  mkdir -p "$FIXTURE/home" "$FIXTURE/machine-tools" "$HOME" "$TEST_TMPDIR/bin"
  FIXTURE="$(cd "$FIXTURE" && pwd -P)"
  HOME="$(cd "$HOME" && pwd -P)"
  export XDG_CONFIG_HOME="$HOME/.config" GIT_CONFIG_GLOBAL="$HOME/.gitconfig" GIT_CONFIG_NOSYSTEM=1
  unset BASH_ENV ENV GIT_CONFIG_SYSTEM GIT_CONFIG_COUNT
  cp "$REPO_ROOT/instantiate" "$REPO_ROOT/configure" "$REPO_ROOT/symlinks" "$REPO_ROOT/log" "$FIXTURE/"
  cp -R "$REPO_ROOT/lib" "$FIXTURE/lib"
  : >"$PACKAGE_STATE"
  printf 'shell\n' >"$FIXTURE/home/.zshrc"
cat >"$TEST_TMPDIR/bin/brew" <<'EOF'
#!/usr/bin/env bash
printf 'brew %s\n' "$*" >>"$TRACE"
case "$1" in
  list)
    kind=${2#--}
    grep -qx "$kind:$3" "$PACKAGE_STATE"
    ;;
  install)
    shift
    kind=${1#--}
    shift
    rc=0
    for package in "$@"; do
      if [[ "$package" = broken ]]; then
        rc=1
      else
        grep -qx "$kind:$package" "$PACKAGE_STATE" || printf '%s:%s\n' "$kind" "$package" >>"$PACKAGE_STATE"
      fi
    done
    exit "$rc"
    ;;
esac
EOF
  printf '#!/bin/sh\nexit 0\n' >"$TEST_TMPDIR/bin/xcode-select"
  chmod +x "$TEST_TMPDIR/bin/"*
}

test_maintenance_configure_context_and_continuation() {
  maintenance_fixture
  cat >"$FIXTURE/machine-tools/a.sh" <<'EOF'
printf '%s|%s|%s\n' "$PORTABLES" "$OS" "$1" >>"$TRACE"
exit 7
EOF
  printf 'echo second >>"$TRACE"\n' >"$FIXTURE/machine-tools/b.sh"
  if PORTABLES=/wrong bash "$FIXTURE/configure" a b; then fail 'failure hidden'; fi
  assert_file_contents "$TRACE" "$FIXTURE|Darwin|config
second"
}

test_maintenance_validation_precedes_work() {
  maintenance_fixture
  printf 'echo touched >>"$TRACE"\n' >"$FIXTURE/machine-tools/a.sh"
  local rc=0
  bash "$FIXTURE/configure" a ../a || rc=$?
  assert_eq 2 "$rc"
  assert_not_exists "$TRACE"
  rc=0
  bash "$FIXTURE/symlinks" .zshrc ../outside || rc=$?
  assert_eq 2 "$rc"
  assert_not_exists "$HOME/.zshrc"
}

test_maintenance_bootstrap_configures_once_after_install() {
  maintenance_fixture
  cat >"$FIXTURE/machine-tools/a.sh" <<'EOF'
case "$1" in
  install) printf 'syspkgmgr:one\nsyspkgmgr:two\n' ;;
  config) echo configured-a >>"$TRACE" ;;
esac
EOF
  cat >"$FIXTURE/machine-tools/b.sh" <<'EOF'
case "$1" in config) echo configured-existing >>"$TRACE" ;; esac
EOF
  bash "$FIXTURE/instantiate"
  assert_symlink_to "$HOME/.maintenance-test.env" "$FIXTURE/home/.maintenance-test.env"
  assert_eq "$FIXTURE" "$(env -u PORTABLES bash -c '. "$1"; printf "%s" "$PORTABLES"' _ "$HOME/.maintenance-test.env")"
  assert_eq 1 "$(grep -c '^configured-a$' "$TRACE")"
  assert_eq 1 "$(grep -c '^configured-existing$' "$TRACE")"
  [[ "$(tail -2 "$TRACE")" = $'configured-a\nconfigured-existing' ]] || fail 'configuration before installation finished'
}

test_maintenance_install_failure_blocks_only_owner() {
  maintenance_fixture
  cat >"$FIXTURE/machine-tools/a.sh" <<'EOF'
case "$1" in
  install) echo syspkgmgr:broken ;;
  config) echo BAD >>"$TRACE" ;;
esac
EOF
  cat >"$FIXTURE/machine-tools/b.sh" <<'EOF'
case "$1" in
  install) echo syspkgmgr:good ;;
  config) echo independent >>"$TRACE" ;;
esac
EOF
  if bash "$FIXTURE/instantiate"; then fail 'installation failure hidden'; fi
  grep -q '^independent$' "$TRACE" || fail 'independent config skipped'
  if grep -q BAD "$TRACE"; then fail 'failed owner configured'; fi
}

test_maintenance_requirement_hook_failure_blocks_only_owner() {
  maintenance_fixture
  cat >"$FIXTURE/machine-tools/a.sh" <<'EOF'
case "$1" in
  install) exit 7 ;;
  config) echo BAD >>"$TRACE" ;;
esac
EOF
  cat >"$FIXTURE/machine-tools/b.sh" <<'EOF'
case "$1" in
  install) echo syspkgmgr:good ;;
  config) echo independent >>"$TRACE" ;;
esac
EOF
  if bash "$FIXTURE/instantiate"; then fail 'requirement-hook failure hidden'; fi
  grep -q '^brew install --formula good$' "$TRACE" || fail 'independent install skipped'
  grep -q '^independent$' "$TRACE" || fail 'independent config skipped'
  if grep -q BAD "$TRACE"; then fail 'failed inventory owner configured'; fi
}

test_maintenance_unknown_requirement_blocks_installation() {
  maintenance_fixture
  printf '[[ "$1" != install ]] || echo magic:package\n' >"$FIXTURE/machine-tools/a.sh"
  if bash "$FIXTURE/instantiate"; then fail 'unknown token accepted'; fi
  if grep -q 'brew install' "$TRACE"; then fail 'installed after invalid inventory'; fi
}

test_maintenance_cask_dispatch() {
  maintenance_fixture
  printf '[[ "$1" != install ]] || echo syspkgmgr:cask:example\n' >"$FIXTURE/machine-tools/a.sh"
  bash "$FIXTURE/instantiate"
  grep -q '^brew install --cask example$' "$TRACE" || fail 'incorrect cask dispatch'
  if grep -q 'brew tap' "$TRACE"; then fail 'cask dispatched as tap'; fi
}

test_maintenance_batches_system_packages() {
  maintenance_fixture
  cat >"$FIXTURE/machine-tools/a.sh" <<'EOF'
[[ "$1" != install ]] || printf '%s\n' syspkgmgr:one syspkgmgr:two syspkgmgr:cask:first
EOF
  cat >"$FIXTURE/machine-tools/b.sh" <<'EOF'
[[ "$1" != install ]] || printf '%s\n' syspkgmgr:two syspkgmgr:three syspkgmgr:cask:second
EOF
  bash "$FIXTURE/instantiate"
  assert_eq 1 "$(grep -c '^brew install --formula ' "$TRACE")"
  assert_eq 1 "$(grep -c '^brew install --cask ' "$TRACE")"
  grep -q '^brew install --formula one two three$' "$TRACE" || fail 'formula batch missing or reordered'
  grep -q '^brew install --cask first second$' "$TRACE" || fail 'cask batch missing or reordered'
}

test_maintenance_failed_batch_retries_missing_packages() {
  maintenance_fixture
  export OS=Linux ID=ubuntu
  cat >"$TEST_TMPDIR/bin/sudo" <<'EOF'
#!/bin/sh
exec "$@"
EOF
  cat >"$TEST_TMPDIR/bin/apt-get" <<'EOF'
#!/usr/bin/env bash
printf 'apt-get %s\n' "$*" >>"$TRACE"
[[ "$1" = install ]] || exit 0
shift
packages=()
for package in "$@"; do [[ "$package" = -* ]] || packages+=( "$package" ); done
if [[ ${#packages[@]} -gt 1 ]]; then exit 100; fi
[[ "${packages[0]}" != broken ]] || exit 100
printf 'apt:%s\n' "${packages[0]}" >>"$PACKAGE_STATE"
EOF
  cat >"$TEST_TMPDIR/bin/dpkg-query" <<'EOF'
#!/usr/bin/env bash
grep -qx "apt:${!#}" "$PACKAGE_STATE" && printf 'install ok installed'
EOF
  chmod +x "$TEST_TMPDIR/bin/sudo" "$TEST_TMPDIR/bin/apt-get" "$TEST_TMPDIR/bin/dpkg-query"
  cat >"$FIXTURE/machine-tools/a.sh" <<'EOF'
case "$1" in install) echo syspkgmgr:broken ;; config) echo BAD >>"$TRACE" ;; esac
EOF
  cat >"$FIXTURE/machine-tools/b.sh" <<'EOF'
case "$1" in install) echo syspkgmgr:good ;; config) echo independent >>"$TRACE" ;; esac
EOF
  if bash "$FIXTURE/instantiate"; then fail 'unavailable package accepted'; fi
  grep -q '^apt-get install -y broken good$' "$TRACE" || fail 'initial package batch missing'
  grep -q '^apt-get install -y broken$' "$TRACE" || fail 'missing package was not retried'
  grep -q '^apt-get install -y good$' "$TRACE" || fail 'valid package was not recovered'
  grep -q '^independent$' "$TRACE" || fail 'recovered package owner remained blocked'
  if grep -q BAD "$TRACE"; then fail 'unavailable package owner configured'; fi
}

test_maintenance_batches_bootstrap_packages() {
  maintenance_fixture
  local original_path="$PATH" command_path command
  for command in bash dirname readlink tr hostname mktemp cp awk mv rm ln chmod mkdir; do
    command_path="$(PATH="$original_path" command -v "$command")"
    ln -sf "$command_path" "$TEST_TMPDIR/bin/$command"
  done
  cat >"$TEST_TMPDIR/bin/sudo" <<'EOF'
#!/bin/sh
exec "$@"
EOF
  cat >"$TEST_TMPDIR/bin/apt-get" <<'EOF'
#!/usr/bin/env bash
printf 'apt-get %s\n' "$*" >>"$TRACE"
case "$1" in
  install)
    shift
    for package in "$@"; do
      [[ "$package" = -* ]] && continue
      printf '#!/bin/sh\nexit 0\n' >"$BOOTSTRAP_BIN/$package"
      chmod +x "$BOOTSTRAP_BIN/$package"
    done
    ;;
esac
EOF
  chmod +x "$TEST_TMPDIR/bin/sudo" "$TEST_TMPDIR/bin/apt-get"
  export BOOTSTRAP_BIN="$TEST_TMPDIR/bin"
  OS=Linux ID=ubuntu PATH="$TEST_TMPDIR/bin" bash "$FIXTURE/instantiate"
  grep -q '^apt-get install -y curl git$' "$TRACE" ||
    fail "bootstrap package batch missing from: $(tr '\n' ';' <"$TRACE")"
}

test_maintenance_git_defaults_and_custom_helpers() {
  maintenance_fixture
  cp "$REPO_ROOT/machine-tools/gcm.sh" "$FIXTURE/machine-tools/"
  ln -sf "$(command -v git)" "$TEST_TMPDIR/bin/git"
  printf '#!/bin/sh\nexit 0\n' >"$TEST_TMPDIR/bin/git-credential-manager"
  printf '#!/bin/sh\nexit 0\n' >"$TEST_TMPDIR/bin/git-credential-oauth"
  chmod +x "$TEST_TMPDIR/bin/"*
  export PATH="$TEST_TMPDIR/bin:/usr/bin:/bin"
  export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$HOME/.gitconfig"
  bash "$FIXTURE/configure" gcm
  assert_eq $'manager\nosxkeychain' "$(git config --global --includes --get-all credential.helper)"
  OS=Linux ID=ubuntu bash "$FIXTURE/configure" gcm
  assert_eq $'cache --timeout 21600\noauth' "$(git config --global --includes --get-all credential.helper)"
  OS=Linux ID=ubuntu bash "$FIXTURE/configure" gcm
  assert_eq 1 "$(git config --file "$HOME/.gitconfig" --get-all include.path | wc -l | tr -d ' ')"
  git config --file "$HOME/.gitconfig" --add credential.helper custom
  bash "$FIXTURE/configure" gcm
  assert_eq custom "$(git config --global --includes --get-all credential.helper)"
}

test_maintenance_git_requires_supported_version() {
  maintenance_fixture
  cp "$REPO_ROOT/machine-tools/git.sh" "$REPO_ROOT/machine-tools/gcm.sh" "$FIXTURE/machine-tools/"
  cat >"$TEST_TMPDIR/bin/git" <<'EOF'
#!/bin/sh
if [ "$1" = version ]; then
  printf 'git version 2.29.9\n'
  exit 0
fi
exit 99
EOF
  chmod +x "$TEST_TMPDIR/bin/git"
  local hook script action output rc
  for hook in "$FIXTURE/machine-tools/git.sh install" \
    "$FIXTURE/machine-tools/git.sh config" "$FIXTURE/machine-tools/gcm.sh config"; do
    script=${hook% *}
    action=${hook##* }
    rc=0
    output="$(bash "$script" "$action" 2>&1)" || rc=$?
    assert_eq 1 "$rc"
    [[ "$output" = *'Git 2.30 or newer required (found 2.29.9)'* ]] ||
      fail "unsupported Git failure was unclear: $output"
  done
  assert_not_exists "$HOME/.config/git/portables-credentials.conf"
}

test_maintenance_gh_declares_system_package() {
  maintenance_fixture
  cp "$REPO_ROOT/machine-tools/gh.sh" "$FIXTURE/machine-tools/"
  assert_eq syspkgmgr:gh \
    "$(OS=Linux ID=ubuntu PATH=/usr/bin:/bin bash "$FIXTURE/machine-tools/gh.sh" install)"
  assert_eq syspkgmgr:github-cli \
    "$(OS=Linux ID=arch PATH=/usr/bin:/bin bash "$FIXTURE/machine-tools/gh.sh" install)"
  printf '#!/bin/sh\nexit 0\n' >"$TEST_TMPDIR/bin/gh"
  chmod +x "$TEST_TMPDIR/bin/gh"
  assert_eq '' \
    "$(OS=Linux ID=ubuntu PATH="$TEST_TMPDIR/bin:/usr/bin:/bin" bash "$FIXTURE/machine-tools/gh.sh" install)"
}

test_maintenance_git_migrates_only_legacy_pair() {
  maintenance_fixture
  cp "$REPO_ROOT/machine-tools/gcm.sh" "$FIXTURE/machine-tools/"
  ln -sf "$(command -v git)" "$TEST_TMPDIR/bin/git"
  printf '#!/bin/sh\nexit 0\n' >"$TEST_TMPDIR/bin/git-credential-manager"
  chmod +x "$TEST_TMPDIR/bin/git-credential-manager"
  export PATH="$TEST_TMPDIR/bin:/usr/bin:/bin"
  export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$HOME/.gitconfig"
  git config --file "$HOME/.gitconfig" --add credential.helper manager
  git config --file "$HOME/.gitconfig" --add credential.helper oauth
  git config --file "$HOME/.gitconfig" credential.https://example.com.helper custom-host
  bash "$FIXTURE/configure" gcm
  assert_eq $'manager\nosxkeychain' "$(git config --global --includes --get-all credential.helper)"
  assert_eq custom-host "$(git config --global --includes --get credential.https://example.com.helper)"
  local backups=( "$HOME"/.gitconfig.bak.* )
  assert_eq $'manager\noauth' "$(git config --file "${backups[0]}" --get-all credential.helper)"
}

test_maintenance_git_uses_xdg_fragments() {
  maintenance_fixture
  cp "$REPO_ROOT/machine-tools/git.sh" "$REPO_ROOT/machine-tools/gcm.sh" "$FIXTURE/machine-tools/"
  ln -sf "$(command -v git)" "$TEST_TMPDIR/bin/git"
  mkdir -p "$FIXTURE/home/.config/git"
  cp "$REPO_ROOT/home/.config/git/config" "$FIXTURE/home/.config/git/config"
  git config --file "$FIXTURE/home/.config/git/config" --unset-all user.name
  printf '#!/bin/sh\nexit 0\n' >"$TEST_TMPDIR/bin/git-credential-manager"
  chmod +x "$TEST_TMPDIR/bin/git-credential-manager"
  export PATH="$TEST_TMPDIR/bin:/usr/bin:/bin"
  bash "$FIXTURE/symlinks" .config/git/config
  unset GIT_CONFIG_GLOBAL
  GIT_NAME='Portable User' GIT_EMAIL=portable@example.com bash "$FIXTURE/configure" git gcm
  assert_eq 'Portable User' "$(git config --file "$HOME/.gitconfig" --get user.name)"
  assert_eq portable@example.com "$(git config --file "$HOME/.gitconfig" --get user.email)"
  assert_eq $'manager\nosxkeychain' \
    "$(git config --file "$HOME/.config/git/portables-credentials.conf" --get-all credential.helper)"
  assert_eq $'gitbutler_config\nlocal.conf\nportables-credentials.conf' \
    "$(git config --file "$HOME/.config/git/config" --get-all include.path)"
  assert_eq true \
    "$(git config --file "$HOME/.config/git/config" --get credential.https://dev.azure.com.useHttpPath)"
  printf 'ignored-by-xdg\n' >"$HOME/.config/git/ignore"
  mkdir "$TEST_TMPDIR/git-repo"
  git -C "$TEST_TMPDIR/git-repo" init -q
  printf 'ignored\n' >"$TEST_TMPDIR/git-repo/ignored-by-xdg"
  git -C "$TEST_TMPDIR/git-repo" check-ignore -q ignored-by-xdg || fail 'standard XDG ignore file not used'
}

test_maintenance_git_preserves_machine_overlay() {
  maintenance_fixture
  cp "$REPO_ROOT/machine-tools/git.sh" "$FIXTURE/machine-tools/"
  unset GIT_CONFIG_GLOBAL
  printf '[user]\n  name = Work User\n  email = work@example.com\n  signingKey = key-id\n' >"$HOME/.gitconfig"
  bash "$FIXTURE/configure" git
  assert_file_contents "$HOME/.gitconfig" \
    $'[user]\n  name = Work User\n  email = work@example.com\n  signingKey = key-id'
}

test_maintenance_git_manages_gh_helpers_and_legacy_root_settings() {
  maintenance_fixture
  cp "$REPO_ROOT/machine-tools/gcm.sh" "$FIXTURE/machine-tools/"
  ln -sf "$(command -v git)" "$TEST_TMPDIR/bin/git"
  mkdir -p "$FIXTURE/home/.config/git" "$HOME/.config/git"
  cp "$REPO_ROOT/home/.config/git/config" "$FIXTURE/home/.config/git/config"
  ln -s "$FIXTURE/home/.config/git/config" "$HOME/.config/git/config"
  printf '#!/bin/sh\nexit 0\n' >"$TEST_TMPDIR/bin/git-credential-manager"
  printf '#!/bin/sh\nexit 0\n' >"$TEST_TMPDIR/bin/gh"
  chmod +x "$TEST_TMPDIR/bin/git-credential-manager" "$TEST_TMPDIR/bin/gh"
  export PATH="$TEST_TMPDIR/bin:/usr/bin:/bin"
  unset GIT_CONFIG_GLOBAL
  git config --file "$HOME/.gitconfig" user.email work@example.com
  git config --file "$HOME/.gitconfig" user.signingKey key-id
  git config --file "$HOME/.gitconfig" --add credential.helper manager
  git config --file "$HOME/.gitconfig" --add core.excludesFile "$HOME/.gitignore"
  git config --file "$HOME/.gitconfig" --add core.excludesFile "$HOME/.config/git/ignore"
  git config --file "$HOME/.gitconfig" --add include.path '~/.config/git/portables-credentials.conf'
  git config --file "$HOME/.gitconfig" --add include.path '~/.config/git/portables-credentials.conf'
  for host in github.com gist.github.com; do
    git config --file "$HOME/.gitconfig" --add "credential.https://$host.helper" ''
    git config --file "$HOME/.gitconfig" --add "credential.https://$host.helper" \
      "!$TEST_TMPDIR/bin/gh auth git-credential"
  done
  bash "$FIXTURE/configure" gcm
  local managed="$HOME/.config/git/portables-credentials.conf"
  assert_eq $'manager\nosxkeychain' "$(git config --file "$managed" --get-all credential.helper)"
  for host in github.com gist.github.com; do
    assert_eq $'\n'"!'$TEST_TMPDIR/bin/gh' auth git-credential"$'\nmanager\nosxkeychain' \
      "$(git config --file "$managed" --get-all "credential.https://$host.helper")"
    if git config --file "$HOME/.gitconfig" --get-all "credential.https://$host.helper" >/dev/null; then
      fail "legacy $host helper remained in machine overlay"
    fi
  done
  assert_eq work@example.com "$(git config --file "$HOME/.gitconfig" --get user.email)"
  assert_eq key-id "$(git config --file "$HOME/.gitconfig" --get user.signingKey)"
  if git config --file "$HOME/.gitconfig" --get-all credential.helper >/dev/null; then
    fail 'legacy generic helper remained in machine overlay'
  fi
  if git config --file "$HOME/.gitconfig" --get-all core.excludesFile >/dev/null; then
    fail 'legacy excludes files remained in machine overlay'
  fi
  if git config --file "$HOME/.gitconfig" --get-all include.path >/dev/null; then
    fail 'duplicate managed include remained in machine overlay'
  fi
  local backups=( "$HOME"/.gitconfig.bak.* )
  assert_eq 1 "${#backups[@]}"
}

test_maintenance_git_preserves_custom_github_helpers() {
  maintenance_fixture
  cp "$REPO_ROOT/machine-tools/gcm.sh" "$FIXTURE/machine-tools/"
  ln -sf "$(command -v git)" "$TEST_TMPDIR/bin/git"
  printf '#!/bin/sh\nexit 0\n' >"$TEST_TMPDIR/bin/git-credential-manager"
  local gh_dir="$FIXTURE/bin-é with ' quote" gh_path quoted_gh_path gh_helper credential
  mkdir -p "$gh_dir"
  gh_path="$gh_dir/gh"
  cat >"$gh_path" <<'EOF'
#!/bin/sh
if [ "$1 $2 $3" = 'auth git-credential get' ]; then
  cat >/dev/null
  printf 'username=space-user\npassword=space-password\n'
fi
EOF
  chmod +x "$TEST_TMPDIR/bin/git-credential-manager" "$gh_path"
  cd "$FIXTURE"
  export LC_ALL=C PATH="bin-é with ' quote:$TEST_TMPDIR/bin:/usr/bin:/bin"
  git config --file "$GIT_CONFIG_GLOBAL" --add credential.helper stale
  git config --file "$GIT_CONFIG_GLOBAL" --add credential.helper ''
  git config --file "$GIT_CONFIG_GLOBAL" --add credential.helper custom-shared
  git config --file "$GIT_CONFIG_GLOBAL" credential.https://github.com.helper custom-shared
  git config --file "$GIT_CONFIG_GLOBAL" credential.https://github.com/.helper custom-slash
  git config --file "$GIT_CONFIG_GLOBAL" credential.https://GitHub.com.helper custom-case
  git config --file "$GIT_CONFIG_GLOBAL" credential.https://github.com:443.helper custom-port
  git config --file "$GIT_CONFIG_GLOBAL" credential.useHttpPath true
  git config --file "$GIT_CONFIG_GLOBAL" --add credential.https://github.com/org.helper ''
  git config --file "$GIT_CONFIG_GLOBAL" --add credential.https://github.com/org.helper custom-shared
  git config --file "$GIT_CONFIG_GLOBAL" --add credential.https://github.com/org.helper custom-path
  git config --file "$GIT_CONFIG_GLOBAL" credential.https://alice@github.com.helper custom-user
  git config --file "$GIT_CONFIG_GLOBAL" credential.https://gist.github.com.helper custom-gist
  bash "$FIXTURE/configure" gcm
  cat >>"$GIT_CONFIG_GLOBAL" <<'EOF'

[credential "https://github.com"]
  helper = after-include

[credential]
  helper = generic-after-include
EOF
  bash "$FIXTURE/configure" gcm
  local managed="$HOME/.config/git/portables-credentials.conf"
  quoted_gh_path=${gh_path//\'/\'\\\'\'}
  gh_helper="!'$quoted_gh_path' auth git-credential"
  assert_eq generic-after-include \
    "$(git config --file "$GIT_CONFIG_GLOBAL" --get-all credential.helper | tail -n 1)"
  assert_eq $'\n'"$gh_helper"$'\ncustom-shared\ncustom-slash\ncustom-case\ncustom-port' \
    "$(git config --file "$managed" --get-all credential.https://github.com.helper)"
  assert_eq $'\ncustom-shared\ncustom-path' \
    "$(git config --file "$managed" --get-all credential.https://github.com/org.helper)"
  assert_eq custom-user \
    "$(git config --file "$managed" --get-all credential.https://alice@github.com.helper)"
  assert_eq $'\n'"$gh_helper"$'\ncustom-gist\ncustom-shared' \
    "$(git config --file "$managed" --get-all credential.https://gist.github.com.helper)"
  assert_eq $'custom-shared\nafter-include' \
    "$(git config --file "$GIT_CONFIG_GLOBAL" --get-all credential.https://github.com.helper)"
  assert_eq custom-gist \
    "$(git config --file "$GIT_CONFIG_GLOBAL" --get-all credential.https://gist.github.com.helper)"
  cd "$HOME"
  credential="$(printf 'protocol=https\nhost=github.com\n\n' | git credential fill)"
  [[ "$credential" = *$'username=space-user\npassword=space-password'* ]] ||
    fail 'quoted GitHub CLI helper did not provide credentials'
}

test_maintenance_git_does_not_replay_root_overlay_helpers() {
  maintenance_fixture
  cp "$REPO_ROOT/machine-tools/gcm.sh" "$FIXTURE/machine-tools/"
  ln -sf "$(command -v git)" "$TEST_TMPDIR/bin/git"
  mkdir -p "$FIXTURE/home/.config/git" "$HOME/.config/git"
  cp "$REPO_ROOT/home/.config/git/config" "$FIXTURE/home/.config/git/config"
  ln -s "$FIXTURE/home/.config/git/config" "$HOME/.config/git/config"
  printf '#!/bin/sh\nexit 0\n' >"$TEST_TMPDIR/bin/git-credential-manager"
  printf '#!/bin/sh\nexit 0\n' >"$TEST_TMPDIR/bin/gh"
  chmod +x "$TEST_TMPDIR/bin/git-credential-manager" "$TEST_TMPDIR/bin/gh"
  export PATH="$TEST_TMPDIR/bin:/usr/bin:/bin"
  unset GIT_CONFIG_GLOBAL
  git config --file "$HOME/.gitconfig" credential.helper root-custom
  bash "$FIXTURE/configure" gcm
  local managed="$HOME/.config/git/portables-credentials.conf"
  if git config --file "$managed" --get-all credential.helper >/dev/null; then
    fail 'root overlay helper was copied into managed generic helpers'
  fi
  assert_eq $'\n'"!'$TEST_TMPDIR/bin/gh' auth git-credential" \
    "$(git config --file "$managed" --get-all credential.https://github.com.helper)"
  assert_eq root-custom "$(git config --global --includes --get-all credential.helper)"
}

test_maintenance_git_recognizes_equivalent_managed_includes() {
  maintenance_fixture
  cp "$REPO_ROOT/machine-tools/gcm.sh" "$FIXTURE/machine-tools/"
  ln -sf "$(command -v git)" "$TEST_TMPDIR/bin/git"
  printf '#!/bin/sh\nexit 0\n' >"$TEST_TMPDIR/bin/gh"
  chmod +x "$TEST_TMPDIR/bin/gh"
  export PATH="$TEST_TMPDIR/bin:/usr/bin:/bin"
  mkdir -p "$HOME/.config/git"
  local config included managed
  managed="$HOME/.config/git/portables-credentials.conf"
  for included in '~/.config/git/portables-credentials.conf' \
    '.config/git/portables-credentials.conf'; do
    config="$HOME/${included%%/*}.gitconfig"
    printf '[credential]\n  helper = before-include\n[include]\n  path = %s\n[credential]\n  helper = after-include\n' \
      "$included" >"$config"
    GIT_CONFIG_GLOBAL="$config" bash "$FIXTURE/configure" gcm
    assert_eq 1 "$(git config --file "$config" --get-all include.path | wc -l | tr -d ' ')"
    assert_eq "$included" "$(git config --file "$config" --get include.path)"
    assert_eq $'\n'"!'$TEST_TMPDIR/bin/gh' auth git-credential"$'\nbefore-include' \
      "$(git config --file "$managed" --get-all credential.https://github.com.helper)"
  done
}

test_maintenance_wrappers_preserve_failure_and_scope() {
  maintenance_fixture
  cat >"$TEST_TMPDIR/bin/bash" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$TRACE"
exit 7
EOF
  chmod +x "$TEST_TMPDIR/bin/bash"
  PORTABLES="$FIXTURE" zsh -fc '
    fpath=( "$1/home/.zfuns" $fpath )
    autoload -Uz relink retune reinstantiate
    LOG_NAME=original
    for wrapper in relink retune reinstantiate; do
      rc=0
      "$wrapper" || rc=$?
      [[ $rc != 0 && $LOG_NAME = original ]] || exit 1
    done
  ' _ "$REPO_ROOT"
  assert_eq 4 "$(wc -l <"$TRACE" | tr -d ' ')"
}

test_maintenance_wrappers_help_has_no_followup() {
  maintenance_fixture
  PORTABLES="$FIXTURE" zsh -fc '
    fpath=( "$1/home/.zfuns" $fpath )
    autoload -Uz retune
    retune --help
  ' _ "$REPO_ROOT"
  assert_not_exists "$HOME/.zshrc"
}

test_case 'maintenance: configuration initializes context and continues independently' test_maintenance_configure_context_and_continuation
test_case 'maintenance: validates complete invocation before work' test_maintenance_validation_precedes_work
test_case 'maintenance: bootstrap configures existing tools once after installation' test_maintenance_bootstrap_configures_once_after_install
test_case 'maintenance: failed installations block only their owner' test_maintenance_install_failure_blocks_only_owner
test_case 'maintenance: failed requirement hooks block only their owner' test_maintenance_requirement_hook_failure_blocks_only_owner
test_case 'maintenance: unknown requirements block installation' test_maintenance_unknown_requirement_blocks_installation
test_case 'maintenance: casks use brew install' test_maintenance_cask_dispatch
test_case 'maintenance: system packages use deduplicated batches' test_maintenance_batches_system_packages
test_case 'maintenance: failed package batches retry only missing packages' test_maintenance_failed_batch_retries_missing_packages
test_case 'maintenance: bootstrap packages share one transaction' test_maintenance_batches_bootstrap_packages
test_case 'maintenance: gh declares its system package when missing' test_maintenance_gh_declares_system_package
test_case 'maintenance: Git defaults follow OS and preserve custom helpers' test_maintenance_git_defaults_and_custom_helpers
test_case 'maintenance: Git requires version 2.30 or newer' test_maintenance_git_requires_supported_version
test_case 'maintenance: Git migrates exact legacy pair and preserves host helpers' test_maintenance_git_migrates_only_legacy_pair
test_case 'maintenance: Git writes generated settings through XDG fragments' test_maintenance_git_uses_xdg_fragments
test_case 'maintenance: Git preserves the machine-specific overlay' test_maintenance_git_preserves_machine_overlay
test_case 'maintenance: Git manages gh helpers and legacy root settings' test_maintenance_git_manages_gh_helpers_and_legacy_root_settings
test_case 'maintenance: Git preserves custom GitHub helpers' test_maintenance_git_preserves_custom_github_helpers
test_case 'maintenance: Git does not replay root overlay helpers' test_maintenance_git_does_not_replay_root_overlay_helpers
test_case 'maintenance: Git recognizes equivalent managed includes' test_maintenance_git_recognizes_equivalent_managed_includes
test_case 'maintenance: Zsh wrappers preserve failures and caller state' test_maintenance_wrappers_preserve_failure_and_scope
test_case 'maintenance: wrapper help does not relink or prompt' test_maintenance_wrappers_help_has_no_followup

test_maintenance_linux_package_backends() {
  maintenance_fixture
  cat >"$TEST_TMPDIR/bin/sudo" <<'EOF'
#!/bin/sh
exec "$@"
EOF
  cat >"$TEST_TMPDIR/bin/package-stub" <<'EOF'
#!/usr/bin/env bash
printf '%s %s\n' "${0##*/}" "$*" >>"$TRACE"
backend=${0##*/}
case "$backend:$1" in
  dnf:check-update) exit 100 ;;
  dpkg-query:*) grep -qx "apt:${!#}" "$PACKAGE_STATE" && printf 'install ok installed';;
  rpm:*) grep -qx "dnf:${!#}" "$PACKAGE_STATE" ;;
  pacman:-Q) grep -qx "pacman:$2" "$PACKAGE_STATE" ;;
  apt-get:install|dnf:install|pacman:-S)
    case "$backend" in apt-get) kind=apt ;; *) kind=$backend ;; esac
    for package in "$@"; do
      [[ "$package" = -* || "$package" = install ]] && continue
      grep -qx "$kind:$package" "$PACKAGE_STATE" || printf '%s:%s\n' "$kind" "$package" >>"$PACKAGE_STATE"
    done
    ;;
esac
EOF
  chmod +x "$TEST_TMPDIR/bin/"*
  local cmd distro
  for cmd in apt-get dpkg-query rpm dnf pacman; do
    ln -s package-stub "$TEST_TMPDIR/bin/$cmd"
  done
  printf '[[ "$1" != install ]] || echo syspkgmgr:example\n' >"$FIXTURE/machine-tools/a.sh"
  for distro in ubuntu debian pop arch fedora; do
    : >"$PACKAGE_STATE"
    OS=Linux ID="$distro" bash "$FIXTURE/instantiate"
  done
  grep -q '^apt-get install -y example$' "$TRACE" || fail 'apt dispatch missing'
  grep -q '^pacman -S --needed --noconfirm example$' "$TRACE" || fail 'pacman dispatch missing'
  grep -q '^dnf install -y example$' "$TRACE" || fail 'dnf status 100 rejected'
  if grep -qE 'upgrade|-Syu|-Sy ' "$TRACE"; then fail 'unexpected blanket upgrade or partial refresh'; fi
}

test_maintenance_language_backends_and_ordering() {
  maintenance_fixture
  mkdir -p "$HOME/.nvm"
  cat >"$HOME/.nvm/nvm.sh" <<'EOF'
nvm() {
  printf 'nvm %s\n' "$*" >>"$TRACE"
  if [[ "$1" = version ]]; then printf 'N/A\n'; return 3; fi
}
EOF
  cat >"$TEST_TMPDIR/bin/language-stub" <<'EOF'
#!/usr/bin/env bash
printf '%s %s\n' "${0##*/}" "$*" >>"$TRACE"
case "${0##*/}:$1:$2" in
  uv:python:find|npm:list:*) exit 1 ;;
esac
EOF
  chmod +x "$TEST_TMPDIR/bin/language-stub"
  local cmd
  for cmd in uv python3 pipx npm; do ln -s language-stub "$TEST_TMPDIR/bin/$cmd"; done
  cat >"$FIXTURE/machine-tools/a.sh" <<'EOF'
case "$1" in
  install)
    printf '%s\n' uv:ruff uv:python:3.12 uv:python:3.13 nvm:20 nvm:22 pip:example pipx:one pipx:two npm:example
    ;;
  config) echo configured >>"$TRACE" ;;
esac
EOF
  bash "$FIXTURE/instantiate"
  grep -q '^uv python install 3.12$' "$TRACE" || fail 'Python request lost'
  grep -q '^uv python install 3.13$' "$TRACE" || fail 'second Python request lost'
  grep -q '^nvm install 20$' "$TRACE" || fail 'Node request lost'
  grep -q '^nvm install 22$' "$TRACE" || fail 'second Node request lost'
  grep -q '^python3 -m pip install --user example$' "$TRACE" || fail 'pip dispatch missing'
  grep -q '^pipx install one$' "$TRACE" || fail 'pipx request lost'
  grep -q '^pipx install two$' "$TRACE" || fail 'second pipx request lost'
  assert_eq configured "$(tail -1 "$TRACE")"
  if grep -qE 'self update|install -U|pipx install one two' "$TRACE"; then fail 'unexpected upgrade or batching'; fi
}

test_maintenance_nvm_activates_node_for_npm() {
  maintenance_fixture
  mkdir -p "$HOME/.nvm"
  cat >"$HOME/.nvm/nvm.sh" <<'EOF'
nvm() {
  printf 'nvm %s\n' "$*" >>"$TRACE"
  case "$1" in
    version) printf 'v24.0.0\n' ;;
    use) export NODE_ACTIVE=1 ;;
  esac
}
EOF
  cat >"$TEST_TMPDIR/bin/npm" <<'EOF'
#!/usr/bin/env bash
[[ "${NODE_ACTIVE:-}" = 1 ]] || exit 7
printf 'npm %s\n' "$*" >>"$TRACE"
[[ "$1" != list ]]
EOF
  chmod +x "$TEST_TMPDIR/bin/npm"
  cat >"$FIXTURE/machine-tools/a.sh" <<'EOF'
case "$1" in
  install) printf '%s\n' nvm:--lts npm:example ;;
  config) echo configured >>"$TRACE" ;;
esac
EOF
  bash "$FIXTURE/instantiate"
  grep -q '^nvm use --lts$' "$TRACE" || fail 'installed Node version was not activated'
  grep -q '^npm install -g example$' "$TRACE" || fail 'npm did not inherit the active Node environment'
  assert_eq configured "$(tail -1 "$TRACE")"
}

test_maintenance_bash32_bootstrap() {
  maintenance_fixture
  ln -s /bin/bash "$TEST_TMPDIR/bin/bash"
  printf '[[ "$1" != install ]] || echo syspkgmgr:example\n' >"$FIXTURE/machine-tools/a.sh"
  /bin/bash "$FIXTURE/instantiate"
  assert_exists "$HOME/.maintenance-test.env"
}

test_maintenance_hook_protocol() {
  local script rc
  for script in "$REPO_ROOT"/machine-tools/*.sh; do
    rc=0
    bash "$script" unknown >/dev/null 2>&1 || rc=$?
    assert_eq 2 "$rc" "invalid action accepted by $script"
    bash "$script" --help >/dev/null
  done
}

test_maintenance_configs_do_not_upgrade_or_rewrite_payload() {
  maintenance_fixture
  cp "$REPO_ROOT/machine-tools/python.sh" "$REPO_ROOT/machine-tools/bash.sh" "$FIXTURE/machine-tools/"
  mkdir -p "$HOME/monty/.venv/bin" "$HOME/.config/python" "$HOME/.oh-my-bash"
  printf '#!/bin/sh\nexit 0\n' >"$HOME/monty/.venv/bin/python"
  chmod +x "$HOME/monty/.venv/bin/python"
  printf '# framework\n' >"$HOME/.oh-my-bash/oh-my-bash.sh"
  printf example >"$HOME/.config/python/monty"
  cat >"$TEST_TMPDIR/bin/uv" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$TRACE"
EOF
  chmod +x "$TEST_TMPDIR/bin/uv"
  bash "$FIXTURE/configure" python bash
  if grep -q -- '-U\|upgrade\|venv --' "$TRACE"; then fail 'existing environment changed unnecessarily'; fi
  grep -q '^pip install --python ' "$TRACE" || fail 'missing requirements not ensured'
  assert_not_exists "$FIXTURE/home/.bashrc"
}

test_maintenance_go_removes_partial_tree_before_restore() {
  maintenance_fixture
  cp "$REPO_ROOT/machine-tools/go.sh" "$FIXTURE/machine-tools/"
  export GO_BACKUP="$TEST_TMPDIR/go-backup"
  export GO_INSTALL_ROOT="$TEST_TMPDIR/usr-local-go"
  mkdir -p "$GO_INSTALL_ROOT"
  cat >"$TEST_TMPDIR/bin/curl" <<'EOF'
#!/usr/bin/env bash
while [[ $# -gt 0 ]]; do
  if [[ "$1" = -o ]]; then : >"$2"; exit 0; fi
  shift
done
exit 2
EOF
  cat >"$TEST_TMPDIR/bin/tar" <<'EOF'
#!/usr/bin/env bash
while [[ $# -gt 0 ]]; do
  if [[ "$1" = -C ]]; then directory=$2; break; fi
  shift
done
mkdir -p "$directory/go/bin"
printf '#!/bin/sh\nexit 0\n' >"$directory/go/bin/go"
chmod +x "$directory/go/bin/go"
EOF
  cat >"$TEST_TMPDIR/bin/sudo" <<'EOF'
#!/usr/bin/env bash
printf 'sudo %s\n' "$*" >>"$TRACE"
case "$1" in
  mktemp) mkdir -p "$GO_BACKUP/go"; printf '%s\n' "$GO_BACKUP" ;;
  mv)
    if [[ "$2" != "$GO_INSTALL_ROOT" && "$2" != "$GO_BACKUP/go" && "$3" = "$GO_INSTALL_ROOT" ]]; then
      exit 1
    fi
    ;;
esac
EOF
  chmod +x "$TEST_TMPDIR/bin/curl" "$TEST_TMPDIR/bin/tar" "$TEST_TMPDIR/bin/sudo"
  if bash "$FIXTURE/machine-tools/go.sh" self-install; then fail 'failed Go install returned success'; fi
  local remove_line restore_line
  remove_line="$(grep -Fn "sudo rm -rf -- $GO_INSTALL_ROOT" "$TRACE" | cut -d: -f1)"
  restore_line="$(grep -Fn "sudo mv $GO_BACKUP/go $GO_INSTALL_ROOT" "$TRACE" | cut -d: -f1)"
  [[ -n "$remove_line" && -n "$restore_line" && "$remove_line" -lt "$restore_line" ]] ||
    fail 'previous Go tree restored before removing partial destination'
}

test_case 'maintenance: existing Linux package managers dispatch without blanket upgrades' test_maintenance_linux_package_backends
test_case 'maintenance: language backends preserve requests and configure last' test_maintenance_language_backends_and_ordering
test_case 'maintenance: NVM activates Node for the npm phase' test_maintenance_nvm_activates_node_for_npm
test_case 'maintenance: bootstrap runs with system Bash' test_maintenance_bash32_bootstrap
test_case 'maintenance: every hook validates actions and supports help' test_maintenance_hook_protocol
test_case 'maintenance: configuration completes missing setup without upgrades' test_maintenance_configs_do_not_upgrade_or_rewrite_payload
test_case 'maintenance: failed Go install removes partial tree before restore' test_maintenance_go_removes_partial_tree_before_restore

test_maintenance_skipped_requirement_does_not_block_independent_owner() {
  maintenance_fixture
  cat >"$FIXTURE/machine-tools/a.sh" <<'EOF'
case "$1" in install) printf 'syspkgmgr:broken\nsyspkgmgr:shared\n' ;; esac
EOF
  cat >"$FIXTURE/machine-tools/b.sh" <<'EOF'
case "$1" in install) echo syspkgmgr:shared ;; config) echo independent >>"$TRACE" ;; esac
EOF
  if bash "$FIXTURE/instantiate"; then fail 'failure hidden'; fi
  grep -q '^brew install --formula broken shared$' "$TRACE" || fail 'system requirements were not batched'
  grep -q '^independent$' "$TRACE" || fail 'independent owner incorrectly blocked'
}

test_maintenance_machine_env_preserves_settings_and_mode() {
  maintenance_fixture
  printf 'export EXTRA=preserved\nexport PORTABLES=/old\n' >"$FIXTURE/home/.maintenance-test.env"
  chmod 640 "$FIXTURE/home/.maintenance-test.env"
  printf '[[ "$1" != config ]] || printf "%%s" "$EXTRA" >>"$TRACE"\n' >"$FIXTURE/machine-tools/a.sh"
  bash "$FIXTURE/instantiate"
  assert_symlink_to "$HOME/.maintenance-test.env" "$FIXTURE/home/.maintenance-test.env"
  grep -q '^export EXTRA=preserved$' "$FIXTURE/home/.maintenance-test.env" || fail 'setting removed'
  assert_eq 1 "$(grep -c '^export PORTABLES=' "$FIXTURE/home/.maintenance-test.env")"
  assert_eq preserved "$(tail -1 "$TRACE")"
  local mode
  mode="$(stat -c '%a' "$FIXTURE/home/.maintenance-test.env" 2>/dev/null || stat -f '%Lp' "$FIXTURE/home/.maintenance-test.env")"
  assert_eq 640 "$mode"
  printf 'export WRITTEN_THROUGH_HOME=1\n' >>"$HOME/.maintenance-test.env"
  grep -q '^export WRITTEN_THROUGH_HOME=1$' "$FIXTURE/home/.maintenance-test.env" ||
    fail 'home machine environment does not write through to repository source'
}

test_maintenance_machine_env_preserves_home_conflict() {
  maintenance_fixture
  printf 'local machine settings\n' >"$HOME/.maintenance-test.env"
  printf '[[ "$1" != config ]] || echo configured >>"$TRACE"\n' >"$FIXTURE/machine-tools/a.sh"
  if bash "$FIXTURE/instantiate"; then fail 'conflicting home machine environment accepted'; fi
  assert_file_contents "$HOME/.maintenance-test.env" 'local machine settings'
  assert_eq configured "$(tail -1 "$TRACE")"
}

test_maintenance_machine_env_rejects_repository_symlink() {
  maintenance_fixture
  printf 'external settings\n' >"$TEST_TMPDIR/external.env"
  ln -s "$TEST_TMPDIR/external.env" "$FIXTURE/home/.maintenance-test.env"
  local output rc=0
  output="$(bash "$FIXTURE/instantiate" 2>&1)" || rc=$?
  assert_eq 1 "$rc"
  [[ "$output" = *'repository machine env must not be a symlink:'* ]] ||
    fail 'repository source rejection was unclear'
  assert_file_contents "$TEST_TMPDIR/external.env" 'external settings'
}

test_maintenance_symlinked_entrypoints() {
  maintenance_fixture
  ln -s "$FIXTURE/configure" "$TEST_TMPDIR/configure-link"
  printf 'printf "%%s" "$PORTABLES" >"$TRACE"\n' >"$FIXTURE/machine-tools/a.sh"
  bash "$TEST_TMPDIR/configure-link" a
  assert_file_contents "$TRACE" "$FIXTURE"
}

test_maintenance_git_refuses_source_writes() {
  maintenance_fixture
  cp "$REPO_ROOT/machine-tools/gcm.sh" "$FIXTURE/machine-tools/"
  export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$FIXTURE/home/tracked-gitconfig"
  printf '[user]\n  name = preserved\n' >"$GIT_CONFIG_GLOBAL"
  if bash "$FIXTURE/configure" gcm; then fail 'repository config accepted as runtime destination'; fi
  assert_file_contents "$GIT_CONFIG_GLOBAL" $'[user]\n  name = preserved'
}

test_maintenance_restart_responses() {
  maintenance_fixture
  export WRAPPER_REPO="$REPO_ROOT" PORTABLES="$FIXTURE" SHELL="$TEST_TMPDIR/fake-shell"
  printf '#!/bin/sh\nprintf "RESULT:replaced:end\\n"\n' >"$SHELL"
  printf '#!/bin/sh\n: >"%s/fallback-used"\n' "$TEST_TMPDIR" >"$TEST_TMPDIR/fallback-shell"
  chmod +x "$SHELL"
  chmod +x "$TEST_TMPDIR/fallback-shell"
  cat >"$TEST_TMPDIR/wrapper.zsh" <<'EOF'
fpath=( "$WRAPPER_REPO/home/.zfuns" $fpath )
autoload -Uz relink
[[ -z "${FALLBACK_SHELL:-}" ]] || commands[zsh]="$FALLBACK_SHELL"
relink
print "RESULT:return:${?}:end"
EOF
  zsh -fc '
    zmodload zsh/zpty || exit 1
    for answer in n N "" y Y; do
      zpty -b worker zsh -fi "$1/wrapper.zsh"
      output= ready=0 chunk=
      for ((attempt = 0; attempt < 200; attempt++)); do
        chunk=
        zpty -r worker chunk
        output+=$chunk
        if [[ "$output" = *"replace the shell now?"* ]]; then ready=1; break; fi
        sleep 0.05
      done
      (( ready )) || { zpty -d worker; print -u2 "prompt missing: $output"; exit 1; }
      printf -v input "%s\n" "$answer"
      zpty -w -n worker "$input"
      output= ready=0 chunk=
      for ((attempt = 0; attempt < 200; attempt++)); do
        chunk=
        zpty -r worker chunk
        output+=$chunk
        if [[ "$output" = *RESULT:*:end* ]]; then ready=1; break; fi
        sleep 0.05
      done
      zpty -d worker
      (( ready )) || { print -u2 "result missing for answer [$answer]: $output"; exit 1; }
      case "$answer" in
        y|Y) [[ "$output" = *RESULT:replaced:end* ]] || exit 1 ;;
        *) [[ "$output" = *RESULT:return:0:end* ]] || exit 1 ;;
      esac
    done
    export SHELL=-zsh FALLBACK_SHELL="$1/fallback-shell"
    zpty -b worker zsh -fi "$1/wrapper.zsh"
    output= ready=0 chunk=
    for ((attempt = 0; attempt < 200; attempt++)); do
      chunk=
      zpty -r worker chunk
      output+=$chunk
      if [[ "$output" = *"replace the shell now?"* ]]; then ready=1; break; fi
      sleep 0.05
    done
    (( ready )) || { zpty -d worker; print -u2 "fallback prompt missing: $output"; exit 1; }
    printf -v input "%s\n" y
    zpty -w -n worker "$input"
    output= ready=0 chunk=
    for ((attempt = 0; attempt < 200; attempt++)); do
      if [[ -e "$1/fallback-used" ]]; then ready=1; break; fi
      chunk=
      zpty -r worker chunk 2>/dev/null || true
      output+=$chunk
      sleep 0.05
    done
    zpty -d worker
    (( ready )) || {
      print -u2 "fallback shell not used: $output"
      exit 1
    }
  ' _ "$TEST_TMPDIR"
}

test_maintenance_relink_help_skips_restart() {
  maintenance_fixture
  export WRAPPER_REPO="$REPO_ROOT" PORTABLES="$FIXTURE"
  cat >"$TEST_TMPDIR/wrapper-help.zsh" <<'EOF'
fpath=( "$WRAPPER_REPO/home/.zfuns" $fpath )
autoload -Uz relink
relink --force --help
print "RESULT:return:${?}:end"
EOF
  zsh -fc '
    zmodload zsh/zpty || exit 1
    zpty -b worker zsh -fi "$1/wrapper-help.zsh"
    output= ready=0 chunk=
    for ((attempt = 0; attempt < 200; attempt++)); do
      chunk=
      zpty -r worker chunk
      output+=$chunk
      [[ "$output" != *"replace the shell now?"* ]] || {
        zpty -d worker
        print -u2 "help prompted for shell replacement: $output"
        exit 1
      }
      if [[ "$output" = *RESULT:return:0:end* ]]; then ready=1; break; fi
      sleep 0.05
    done
    zpty -d worker
    (( ready )) || { print -u2 "help invocation did not return: $output"; exit 1; }
  ' _ "$TEST_TMPDIR"
}

zsh_config_fixture() {
  maintenance_fixture
  cp "$REPO_ROOT/machine-tools/zsh.sh" "$FIXTURE/machine-tools/"
  export ZMV_TARGET="$TEST_TMPDIR/current/share/zsh/5.10/functions/zmv"
  mkdir -p "$(dirname "$ZMV_TARGET")" "$HOME/.zfuns" "$FIXTURE/home/.zfuns"
  printf '# zmv\n' >"$ZMV_TARGET"
  cat >"$TEST_TMPDIR/bin/zsh" <<'EOF'
#!/bin/sh
printf '%s\n' "$ZMV_TARGET"
EOF
  chmod +x "$TEST_TMPDIR/bin/zsh"
  mkdir -p "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting" \
    "$HOME/.oh-my-zsh/custom/plugins/zsh-completions" \
    "$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions" \
    "$HOME/.oh-my-zsh/custom/plugins/zsh-autocomplete" \
    "$HOME/.oh-my-zsh/custom/themes/powerlevel10k"
  printf '# framework\n' >"$HOME/.oh-my-zsh/oh-my-zsh.sh"
}

test_maintenance_zsh_migrates_managed_function_links() {
  zsh_config_fixture
  ln -s "$FIXTURE/home/.zfuns/zcp" "$HOME/.zfuns/zcp"
  ln -s "$ZMV_TARGET" "$FIXTURE/home/.zfuns/zln"
  ln -s "$FIXTURE/home/.zfuns/zln" "$HOME/.zfuns/zln"
  bash "$FIXTURE/configure" zsh
  assert_symlink_to "$HOME/.zfuns/zcp" "$ZMV_TARGET"
  assert_symlink_to "$HOME/.zfuns/zln" "$ZMV_TARGET"

  ln -sfn "$TEST_TMPDIR/old/share/zsh/5.9/functions/zmv" "$HOME/.zfuns/zcp"
  bash "$FIXTURE/configure" zsh
  assert_symlink_to "$HOME/.zfuns/zcp" "$ZMV_TARGET"
  assert_symlink_to "$HOME/.zfuns/zln" "$ZMV_TARGET"
}

test_maintenance_zsh_preserves_unmanaged_function_links() {
  zsh_config_fixture
  printf '# custom\n' >"$TEST_TMPDIR/custom-zmv"
  ln -s "$TEST_TMPDIR/missing-custom" "$HOME/.zfuns/zcp"
  ln -s "$TEST_TMPDIR/custom-zmv" "$HOME/.zfuns/zln"
  if bash "$FIXTURE/configure" zsh; then fail 'unrelated broken function link accepted'; fi
  assert_symlink_to "$HOME/.zfuns/zcp" "$TEST_TMPDIR/missing-custom"
  assert_symlink_to "$HOME/.zfuns/zln" "$TEST_TMPDIR/custom-zmv"
}

test_case 'maintenance: unattempted requirements do not poison independent owners' test_maintenance_skipped_requirement_does_not_block_independent_owner
test_case 'maintenance: machine environment preserves settings and permissions' test_maintenance_machine_env_preserves_settings_and_mode
test_case 'maintenance: machine environment preserves conflicting home files' test_maintenance_machine_env_preserves_home_conflict
test_case 'maintenance: machine environment source must be a regular file' test_maintenance_machine_env_rejects_repository_symlink
test_case 'maintenance: symlinked entrypoints find their repository' test_maintenance_symlinked_entrypoints
test_case 'maintenance: Git never writes runtime settings into the repository' test_maintenance_git_refuses_source_writes
test_case 'maintenance: interactive restart accepts y/Y and declines Enter/n/N' test_maintenance_restart_responses
test_case 'maintenance: relink help after options skips restart' test_maintenance_relink_help_skips_restart
test_case 'maintenance: Zsh migrates only recognized function links' test_maintenance_zsh_migrates_managed_function_links
test_case 'maintenance: Zsh preserves unmanaged function links' test_maintenance_zsh_preserves_unmanaged_function_links

test_maintenance_default_python_reuses_installed_version() {
  maintenance_fixture
  cat >"$TEST_TMPDIR/bin/uv" <<'EOF'
#!/bin/sh
printf 'uv %s\n' "$*" >>"$TRACE"
if [ "$1 $2" = 'python find' ]; then command -v managed-python; fi
EOF
  printf '#!/bin/sh\nprintf "3.12.9\\n"\n' >"$TEST_TMPDIR/bin/managed-python"
  chmod +x "$TEST_TMPDIR/bin/uv" "$TEST_TMPDIR/bin/managed-python"
  printf '[[ "$1" != install ]] || echo uv:python:--default\n' >"$FIXTURE/machine-tools/a.sh"
  bash "$FIXTURE/instantiate"
  grep -q '^uv python install 3.12.9 --default$' "$TRACE" || fail 'default links would select a new Python version'
}

test_case 'maintenance: default Python setup retains the installed version' test_maintenance_default_python_reuses_installed_version

test_maintenance_python_creates_fresh_monty_directory() {
  maintenance_fixture
  cp "$REPO_ROOT/machine-tools/python.sh" "$FIXTURE/machine-tools/"
  mkdir -p "$HOME/.config/python"
  printf example >"$HOME/.config/python/monty"
  cat >"$TEST_TMPDIR/bin/uv" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" = venv ]]; then
  while [[ $# -gt 0 ]]; do
    if [[ "$1" = --directory ]]; then directory="$2"; break; fi
    shift
  done
  [[ -d "$directory" ]] || exit 2
  mkdir -p "$directory/.venv/bin"
  printf '#!/bin/sh\n' >"$directory/.venv/bin/python"
  chmod +x "$directory/.venv/bin/python"
fi
EOF
  chmod +x "$TEST_TMPDIR/bin/uv"
  bash "$FIXTURE/configure" python
  assert_exists "$HOME/monty/.venv/bin/python"
}

test_maintenance_stale_metadata_allows_installed_requirements() {
  maintenance_fixture
  export OS=Linux ID=ubuntu
  cat >"$TEST_TMPDIR/bin/sudo" <<'EOF'
#!/bin/sh
exec "$@"
EOF
  cat >"$TEST_TMPDIR/bin/apt-get" <<'EOF'
#!/bin/sh
printf 'apt-get %s\n' "$*" >>"$TRACE"
[[ "$1" != update ]]
EOF
  cat >"$TEST_TMPDIR/bin/dpkg-query" <<'EOF'
#!/bin/sh
printf 'install ok installed'
EOF
  chmod +x "$TEST_TMPDIR/bin/sudo" "$TEST_TMPDIR/bin/apt-get" "$TEST_TMPDIR/bin/dpkg-query"
  cat >"$FIXTURE/machine-tools/a.sh" <<'EOF'
case "$1" in
  install) echo syspkgmgr:already-installed ;;
  config) echo configured >>"$TRACE" ;;
esac
EOF
  if bash "$FIXTURE/instantiate"; then fail 'metadata failure hidden'; fi
  grep -q '^configured$' "$TRACE" || fail 'installed requirement incorrectly blocked configuration'
  if grep -q '^apt-get install' "$TRACE"; then fail 'installed package was reinstalled'; fi
}

test_case 'maintenance: Python creates Monty before using it as uv working directory' test_maintenance_python_creates_fresh_monty_directory
test_case 'maintenance: stale metadata preserves installed requirements' test_maintenance_stale_metadata_allows_installed_requirements
