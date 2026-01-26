# making environment available to non-interactive login shells?
eval "$(/opt/homebrew/bin/brew shellenv)"

MACHINE=${${HOST%%.*}:-${(%):-%m}}
[[ -e ~/.$MACHINE.env.zsh ]] && . ~/.$MACHINE.env.zsh

export PATH="$PATH:/Users/nathan/.local/bin"
export PATH="$PATH:/Users/nathan/.local/scripts"
