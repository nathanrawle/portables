#!/usr/bin/env bash

LOG_NAME="${LOG_NAME:+$LOG_NAME.}gcm:$1"
functions log >/dev/null 2>&1 || . "$PORTABLES"/log

case "$1" in
  install)
    command -v git-credential-manager >/dev/null 2>&1 \
    || case "$OS" in
      Darwin)
        echo syspkgmgr:ext:--cask:git-credential-manager
        ;;
      *) echo syspkgmgr:git-credential-oauth ;;
    esac
    ;;
  config)
    case "$OS" in
      Darwin) git-credential-manager configure ;;
      *) git-credential-oauth configure ;;
    esac
    ;;
esac
