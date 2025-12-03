# set up completions and path for installed commands

[[ -e '/Users/nathan/google-cloud-sdk/path.zsh.inc' ]] \
&& . '/Users/nathan/google-cloud-sdk/path.zsh.inc'

[[ -e '/Users/nathan/google-cloud-sdk/completion.zsh.inc' ]] \
&& . '/Users/nathan/google-cloud-sdk/completion.zsh.inc'

# completions not managed by brew or omz
[[ -d ~/.zfunc ]] && fpath+=~/.zfunc

[[ -e /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv)"
hash | grep -qE ^zoxide= && eval "$(zoxide init zsh)"
hash | grep -qE ^pyenv= && eval "$(pyenv init -)"
hash | grep -qE ^direnv= && eval "$(direnv hook zsh)"

export NVM_DIR="$HOME/.nvm"
[ -s "/opt/homebrew/opt/nvm/nvm.sh" ] \
&& . "/opt/homebrew/opt/nvm/nvm.sh"  # This loads nvm

[ -s "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm" ] \
&& . "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm"  # This loads nvm bash_completion

[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

# Added by dbt Fusion extension (ensure dbt binary dir on PATH)
if [[ ":$PATH:" != *":/Users/nathan/.local/bin:"* ]]; then
  export PATH=/Users/nathan/.local/bin:"$PATH"
fi
# Added by dbt Fusion extension
alias dbtf=/Users/nathan/.local/bin/dbt

# put go binaries in path:
[[ -d "${GOPATH:=$HOME/go}/bin" ]] \
&& path+="$GOPATH/bin"

