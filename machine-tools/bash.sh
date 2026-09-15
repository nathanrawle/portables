#!/usr/bin/env bash

. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)/lib/maintenance.bash" || exit 1
tool_init "$@"

case "$1" in
  install) (( $(bash -c 'echo ${BASH_VERSINFO[0]}') >= 5 )) || echo syspkgmgr:bash ;;
  config)
    require_commands git bash
    clone_missing https://github.com/ohmybash/oh-my-bash.git "$HOME/.oh-my-bash"
    require_files "$HOME/.oh-my-bash/oh-my-bash.sh"
    ;;
esac
