#!/usr/bin/env bash

LOG_NAME="${LOG_NAME:+$LOG_NAME.}tmux-sssnzr:$1"
functions log >/dev/null 2>&1 || . "$PORTABLES"/log

url=https://github.com/ThePrimeagen/tmux-sessionizer.git
sauce="${PORTABLES%/*}"
source="$sauce"/tmux-sessionizer/tmux-sessionizer
target=~/.local/scripts/tmux-sessionizer

case "$1" in
install) command -v tmux-sessionizer >/dev/null 2>&1 || echo self-install ;;
self-install)
  log "beginning"
  [[ -s "$source" ]] ||
    git clone --depth 1 "$url" "$sauce"/tmux-sessionizer

  [[ -x "$source" ]] || chmod +x "$source"

  mkdir -p ~/.local/scripts
  rm -f "$target"
  ln -shf "$source" "$target"
  log "complete"
  ;;
config)
  ln -shf "$source" "$target"
  [[ "$PATH": = *.local/scripts:* ]] ||
    log -i "make sure ~/.local/scripts gets added to your path"
  ;;
esac
