#!/usr/bin/env bash

case "$1" in
  install) command -v yq >/dev/null 2>&1 || echo "syspkgmgr:yq" ;;
esac
