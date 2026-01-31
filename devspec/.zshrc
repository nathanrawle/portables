# This file is the orchestrator for the Zsh startup sequence.
# It should only contain comments and source statements.

# Find the devspec directory, assuming this script is symlinked to the home directory.
# A default is provided for robustness.
if [ -L "$0" ]; then
    DEV_SPECS="$(dirname "$(readlink "$0")")"
else
    DEV_SPECS="${DEV_SPECS:-$HOME/code/portables/devspec}"
fi

ZSH_LIB="$DEV_SPECS/zsh-lib"

# 1. Configure Oh My Zsh variables (theme, plugins, etc.)
source "$ZSH_LIB/omz-config.zsh"

# 2. Set up paths and environment initializers BEFORE sourcing Oh My Zsh
source "$ZSH_LIB/tool-config.zsh"

# 3. Source Oh My Zsh itself
# This will initialize the completion system and load plugins.
if [ -f "$ZSH/oh-my-zsh.sh" ]; then
    source "$ZSH/oh-my-zsh.sh"
fi

# 4. Source personal aliases
source "$ZSH_LIB/aliases.zsh"

# 5. Source personal keybind overrides AFTER plugins are loaded
source "$ZSH_LIB/keybinds.zsh"

# 6. Source named directory hashes for easy navigation
source "$ZSH_LIB/named-dirs.zsh"

# 7. Conditionally source Powerlevel10k theme configuration
if [ -f "$ZSH_LIB/p10k.zsh" ]; then
    # PROMPT_FW should be set in a machine-specific env file (e.g. .m1pro.env.zsh)
    if [ "$PROMPT_FW" = "p10k" ]; then
        source "$ZSH_LIB/p10k.zsh"
    fi
fi

# 8. Source all other functions, final overrides, and shell greetings
source "$ZSH_LIB/fin.zsh"

# Unset variables to keep the shell environment clean
unset DEV_SPECS ZSH_LIB
