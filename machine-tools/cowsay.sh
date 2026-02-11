#!/usr/bin/env bash

case "$1" in
  install) command -v cowsay >/dev/null 2>&1 || echo "syspkgmgr:cowsay" ;;
esac
