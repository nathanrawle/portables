#!/usr/bin/env bash

LOG_NAME="${LOG_NAME:+$LOG_NAME.}git:$1"
functions log >/dev/null 2>&1 || . "$PORTABLES"/log

case "$1" in
  install)
    command -v git >/dev/null 2>&1 \
    || case "$OS" in
      Darwin)
        echo xcode
        ;;
      *) echo syspkgmgr:git ;;
    esac
    ;;
  xcode)
    log "installing xcode command-line tools"
    xcode-select --install
    ;;
  config)
    log -d "configuring global git configurations…"
    git config --global user.name "$USER_NAME" # these can be passed from private portables
    git config --global user.email "$USER_EMAIL"
    git config --global --unset-all core.excludesfile 2>/dev/null || true # Ignore error if not set
    git config --global --add core.excludesfile "$HOME/.config/git/ignore"
    git config --global --add core.excludesfile "$HOME/.gitignore"
    ;;
esac
