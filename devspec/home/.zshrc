export MACHINE=${${HOST%%.*}:-${(%):-%m}}
source "$HOME/.$MACHINE.env" \
|| echo "No environment found for $MACHINE. Run \`run.sh\`"

source "$HOME/.zstyles"
source "$HOME/.toolshinits.zsh"
source "$HOME/.omz-config.zsh"
source "$ZSH/oh-my-zsh.sh"
# oh-my-zsh may read zstyles during setup, but also override them, so I have to source
# styles before *and* after:
source "$HOME/.zstyles" # undo any mods made by omz
source "$HOME/.aliases.zsh"
source "$HOME/.keybinds.zsh"
source "$HOME/.named-dirs.zsh"
source "$HOME/.fin.zsh"

# Anything below this comment has been added by a wayward shell command and will be
# dealt with appropriately in due course. LOOKING AT YOU TERRAFORM 👀

