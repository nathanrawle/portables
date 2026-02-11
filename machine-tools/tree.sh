#!/usr/bin/env bash

case "$1" in
  install) command -v tree >/dev/null 2>&1 || echo "syspkgmgr:tree" ;;
esac
