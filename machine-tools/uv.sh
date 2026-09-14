#!/usr/bin/env bash

. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)/lib/maintenance.bash" || exit 1
tool_init "$@"

case "$1" in
  install)
    if ! command -v uv >/dev/null 2>&1; then
      if [[ "$OS" = Darwin ]]; then echo syspkgmgr:uv; else echo self-install; fi
    fi
    ;;
  self-install)
    require_commands curl sh
    temp="$(mktemp -d "${TMPDIR:-/tmp}/portables-uv.XXXXXX")"
    trap 'rm -rf -- "$temp"' EXIT
    curl -fsSL https://astral.sh/uv/install.sh -o "$temp/install"
    UV_NO_MODIFY_PATH=1 sh "$temp/install"
    ;;
esac
