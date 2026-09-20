#!/usr/bin/env bash

. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)/lib/maintenance.bash" || exit 1
tool_init "$@"

case "$1" in
  install)
    if ! command -v gh >/dev/null 2>&1; then
      case "$OS:$ID" in
        Linux:arch) echo syspkgmgr:github-cli ;;
        *) echo syspkgmgr:gh ;;
      esac
    fi
    ;;
esac
