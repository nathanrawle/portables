#!/usr/bin/env bash

LOG_NAME="${LOG_NAME:+$LOG_NAME.}homebrew:$1"
functions log >/dev/null 2>&1 || . "$PORTABLES"/log

case "$1" in
  install) command -v brew >/dev/null 2>&1 || echo self-install ;;
  self-install)
    log "begin"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    log "complete"
    ;;
esac
