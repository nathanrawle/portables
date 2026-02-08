MACHINE="${${HOST%%.*}:-${(%):-%m}}"
source "$HOME/.$MACHINE.env.zsh"
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

