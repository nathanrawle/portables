#!/usr/bin/env bash

LOG_NAME="${LOG_NAME:+$LOG_NAME.}curl:$1"
functions log >/dev/null 2>&1 || . "$PORTABLES"/log

case "$1" in
install)
  command -v curl >/dev/null 2>&1 ||
    case "$OS" in
    Darwin)
      echo self-install
      ;;
    *) echo syspkgmgr:curl ;;
    esac
  ;;
self-install)
  log "installing xcode command-line tools"
  xcode-select --install
  log "complete"
  ;;
esac
