#!/usr/bin/env bash

case "$1" in
  install) command -v jq >/dev/null 2>&1 || echo "syspkgmgr:jq" ;;
esac
