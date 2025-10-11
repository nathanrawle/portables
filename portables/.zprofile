# making environment available to non-interactive login shells?
eval "$(/opt/homebrew/bin/brew shellenv)"
eval "$(pyenv init --path)"

MACHINE=${${HOST%%.*}:-${(%):-%m}}
[[ -e "~/$MACHINE.env.zsh" ]] && . "~/$MACHINE.env.zsh"

# Created by `pipx` on 2024-12-04 16:53:53
export PATH="$PATH:/Users/nathan/.local/bin"
