#!/usr/bin/env bash

. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)/lib/maintenance.bash" || exit 1
tool_init "$@"

[[ -n "$OS" ]] || OS="$(uname -s)"
case "$1" in
  install)
    if [[ "$OS" = Darwin ]]; then
      command -v colima >/dev/null 2>&1 || echo "syspkgmgr:colima"
    fi
    ;;
esac
