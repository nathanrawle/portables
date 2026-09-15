#!/usr/bin/env bash

. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)/lib/maintenance.bash" || exit 1
tool_init "$@"

case "$1" in
  install) command -v zsh >/dev/null 2>&1 || echo syspkgmgr:zsh ;;
  config)
    require_commands zsh git
    clone_missing https://github.com/ohmyzsh/ohmyzsh.git "$HOME/.oh-my-zsh"
    require_files "$HOME/.oh-my-zsh/oh-my-zsh.sh"
    custom="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
    for plugin in zsh-syntax-highlighting zsh-completions zsh-autosuggestions; do
      clone_missing "https://github.com/zsh-users/$plugin.git" "$custom/plugins/$plugin" ||
        failure "plugin $plugin"
    done
    clone_missing https://github.com/marlonrichert/zsh-autocomplete.git "$custom/plugins/zsh-autocomplete" ||
      failure "plugin zsh-autocomplete"
    clone_missing https://github.com/romkatv/powerlevel10k.git "$custom/themes/powerlevel10k" ||
      failure "theme powerlevel10k"
    zmv="$(zsh -fc 'for dir in $fpath; do if [[ -r "$dir/zmv" ]]; then print -r -- "$dir/zmv"; break; fi; done')"
    require_files "$zmv"
    if [[ ! -d "$HOME/.zfuns" ]]; then
      require_external_destination "$HOME/.zfuns/zcp"
      mkdir -p "$HOME/.zfuns"
    fi
    for name in zcp zln; do
      destination="$HOME/.zfuns/$name"
      managed=0
      if [[ ! -e "$destination" && ! -L "$destination" ]]; then
        managed=1
      elif [[ -L "$destination" ]]; then
        target="$(readlink "$destination")"
        if [[ "$target" = "$PORTABLE_HOME/.zfuns/$name" ]]; then
          managed=1
        elif [[ ! -e "$destination" && "$target" = */share/zsh/*/functions/zmv ]]; then
          managed=1
        fi
      fi
      if [[ "$managed" = 1 ]]; then
        if require_external_destination "$HOME/.zfuns/$name"; then
          ln -sfn "$zmv" "$destination" || failure "function $name"
        else
          failure "function $name destination is inside repository"
        fi
      elif [[ ! -e "$destination" ]]; then
        failure "broken function link: $destination"
      fi
    done
    finish
    ;;
esac
