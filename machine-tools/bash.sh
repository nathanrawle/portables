#!/usr/bin/env bash

LOG_NAME="${LOG_NAME:+$LOG_NAME.}bash:$1"
functions log >/dev/null 2>&1 || . "$PORTABLES"/log

case "$1" in
  install) (( $(bash -c 'echo ${BASH_VERSINFO[0]}') >= 5 )) || echo syspkgmgr:bash ;;
  config)
    if [ ! -d $HOME/.oh-my-bash ]; then
      log "installing oh-my-bash"
      bash -c "$(curl -fsSL https://raw.githubusercontent.com/ohmybash/oh-my-bash/master/tools/install.sh)"
    fi
    ;;
esac
