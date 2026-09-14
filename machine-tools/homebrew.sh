#!/usr/bin/env bash

. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)/lib/maintenance.bash" || exit 1
tool_init "$@"

[[ "$OS" = Darwin ]] || exit 0
case "$1" in
  install) command -v brew >/dev/null 2>&1 || echo self-install ;;
  self-install)
    require_commands curl bash
    temp="$(mktemp -d "${TMPDIR:-/tmp}/portables-brew.XXXXXX")"
    trap 'rm -rf -- "$temp"' EXIT
    curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh -o "$temp/install"
    /bin/bash "$temp/install"
    ;;
esac
