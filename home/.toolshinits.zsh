export HOMEBREW_NO_ENV_HINTS=1
[[ -x /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv)"

[[ -f ~/google-cloud-sdk/path.zsh.inc ]] \
&& . ~/google-cloud-sdk/path.zsh.inc

[[ -f ~/google-cloud-sdk/completion.zsh.inc ]] \
&& . ~/google-cloud-sdk/completion.zsh.inc

command -v direnv >/dev/null 2>&1 && eval "$(direnv hook zsh)"
command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init zsh --no-cmd)"
command -v pyenv >/dev/null 2>&1 && eval "$(pyenv init -)"
command -v codex >/dev/null 2>&1 && eval "$(codex completion zsh)"

# NVM, npm, & node
export NVM_DIR="$HOME/.nvm"
function nvm() {
  if [[ -s "$NVM_DIR/nvm.sh" ]]; then
    unfunction nvm
    . "$NVM_DIR/nvm.sh"
    [[ -s "$NVM_DIR/bash_completion" ]] && . "$NVM_DIR/bash_completion"  # This loads nvm bash_completion
    nvm "$@"
  else
    print -u2 "nvm: could not find $NVM_DIR/nvm.sh"
    return 1
  fi
}
[[ -d "$HOME/.npm-global/bin" ]] && path+=( "$HOME/.npm-global/bin" )

# Go
[[ -d "/usr/local/go/bin" ]] && path+=( "/usr/local/go/bin" )
[[ -d "${GOPATH:=$HOME/go}/bin" ]] && path+=( "$GOPATH/bin" )

# opencode
export PATH=/Users/nathan/.opencode/bin:$PATH
command -v opencode >/dev/null 2>&1 && . $PORTABLES/home/.opencode-completions.zsh

# ~/.local
localbin=~/.local/bin
localscripts=~/.local/scripts
mkdir -p "$localbin"
mkdir -p "$localscripts"
path=( "$localbin" "$localscripts" $path )

# Add my functions to fpath
for fundir in zfuns bfuns pfuns; do
  if [ -d "$HOME/.$fundir" ]; then
    fpath+=( "$HOME/.$fundir" )
    autoload -U $HOME/.$fundir/*(:t)
  fi
done

# handy zsh functions
autoload -Uz zmv zcp zln

# This affects every invocation of `less` and makes it way better:
#   -i   case-insensitive search unless search string contains uppercase letters
#   -R   color
#   -F   exit if there is less than one page of content
#   -X   keep content on screen after exit
#   -M   show more info at the bottom prompt line
#   -x4  tabs are 4 instead of 8
#   -W   temporarily highlight the first new line after foreward movement
LESS='-iRFXMx4W'

export NVM_DIR PATH path fpath LESS

