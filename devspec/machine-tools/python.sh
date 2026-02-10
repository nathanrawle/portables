#!/usr/bin/env bash

[[ -n "$OS" ]] || OS="$(uname -s)"

case "$1" in
install)
  case "$OS" in
  # on macOS, I only really need brew python to get the essential system deps, like
  # openssl & readline
  Darwin) [[ -x "$(brew --prefix)/bin/python3" ]] || echo "syspkgmgr:python" ;;
  *) echo "syspkgmgr:python" ;;
  esac
  echo "uv:python:--default:--preview-features:python-install-default"
  ;;
config)
  mkdir -p ~/monty
  if [[ ! -d ~/monty/.venv ]]; then
    uv venv --directory ~/monty --allow-existing --prompt monty
  fi
  uv pip install --directory ~/monty -r ~/.config/python/monty
  ;;
esac
