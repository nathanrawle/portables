#!/usr/bin/env bash

. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)/lib/maintenance.bash" || exit 1
tool_init "$@"

version=26.08.04
source_dir="${XDG_DATA_HOME:-$HOME/.local/share}/zsh-autocomplete"
entrypoint="$source_dir/zsh-autocomplete.plugin.zsh"
zasync="$source_dir/z-async/z-async"

case "$1" in
  install)
    case "$OS:$ID" in
      Darwin:*|Linux:arch) echo syspkgmgr:zsh-autocomplete ;;
      Linux:ubuntu|Linux:debian|Linux:pop|Linux:fedora)
        [[ -r "$entrypoint" && -r "$zasync" ]] || echo self-install
        ;;
    esac
    ;;
  self-install)
    case "$OS:$ID" in
      Linux:ubuntu|Linux:debian|Linux:pop|Linux:fedora) ;;
      *) log -e "self-install unsupported on $OS ${ID:-unknown}"; exit 1 ;;
    esac
    require_commands git
    if [[ -r "$entrypoint" && -r "$zasync" ]]; then exit 0; fi
    if [[ -e "$source_dir" || -L "$source_dir" ]]; then
      log -e "preserving conflicting path: $source_dir"
      exit 1
    fi
    mkdir -p "${source_dir%/*}"
    temp="$(mktemp -d "${source_dir%/*}/.zsh-autocomplete.XXXXXX")"
    trap 'rm -rf -- "$temp"' EXIT
    git clone --depth 1 --branch "$version" -- \
      https://github.com/marlonrichert/zsh-autocomplete.git "$temp/source"
    require_files "$temp/source/zsh-autocomplete.plugin.zsh" "$temp/source/z-async/z-async"
    if [[ -e "$source_dir" || -L "$source_dir" ]]; then
      log -e "installation destination appeared during clone: $source_dir"
      exit 1
    fi
    mv "$temp/source" "$source_dir"
    ;;
esac
