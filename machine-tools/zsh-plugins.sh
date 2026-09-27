#!/usr/bin/env bash

. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)/lib/maintenance.bash" || exit 1
tool_init "$@"

source_root="${XDG_DATA_HOME:-$HOME/.local/share}/portables/zsh"
names=( zsh-autosuggestions zsh-syntax-highlighting zsh-completions powerlevel10k )
versions=( 0.7.1 0.8.0 0.36.0 v1.20.0 )
urls=(
  https://github.com/zsh-users/zsh-autosuggestions.git
  https://github.com/zsh-users/zsh-syntax-highlighting.git
  https://github.com/zsh-users/zsh-completions.git
  https://github.com/romkatv/powerlevel10k.git
)
files=(
  zsh-autosuggestions.zsh
  zsh-syntax-highlighting.zsh
  src/_git
  powerlevel10k.zsh-theme
)

plugins_ready() {
  local index
  for ((index = 0; index < ${#names[@]}; index++)); do
    [[ -r "$source_root/${names[index]}/${files[index]}" ]] || return 1
  done
}

case "$1" in
  install)
    case "$OS" in
      Darwin) printf '%s\n' syspkgmgr:zsh-autosuggestions syspkgmgr:zsh-syntax-highlighting \
        syspkgmgr:zsh-completions syspkgmgr:powerlevel10k ;;
      Linux) plugins_ready || echo self-install ;;
    esac
    ;;
  self-install)
    [[ "$OS" = Linux ]] || { log -e "self-install unsupported on $OS ${ID:-unknown}"; exit 1; }
    require_commands git
    plugins_ready && exit 0
    mkdir -p "$source_root"
    for ((index = 0; index < ${#names[@]}; index++)); do
      name="${names[index]}"
      destination="$source_root/$name"
      [[ -r "$destination/${files[index]}" ]] && continue
      if [[ -e "$destination" || -L "$destination" ]]; then
        log -e "preserving conflicting path: $destination"
        exit 1
      fi
      temp="$(mktemp -d "$source_root/.${name}.XXXXXX")"
      git clone --depth 1 --branch "${versions[index]}" -- "${urls[index]}" "$temp/source"
      require_files "$temp/source/${files[index]}" || exit 1
      if [[ -e "$destination" || -L "$destination" ]]; then
        log -e "installation destination appeared during clone: $destination"
        exit 1
      fi
      mv "$temp/source" "$destination"
      rmdir "$temp"
    done
    ;;
esac
