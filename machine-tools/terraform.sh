#!/usr/bin/env bash

. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)/lib/maintenance.bash" || exit 1
tool_init "$@"

[[ -n "${OS-}" ]] || OS="$(uname -s)"
[[ "$OS" = Linux ]] && exit 0
case "$1" in
  install) command -v terraform >/dev/null 2>&1 || echo "syspkgmgr:terraform" ;;
esac
