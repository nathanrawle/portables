#!/usr/bin/env bash

case "$1" in
  install) command -v fzf >/dev/null 2>&1 || echo "syspkgmgr:fzf" ;;
esac
