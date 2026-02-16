#!/usr/bin/env bash

LOG_NAME="${LOG_NAME:+$LOG_NAME.}homebrew:$1"
functions log >/dev/null 2>&1 || . "$PORTABLES"/log

[[ -n "$OS" ]] || OS="$(uname -s)"
[[ "$OS" = Darwin ]] || exit
case "$1" in
  install)
    command -v brew >/dev/null 2>&1 ||
      [[ -x /opt/homebrew/bin/brew ]] ||
      echo self-install
    ;;
  self-install)
    log
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    ;;
esac
