# Activate Powerlevel10k Instant Prompt.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

export ZSH="$HOME/.oh-my-zsh"

zstyle ':omz:update' mode auto

DISABLE_MAGIC_FUNCTIONS=true
ZSH_AUTOSUGGEST_MANUAL_REBIND=1

ZSH_THEME="powerlevel10k/powerlevel10k"
plugins=(
  git
  colored-man-pages
  zsh-syntax-highlighting
  zsh-autocomplete
  zsh-autosuggestions
)

fpath+=${ZSH_CUSTOM:-${ZSH:-~/.oh-my-zsh}/custom}/plugins/zsh-completions/src
[[ -e $HOME/.andfinally.zshrc ]] && source $HOME/.andfinally.zshrc
source $ZSH/oh-my-zsh.sh
