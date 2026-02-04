# This file contains final overrides, functions, and shell greetings.

## Add my functions to fpath
# In the new model, the symlinking of functions is handled by the main symlink script.
# We just need to ensure the path is set and the functions are autoloaded.
if [ -d "$HOME/.fns" ]; then
    fpath+=("$HOME/.funs")
    autoload -U $HOME/.funs/*(:t)
fi

## Ensure $path and $fpath entries are unique
typeset -U path fpath

# Bash completion compatibility
autoload -U +X bashcompinit && bashcompinit
complete -o nospace -C /opt/homebrew/bin/terraform terraform

## zsh-autocomplete configuration
zstyle -e ':autocomplete:*:*' list-lines 'reply=( $(( 0.75 * LINES )) )'
zstyle ':autocomplete:*complete*:*' insert-unambiguous yes
zstyle ':autocomplete:*history*:*' insert-unambiguous yes
zstyle ':autocomplete:menu-search:*' insert-unambiguous yes
zstyle ':completion:*:*' matcher-list 'm:{[:lower:]-}={[:upper:]_}' '+r:|[.]=**'
zstyle ':autocomplete:*' delay 0.2
zstyle ':completion:*' group-name ''

## Welcome message
if command -v fortune >/dev/null 2>&1 && command -v cowsay >/dev/null 2>&1; then
  cs_mods=( b d g p s t w y )
  cs_opt=${cs_mods[$(( RANDOM % ${#cs_mods} + 1 ))]}
  fortune | cowsay -"$cs_opt" -n
  unset cs_mods cs_opt
fi
