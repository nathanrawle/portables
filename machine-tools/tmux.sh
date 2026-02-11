#!/usr/bin/env bash

case "$1" in
  install) command -v tmux >/dev/null 2>&1 || echo "syspkgmgr:tmux" ;;
esac
