#!/usr/bin/env bash

. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)/lib/maintenance.bash" || exit 1
tool_init "$@"

case "$1" in
  install) [[ -s "$HOME/.nvm/nvm.sh" ]] || echo self-install ;;
  self-install)
    require_commands curl bash
    temp="$(mktemp -d "${TMPDIR:-/tmp}/portables-nvm.XXXXXX")"
    trap 'rm -rf -- "$temp"' EXIT
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh -o "$temp/install"
    PROFILE=/dev/null bash "$temp/install"
    ;;
esac
