#!/usr/bin/env bash

case "$1" in
  install) command -v fd >/dev/null 2>&1 || echo "syspkgmgr:fd" ;;
esac
