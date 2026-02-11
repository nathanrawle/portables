#!/usr/bin/env bash

case "$1" in
  install) command -v fortune >/dev/null 2>&1 || echo "syspkgmgr:fortune" ;;
esac
