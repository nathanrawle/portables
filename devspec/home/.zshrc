if [[ -n "${HOST-}" ]]; then
  MACHINE=${HOST%%.*}
else
  MACHINE=$(hostname 2>/dev/null) || MACHINE=mystery-box
  MACHINE=${MACHINE%%.*}
fi
[[ -f "$HOME/.$MACHINE.env.zsh" ]] && source "$HOME/.$MACHINE.env.zsh"

source "$HOME/.omz-config.zsh"
source "$HOME/.tool-config.zsh"

source "$ZSH/oh-my-zsh.sh"

source "$HOME/.aliases.zsh"
source "$HOME/.keybinds.zsh"
source "$HOME/.named-dirs.zsh"

if [[ "$PROMPT_FW" = "p10k" ]]; then
  source "$HOME/.p10k.zsh"
fi

source "$HOME/.fin.zsh"

