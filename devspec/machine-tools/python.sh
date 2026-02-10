#!/usr/bin/env bash

case "$1" in
install)
  echo "syspkgmgr:python"
  echo "uv:python:--default"
  ;;
config)
  mkdir -p ~/monty
  if [[ ! -d ~/monty/.venv ]]; then
    uv venv --directory ~/monty --allow-existing --prompt monty
  fi
  uv pip install --directory ~/monty -r ~/.config/python/monty
  ;;
esac
