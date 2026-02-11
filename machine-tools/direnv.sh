#!/usr/bin/env bash

case "$1" in
  install) command -v direnv >/dev/null 2>&1 || echo "syspkgmgr:direnv" ;;
esac
