#!/usr/bin/env bash

case "$1" in
  install) command -v tmux-sessionizer >/dev/null 2>&1 || echo self-install ;;
  self-install)
    sess_path="$PORTABLES"/../tmux-sessionizer/tmux-sessionizer
    [[ -s "$sess_path" ]] \
    || git clone --depth 1 https://github.com/ThePrimeagen/tmux-sessionizer.git
    [[ -x "$sess_path" ]] || chmod +x "$sess_path"
    mkdir -p ~/.local/scripts
    ln -sf "$sess_path"/tmux-sessionizer ~/.local/scripts/tmux-sessionizer
  config)
    [[ :"$PATH": = *.local/scripts/?:* ]] \
    || echo "make sure ~/.local/scripts gets added to your path"
    ;;
esac

