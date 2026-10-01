test_codex_shell_alias_forwards_arguments() {
  local shell="$1" bin home output

  bin="$TEST_TMPDIR/bin"
  home="$TEST_TMPDIR/home"
  mkdir -p "$bin" "$home"
  cat >"$bin/codex" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@"
EOF
  chmod +x "$bin/codex"

  output="$(HOME="$home" PATH="$bin:$PATH" "$shell" -fc '
    if [ -n "${BASH_VERSION:-}" ]; then shopt -s expand_aliases; fi
    . "$1"
    eval '\''codex resume "session id"'\''
    eval '\''command codex --version'\''
  ' "$shell" "$REPO_ROOT/home/.aliases.sh")"
  assert_eq $'--no-daemon\nresume\nsession id\n--version' "$output" \
    "expected the alias to preserve arguments and allow an explicit bypass"
}

test_codex_bash_alias() {
  test_codex_shell_alias_forwards_arguments bash
}

test_codex_zsh_alias() {
  test_codex_shell_alias_forwards_arguments zsh
}

test_case "Codex launch: Bash alias bypasses the daemon" test_codex_bash_alias
test_case "Codex launch: Zsh alias bypasses the daemon" test_codex_zsh_alias
