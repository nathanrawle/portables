export MACHINE=${${HOST%%.*}:-${(%):-%m}}
machine="$(tr '[:upper:]' '[:lower:]' <<< "$MACHINE")"
source ~/."$machine".env \
|| echo "No environment found for $MACHINE. Run \`run.sh\`"

source ~/.zstyles
source ~/.toolshinits.zsh
source ~/.omz-config.zsh
source "$ZSH"/oh-my-zsh.sh
# oh-my-zsh may read zstyles during setup, but also override them, so I have to source
# styles before *and* after:
source ~/.zstyles # undo any mods made by omz
source ~/.aliases.zsh
source ~/.keybinds.zsh
source ~/.named-dirs.zsh
source ~/.fin.zsh

# Anything below this comment has been added by a wayward shell command and will be
# dealt with appropriately in due course. LOOKING AT YOU TERRAFORM 👀


export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion
