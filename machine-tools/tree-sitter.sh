#!/usr/bin/env bash

. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)/lib/maintenance.bash" || exit 1
tool_init "$@"

case "$1" in
    install)
      if ! command -v tree-sitter >/dev/null 2>&1; then
        echo syspkgmgr:tree-sitter-cli
      fi
    ;;
esac
