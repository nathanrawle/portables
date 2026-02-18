#!/usr/bin/env bash

[[ -n "${OS-}" ]] || OS="$(uname -s)"
[[ "$OS" = Linux ]] && exit 0
case "$1" in
  install) command -v terraform >/dev/null 2>&1 || echo "syspkgmgr:terraform" ;;
esac
