#!/usr/bin/env bash

LOG_NAME="${LOG_NAME:+$LOG_NAME.}git:$1"
functions log >/dev/null 2>&1 || . "$PORTABLES"/log

case "$1" in
  install)
    command -v git >/dev/null 2>&1 \
    || case "$OS" in
      Darwin)
        echo self-install
        ;;
      *) echo syspkgmgr:git ;;
    esac
    ;;
  self-install)
    log "installing xcode command-line tools"
    xcode-select --install
    log "complete"
    ;;
  config)
    log -d "configuring global git excludesfile…"
    git config --global --unset-all core.excludesfile 2>/dev/null || true # Ignore error if not set
    git config --global --add core.excludesfile "$HOME/.config/git/ignore"
    git config --global --add core.excludesfile "$HOME/.gitignore"
    log -d "complete"
    ;;
esac
