# This file sets up paths and initializers for tools before OMZ and compinit run.

# Google Cloud SDK
if [ -f "/Users/nathan/google-cloud-sdk/path.zsh.inc" ]; then
    . "/Users/nathan/google-cloud-sdk/path.zsh.inc"
fi
if [ -f "/Users/nathan/google-cloud-sdk/completion.zsh.inc" ]; then
    . "/Users/nathan/google-cloud-sdk/completion.zsh.inc"
fi

# Add custom functions to fpath
if [ -d "$HOME/.zfunc" ]; then
    fpath+="$HOME/.zfunc"
fi

# Tool initializers
eval "$(zoxide init zsh --no-cmd)" 2>/dev/null || true
eval "$(pyenv init -)" 2>/dev/null || true
eval "$(direnv hook zsh)" 2>/dev/null || true

# NVM
export NVM_DIR="$HOME/.nvm"
if [ -s "$NVM_DIR/nvm.sh" ]; then
    . "$NVM_DIR/nvm.sh"  # This loads nvm
fi

if [ -d "$HOME/.npm-global" ]; then
  export PATH="$PATH:$HOME/.npm-global/bin"
fi

# Go environment
if [ -d "/usr/local/go/bin" ]; then
    path+=("/usr/local/go/bin")
fi

if [ -d "${GOPATH:=$HOME/go}/bin" ]; then
    path+=("$GOPATH/bin")
fi

# dbt Fusion extension (ensure dbt binary dir on PATH)
if [[ ":$PATH:" != *":/Users/nathan/.local/bin:"* ]]; then
  export PATH=/Users/nathan/.local/bin:"$PATH"
fi
