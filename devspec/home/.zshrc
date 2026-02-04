if [ -L "$0" ]; then
    DEV_SPECS="$(dirname "$(readlink "$0")")"
else
    DEV_SPECS="${DEV_SPECS:-$HOME/code/portables/devspec}"
fi

PORTABLE_HOME="$DEV_SPECS/home"

if [[ -n "${HOST-}" ]]; then
  MACHINE=${HOST%%.*}
else
  MACHINE=$(hostname 2>/dev/null) || MACHINE=mystery-box
  MACHINE=${MACHINE%%.*}
fi
[[ -f "$PORTABLE_HOME/.$MACHINE.env.zsh" ]] && source "$PORTABLE_HOME/.$MACHINE.env.zsh"

source "$PORTABLE_HOME/.omz-config.zsh"
source "$PORTABLE_HOME/.tool-config.zsh"

if [[ -f "$ZSH/oh-my-zsh.sh" ]]; then
    source "$ZSH/oh-my-zsh.sh"
fi

source "$PORTABLE_HOME/.aliases.zsh"
source "$PORTABLE_HOME/.keybinds.zsh"
source "$PORTABLE_HOME/.named-dirs.zsh"

if [[ -f "$PORTABLE_HOME/.p10k.zsh" ]]; then
    # PROMPT_FW should be set in a machine-specific env file (e.g. .m1pro.env.zsh)
    if [[ "$PROMPT_FW" = "p10k" ]]; then
        source "$PORTABLE_HOME/.p10k.zsh"
    fi
fi

source "$PORTABLE_HOME/.fin.zsh"

unset DEV_SPECS PORTABLE_HOME
