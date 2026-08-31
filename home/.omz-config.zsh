# This file contains the core configuration for Oh My Zsh.

export ZSH="$HOME/.oh-my-zsh"

# Oh My Zsh auto-update
zstyle ':omz:update' mode auto

# Add wisely, as too many plugins slow down shell startup.
plugins=(
  direnv
  git
  colored-man-pages
  zsh-syntax-highlighting
  zsh-autocomplete
  zsh-autosuggestions
)

# Set Zsh theme. Can be overridden by p10k setup.
# PROMPT_FW should be set in a machine-specific env file.
if [ "$PROMPT_FW" = "starship" ]; then
  plugins+=("starship")
elif [[ -f ~/.p10k.zsh ]]; then
  ZSH_THEME="powerlevel10k/powerlevel10k"
else
  ZSH_THEME="random"
fi

# Add path for zsh-completions
fpath+=( ${ZSH_CUSTOM:-$ZSH/custom}/plugins/zsh-completions/src )

# zsh-autocomplete's path-based zasync autoload is ineffective on Zsh 5.9.
fpath+=( "${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zasync" )

# Set to this value to manual rebind keys for zsh-autosuggestions
ZSH_AUTOSUGGEST_MANUAL_REBIND=1

# Disable OMZ's magic functions for pushd
DISABLE_MAGIC_FUNCTIONS=true
