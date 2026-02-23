#!/usr/bin/env bash

LOG_NAME="${LOG_NAME:+$LOG_NAME.}python:$1"
functions log >/dev/null 2>&1 || . "$PORTABLES"/log

[[ -n "$OS" ]] || OS="$(uname -s)"

case "$1" in
  install)
    case "$OS" in
      # on macOS, I only really need brew python to get the essential system deps, like
      # openssl & readline
      Darwin) [[ -x "$(brew --prefix)/bin/python3" ]] || echo "syspkgmgr:python3" ;;
      *) echo "syspkgmgr:python3-venv" ;;
    esac
    echo "uv:python:--default:--preview-features:python-install-default"
    ;;
  config)
    mkdir -p ~/monty
    if [[ ! -d ~/monty/.venv ]]; then
      log "creating centralised python environment (monty) for sketching"
      uv venv --directory ~/monty --allow-existing --prompt monty
    fi
    log "kitting-out monty"
    uv pip install -U --directory ~/monty -r ~/.config/python/monty
    ;;
esac
