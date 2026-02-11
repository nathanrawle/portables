#!/usr/bin/env bash

case "$1" in
  install) command -v timew >/dev/null 2>&1 || echo "syspkgmgr:timewarrior" ;;
esac
