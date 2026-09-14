#!/usr/bin/env bash

. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)/lib/maintenance.bash" || exit 1
tool_init "$@"

case "$1" in
  install)
    if ! command -v lazygit >/dev/null 2>&1; then
      if package_available lazygit; then
        echo syspkgmgr:lazygit
      else
        command -v jq >/dev/null 2>&1 || echo syspkgmgr:jq
        echo self-install
      fi
    fi
    ;;
  self-install)
    require_commands curl jq tar
    case "$(uname -m)" in
      arm64|aarch64) arch=arm64 ;;
      x86_64|amd64) arch=x86_64 ;;
      *) log -e "unsupported lazygit architecture"; exit 1 ;;
    esac
    temp="$(mktemp -d "${TMPDIR:-/tmp}/portables-lazygit.XXXXXX")"
    trap 'rm -rf -- "$temp"' EXIT
    curl -fsSL https://api.github.com/repos/jesseduffield/lazygit/releases/latest -o "$temp/release.json"
    version="$(jq -er '.tag_name | select(test("^v[0-9.]+$")) | ltrimstr("v")' "$temp/release.json")"
    curl -fsSL "https://github.com/jesseduffield/lazygit/releases/download/v$version/lazygit_${version}_${OS}_$arch.tar.gz" -o "$temp/lazygit.tar.gz"
    tar -xzf "$temp/lazygit.tar.gz" -C "$temp" lazygit
    [[ -s "$temp/lazygit" ]] || exit 1
    mkdir -p "$HOME/.local/bin"
    install -m 755 "$temp/lazygit" "$HOME/.local/bin/lazygit"
    ;;
esac
