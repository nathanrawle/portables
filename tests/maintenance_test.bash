#!/usr/bin/env bash

maintenance_fixture() {
  export FIXTURE="$TEST_TMPDIR/repo with spaces"
  export HOME="$TEST_TMPDIR/home with spaces"
  export TRACE="$TEST_TMPDIR/trace"
  export OS=Darwin ID= VERSION_ID= HOST=maintenance-test
  export PATH="$TEST_TMPDIR/bin:$PATH"
  mkdir -p "$FIXTURE/home" "$FIXTURE/machine-tools" "$HOME" "$TEST_TMPDIR/bin"
  FIXTURE="$(cd "$FIXTURE" && pwd -P)"
  HOME="$(cd "$HOME" && pwd -P)"
  export XDG_CONFIG_HOME="$HOME/.config" GIT_CONFIG_GLOBAL="$HOME/.gitconfig" GIT_CONFIG_NOSYSTEM=1
  unset BASH_ENV ENV GIT_CONFIG_SYSTEM GIT_CONFIG_COUNT
  cp "$REPO_ROOT/instantiate" "$REPO_ROOT/configure" "$REPO_ROOT/symlinks" "$REPO_ROOT/log" "$FIXTURE/"
  cp -R "$REPO_ROOT/lib" "$FIXTURE/lib"
  printf 'shell\n' >"$FIXTURE/home/.zshrc"
  cat >"$TEST_TMPDIR/bin/brew" <<'EOF'
#!/usr/bin/env bash
printf 'brew %s\n' "$*" >>"$TRACE"
case "$1" in
  list) exit 1 ;;
  install) [[ "$*" != *broken* ]] ;;
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

test_maintenance_git_defaults_and_custom_helpers() {
  maintenance_fixture
  cp "$REPO_ROOT/machine-tools/gcm.sh" "$FIXTURE/machine-tools/"
  printf '#!/bin/sh\nexit 0\n' >"$TEST_TMPDIR/bin/git-credential-manager"
  printf '#!/bin/sh\nexit 0\n' >"$TEST_TMPDIR/bin/git-credential-oauth"
  chmod +x "$TEST_TMPDIR/bin/"*
  export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$HOME/.gitconfig"
  bash "$FIXTURE/configure" gcm
  assert_eq manager "$(git config --global --includes --get-all credential.helper)"
  OS=Linux ID=ubuntu bash "$FIXTURE/configure" gcm
  assert_eq $'cache --timeout 21600\noauth' "$(git config --global --includes --get-all credential.helper)"
  OS=Linux ID=ubuntu bash "$FIXTURE/configure" gcm
  assert_eq 1 "$(git config --file "$HOME/.gitconfig" --get-all include.path | wc -l | tr -d ' ')"
  git config --file "$HOME/.gitconfig" --add credential.helper custom
  bash "$FIXTURE/configure" gcm
  assert_eq custom "$(git config --global --includes --get-all credential.helper)"
}

test_maintenance_git_migrates_only_legacy_pair() {
  maintenance_fixture
  cp "$REPO_ROOT/machine-tools/gcm.sh" "$FIXTURE/machine-tools/"
  printf '#!/bin/sh\nexit 0\n' >"$TEST_TMPDIR/bin/git-credential-manager"
  chmod +x "$TEST_TMPDIR/bin/git-credential-manager"
  export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$HOME/.gitconfig"
  git config --file "$HOME/.gitconfig" --add credential.helper manager
  git config --file "$HOME/.gitconfig" --add credential.helper oauth
  git config --file "$HOME/.gitconfig" credential.https://example.com.helper custom-host
  bash "$FIXTURE/configure" gcm
  assert_eq manager "$(git config --global --includes --get-all credential.helper)"
  assert_eq custom-host "$(git config --global --includes --get credential.https://example.com.helper)"
  local backups=( "$HOME"/.gitconfig.bak.* )
  assert_eq $'manager\noauth' "$(git config --file "${backups[0]}" --get-all credential.helper)"
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
test_case 'maintenance: unknown requirements block installation' test_maintenance_unknown_requirement_blocks_installation
test_case 'maintenance: casks use brew install' test_maintenance_cask_dispatch
test_case 'maintenance: Git defaults follow OS and preserve custom helpers' test_maintenance_git_defaults_and_custom_helpers
test_case 'maintenance: Git migrates exact legacy pair and preserves host helpers' test_maintenance_git_migrates_only_legacy_pair
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
case "${0##*/}:$1" in
  dnf:check-update) exit 100 ;;
  dpkg-query:*|rpm:*|pacman:-Q) exit 1 ;;
