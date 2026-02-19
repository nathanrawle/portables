#!/usr/bin/env bash

[[ -n "$OS" ]] || OS="$(uname -s)"
case "$1" in
  install)
    if [[ "$OS" = Darwin ]]; then
      command -v colima >/dev/null 2>&1 || echo "syspkgmgr:colima"
    fi
    ;;
esac
