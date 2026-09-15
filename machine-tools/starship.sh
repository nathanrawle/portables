#!/usr/bin/env bash

. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)/lib/maintenance.bash" || exit 1
tool_init "$@"

case "$1" in
  install)
    if ! command -v starship >/dev/null 2>&1; then
      if package_available starship; then echo syspkgmgr:starship; else echo self-install; fi
    fi
    ;;
  self-install)
    require_commands curl sh
    temp="$(mktemp -d "${TMPDIR:-/tmp}/portables-starship.XXXXXX")"
    trap 'rm -rf -- "$temp"' EXIT
    curl -fsSL https://starship.rs/install.sh -o "$temp/install"
    mkdir -p "$HOME/.local/bin"
    sh "$temp/install" --yes --bin-dir "$HOME/.local/bin"
    ;;
esac
