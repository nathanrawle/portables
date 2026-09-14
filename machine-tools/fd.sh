#!/usr/bin/env bash

. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)/lib/maintenance.bash" || exit 1
tool_init "$@"

case "$1" in
  install)
    if ! command -v fd >/dev/null 2>&1 && ! command -v fdfind >/dev/null 2>&1; then
      case "$OS:$ID" in
        Linux:ubuntu|Linux:debian|Linux:pop|Linux:fedora) echo syspkgmgr:fd-find ;;
        *) echo syspkgmgr:fd ;;
      esac
    fi
    ;;
esac
