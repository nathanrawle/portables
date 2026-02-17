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
      *) echo self-install ;;
    esac
    ;;
  self-install)
    curl -L https://aka.ms/gcm/linux-install-source.sh | sh
    ;;
  config)
    git-credential-manager configure
    ;;
esac
