#!/usr/bin/env bash

. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)/lib/maintenance.bash" || exit 1
tool_init "$@"

case "$1" in
  install) command -v timew >/dev/null 2>&1 || echo "syspkgmgr:timewarrior" ;;
esac
