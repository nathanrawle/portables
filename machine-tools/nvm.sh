#!/usr/bin/env bash

LOG_NAME="${LOG_NAME:+$LOG_NAME.}nvm:$1"
functions log >/dev/null 2>&1 || . "$PORTABLES"/log

case "$1" in
  install) [ -s $HOME/.nvm/nvm.sh ] || echo self-install ;;
  self-install)
    log "installing nvm"
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh | bash
    ;;
esac
