#!/usr/bin/env bash

LOG_NAME="${LOG_NAME:+$LOG_NAME.}uv:$1"
functions log >/dev/null 2>&1 || . "$PORTABLES"/log

[[ -n "$OS" ]] || OS="$(uname -s)"
case "$1" in
install)
  if ! command -v uv >/dev/null 2>&1; then
    case "$OS" in
    Darwin) echo "syspkgmgr:uv" ;;
    *) echo "self-install" ;;
    esac
  fi
  ;;
self-install)
  log "begin"
  curl -LsSf https://astral.sh/uv/install.sh | sh
  log "complete"
  ;;
esac
