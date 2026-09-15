#!/usr/bin/env bash

. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)/lib/maintenance.bash" || exit 1
tool_init "$@"

case "$OS" in
  Darwin) fonts_dir="$HOME/Library/Fonts" ;;
  Linux) fonts_dir="$HOME/.local/share/fonts" ;;
  *) log -e "unsupported font platform: $OS"; exit 1 ;;
esac
case "$1" in
  install)
    shopt -s nullglob
    fonts=( "$fonts_dir"/FiraCode*.ttf "$fonts_dir"/ttf/FiraCode*.ttf )
    if [[ ${#fonts[@]} = 0 ]]; then
      command -v unzip >/dev/null 2>&1 || echo syspkgmgr:unzip
      if [[ "$OS" = Linux ]] && ! command -v fc-cache >/dev/null 2>&1; then echo syspkgmgr:fontconfig; fi
      echo self-install
    fi
    ;;
  self-install)
    require_commands curl unzip
    [[ "$OS" != Linux ]] || require_commands fc-cache
    temp="$(mktemp -d "${TMPDIR:-/tmp}/portables-fonts.XXXXXX")"
    trap 'rm -rf -- "$temp"' EXIT
    curl -fsSL https://github.com/tonsky/FiraCode/releases/download/5.2/Fira_Code_v5.2.zip -o "$temp/fonts.zip"
    unzip -tq "$temp/fonts.zip"
    unzip -q "$temp/fonts.zip" 'ttf/*' -d "$temp"
    mkdir -p "$fonts_dir"
    cp "$temp"/ttf/*.ttf "$fonts_dir/"
    [[ "$OS" != Linux ]] || fc-cache -f "$fonts_dir"
    ;;
esac
