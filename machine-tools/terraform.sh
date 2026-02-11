#!/usr/bin/env bash

case "$1" in
  install) command -v terraform >/dev/null 2>&1 || echo "syspkgmgr:terraform" ;;
esac
