# This file contains the core configuration for Oh My Zsh.

export ZSH="$HOME/.oh-my-zsh"

# Keep completion state with other generated Zsh cache files.
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
mkdir -p "$XDG_CACHE_HOME/zsh"
ZSH_COMPDUMP="$XDG_CACHE_HOME/zsh/compdump-${HOST%%.*}-${ZSH_VERSION}"

# Homebrew owns the completion directory even though OMZ flags its group mode.
ZSH_DISABLE_COMPFIX=true

# Oh My Zsh auto-update
zstyle ':omz:update' mode auto

# Add wisely, as too many plugins slow down shell startup.
plugins=(
  git
  colored-man-pages
)

# Set Zsh theme. Can be overridden by p10k setup.
# PROMPT_FW should be set in a machine-specific env file.
if [ "$PROMPT_FW" = "starship" ]; then
  ZSH_THEME=""
else
  ZSH_THEME="random"
fi

# Disable OMZ's magic functions for pushd
DISABLE_MAGIC_FUNCTIONS=true
