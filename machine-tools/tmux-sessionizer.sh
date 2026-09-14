#!/usr/bin/env bash

. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)/lib/maintenance.bash" || exit 1
tool_init "$@"

source_path="${PORTABLES%/*}/tmux-sessionizer/tmux-sessionizer"
target="$HOME/.local/scripts/tmux-sessionizer"
case "$1" in
  install) command -v tmux-sessionizer >/dev/null 2>&1 || echo self-install ;;
  self-install)
    require_commands git
    clone_missing https://github.com/ThePrimeagen/tmux-sessionizer.git "${source_path%/*}"
    ;;
  config)
    if command -v tmux-sessionizer >/dev/null 2>&1; then exit 0; fi
    require_files "$source_path"
    chmod +x "$source_path"
    mkdir -p "${target%/*}"
    if [[ -e "$target" || -L "$target" ]]; then
      log -e "preserving conflicting path: $target"
      exit 1
    fi
    ln -s "$source_path" "$target"
    ;;
esac
