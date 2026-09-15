#!/usr/bin/env bash

. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)/lib/maintenance.bash" || exit 1
tool_init "$@"

case "$1" in
  install)
    case "$OS:$ID" in
      Darwin:*) command -v python3 >/dev/null 2>&1 || echo syspkgmgr:python3 ;;
      Linux:arch) echo syspkgmgr:python ;;
      Linux:fedora) echo syspkgmgr:python3 ;;
      Linux:*) echo syspkgmgr:python3-venv ;;
    esac
    echo uv:python:--default:--preview-features:python-install-default
    ;;
  config)
    require_commands uv
    require_files "$HOME/.config/python/monty"
    if [[ ! -x "$HOME/monty/.venv/bin/python" ]]; then
      mkdir -p "$HOME/monty"
      uv venv --directory "$HOME/monty" --allow-existing --prompt monty
    fi
    uv pip install --python "$HOME/monty/.venv/bin/python" -r "$HOME/.config/python/monty"
    ;;
esac
