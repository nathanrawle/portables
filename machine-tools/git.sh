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
    log "configuring…"
    if [[ -z "$(git config --global user.name)" ]]; then
      [[ -n "$GIT_NAME" ]] || read -p 'What name should appear on your commits? ' GIT_NAME
      git config --global user.name "$GIT_NAME"
    fi
    if [[ -z "$(git config --global user.email)" ]]; then
      [[ -n "$GIT_EMAIL" ]] || read -p 'What email should git use? ' GIT_EMAIL
      git config --global user.email "$GIT_EMAIL"
    fi
    git config --global --unset-all core.excludesfile 2>/dev/null || true # Ignore error if not set
    git config --global --add core.excludesfile "$HOME/.gitignore"
    git config --global --add core.excludesfile "$HOME/.config/git/ignore"
    ;;
esac
