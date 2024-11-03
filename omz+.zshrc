# Activate Powerlevel10k Instant Prompt.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

ZSH=~/.oh-my-zsh
DISABLE_AUTO_UPDATE=true
DISABLE_MAGIC_FUNCTIONS=true
ZSH_AUTOSUGGEST_MANUAL_REBIND=1

ZSH_THEME="powerlevel10k/powerlevel10k"
plugins=(zsh-syntax-highlighting zsh-autocomplete zsh-autosuggestions)

source ~/.oh-my-zsh/oh-my-zsh.sh
source ~/.p10k.zsh