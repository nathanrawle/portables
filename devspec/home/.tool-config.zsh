# Google Cloud SDK
[[ -f "~/google-cloud-sdk/path.zsh.inc" ]] && . "~/google-cloud-sdk/path.zsh.inc"
[[ -f "~/google-cloud-sdk/completion.zsh.inc" ]] && . "~/google-cloud-sdk/completion.zsh.inc"

# Add custom functions to fpath
[[ -d "$HOME/.zfunc" ]] && fpath+="$HOME/.zfunc"

# NVM & node
export NVM_DIR="$HOME/.nvm"
[[ -s "$NVM_DIR/nvm.sh" ]] && . "$NVM_DIR/nvm.sh"  # This loads nvm
[[ -d "$HOME/.npm-global" ]] && export PATH="$PATH:$HOME/.npm-global/bin"

# Go environment
[[ -d "/usr/local/go/bin" ]] && path+=("/usr/local/go/bin")
[[ -d "${GOPATH:=$HOME/go}/bin" ]] && path+=("$GOPATH/bin")

[[ ":$PATH:" != *":~/.local/bin:"* ]] && export PATH=~/.local/bin:"$PATH"

# Tool initializers
command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init zsh --no-cmd)" 2>/dev/null
command -v pyenv >/dev/null 2>&1 && eval "$(pyenv init -)" 2>/dev/null
command -v direnv >/dev/null 2>&1 && eval "$(direnv hook zsh)" 2>/dev/null
