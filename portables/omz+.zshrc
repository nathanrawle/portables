# 1. Remove older command from the history if a duplicate is to be added.
# 2. Include hidden files (files beginning with a `.`, i.e. dotfiles) in expansions.
setopt hist_ignore_all_dups glob_dots

# Activate Powerlevel10k Instant Prompt.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

export ZSH="$HOME/.oh-my-zsh"

# This affects every invocation of `less`.
#
#   -i   case-insensitive search unless search string contains uppercase letters
#   -R   color
#   -F   exit if there is less than one page of content
#   -X   keep content on screen after exit
#   -M   show more info at the bottom prompt line
#   -x4  tabs are 4 instead of 8
#   -W   temporarily highlight the first new line after foreward movement
export LESS='-iRFXMx4W'

# Give myself time to type
zstyle ':autocomplete:*' delay 0.5

# Allow browsing unlimited history
zstyle ':autocomplete:history-search-backward:*' list-lines -1

# Workaround for `zsh: do you wish to see all x possibilities…?`
zstyle ':completion:*' group-name ''

# Oh My Zsh auto-update
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

fpath+=${ZSH_CUSTOM:-$ZSH/custom}/plugins/zsh-completions/src
[[ -e $HOME/.precompinit.zsh ]] && source $HOME/.precompinit.zsh
source $ZSH/oh-my-zsh.sh

autoload -U +X bashcompinit && bashcompinit
complete -o nospace -C /opt/homebrew/bin/terraform terraform
