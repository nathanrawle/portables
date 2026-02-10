#!/usr/bin/env bash

url=https://github.com/ThePrimeagen/tmux-sessionizer.git
sauce="${PORTABLES%/*}"
source="$sauce"/tmux-sessionizer/tmux-sessionizer
target=~/.local/scripts/tmux-sessionizer

case "$1" in
install) command -v tmux-sessionizer >/dev/null 2>&1 || echo self-install ;;
self-install)
  [[ -s "$source" ]] ||
    git clone --depth 1 "$url" "$sauce"/tmux-sessionizer

  [[ -x "$source" ]] || chmod +x "$source"

  mkdir -p ~/.local/scripts
  rm -f "$target"
  ln -shf "$source" "$target"
  ;;
config)
  ln -shf "$source" "$target"
  [[ "$PATH": = *.local/scripts:* ]] ||
    echo "make sure ~/.local/scripts gets added to your path"
  ;;
esac
