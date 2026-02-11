#!/usr/bin/env bash

case "$1" in
  install) command -v colima >/dev/null 2>&1 || echo "syspkgmgr:colima" ;;
esac