esac
EOF
  chmod +x "$TEST_TMPDIR/bin/"*
  local cmd distro
  for cmd in apt-get dpkg-query rpm dnf pacman; do
    ln -s package-stub "$TEST_TMPDIR/bin/$cmd"
  done
  printf '[[ "$1" != install ]] || echo syspkgmgr:example\n' >"$FIXTURE/machine-tools/a.sh"
  for distro in ubuntu debian pop arch fedora; do
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

test_case 'maintenance: existing Linux package managers dispatch without blanket upgrades' test_maintenance_linux_package_backends
test_case 'maintenance: language backends preserve requests and configure last' test_maintenance_language_backends_and_ordering
test_case 'maintenance: bootstrap runs with system Bash' test_maintenance_bash32_bootstrap
test_case 'maintenance: every hook validates actions and supports help' test_maintenance_hook_protocol
test_case 'maintenance: configuration completes missing setup without upgrades' test_maintenance_configs_do_not_upgrade_or_rewrite_payload

test_maintenance_skipped_requirement_does_not_block_independent_owner() {
  maintenance_fixture
  cat >"$FIXTURE/machine-tools/a.sh" <<'EOF'
case "$1" in install) printf 'syspkgmgr:broken\nsyspkgmgr:shared\n' ;; esac
EOF
  cat >"$FIXTURE/machine-tools/b.sh" <<'EOF'
case "$1" in install) echo syspkgmgr:shared ;; config) echo independent >>"$TRACE" ;; esac
EOF
  if bash "$FIXTURE/instantiate"; then fail 'failure hidden'; fi
  grep -q '^brew install --formula shared$' "$TRACE" || fail 'shared requirement incorrectly blocked'
  grep -q '^independent$' "$TRACE" || fail 'independent owner incorrectly blocked'
}

test_maintenance_machine_env_preserves_settings_and_mode() {
  maintenance_fixture
  printf 'export EXTRA=preserved\nexport PORTABLES=/old\n' >"$FIXTURE/home/.maintenance-test.env"
  chmod 640 "$FIXTURE/home/.maintenance-test.env"
  printf '[[ "$1" != config ]] || printf "%%s" "$EXTRA" >>"$TRACE"\n' >"$FIXTURE/machine-tools/a.sh"
  bash "$FIXTURE/instantiate"
  grep -q '^export EXTRA=preserved$' "$FIXTURE/home/.maintenance-test.env" || fail 'setting removed'
  assert_eq 1 "$(grep -c '^export PORTABLES=' "$FIXTURE/home/.maintenance-test.env")"
  assert_eq preserved "$(tail -1 "$TRACE")"
  local mode
  mode="$(stat -c '%a' "$FIXTURE/home/.maintenance-test.env" 2>/dev/null || stat -f '%Lp' "$FIXTURE/home/.maintenance-test.env")"
  assert_eq 640 "$mode"
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
  chmod +x "$SHELL"
  cat >"$TEST_TMPDIR/wrapper.zsh" <<'EOF'
fpath=( "$WRAPPER_REPO/home/.zfuns" $fpath )
autoload -Uz relink
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
        n|N) [[ "$output" = *RESULT:return:0:end* ]] || exit 1 ;;
        *) [[ "$output" = *RESULT:replaced:end* ]] || exit 1 ;;
      esac
    done
  ' _ "$TEST_TMPDIR"
}

test_case 'maintenance: unattempted requirements do not poison independent owners' test_maintenance_skipped_requirement_does_not_block_independent_owner
test_case 'maintenance: machine environment preserves settings and permissions' test_maintenance_machine_env_preserves_settings_and_mode
test_case 'maintenance: symlinked entrypoints find their repository' test_maintenance_symlinked_entrypoints
test_case 'maintenance: Git never writes runtime settings into the repository' test_maintenance_git_refuses_source_writes
test_case 'maintenance: interactive restart accepts Enter/y/Y and declines n/N' test_maintenance_restart_responses

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
