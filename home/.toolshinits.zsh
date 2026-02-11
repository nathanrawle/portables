export HOMEBREW_NO_ENV_HINTS=1
[[ -x /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv)"

[[ -f ~/google-cloud-sdk/path.zsh.inc ]] \
&& . ~/google-cloud-sdk/path.zsh.inc

[[ -f ~/google-cloud-sdk/completion.zsh.inc ]] \
&& . ~/google-cloud-sdk/completion.zsh.inc

command -v direnv >/dev/null 2>&1 && eval "$(direnv hook zsh)"
command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init zsh --no-cmd)"
command -v pyenv >/dev/null 2>&1 && eval "$(pyenv init -)"

# NVM, npm, & node
NVM_DIR="$HOME/.nvm"
[[ -s "$NVM_DIR/nvm.sh" ]] && . "$NVM_DIR/nvm.sh"
[[ -d "$HOME/.npm-global/bin" ]] && path+=( "$HOME/.npm-global/bin" )

# Go
[[ -d "/usr/local/go/bin" ]] && path+=( "/usr/local/go/bin" )
[[ -d "${GOPATH:=$HOME/go}/bin" ]] && path+=( "$GOPATH/bin" )

# ~/.local
localbin=~/.local/bin
localscripts=~/.local/scripts
mkdir -p "$localbin"
mkdir -p "$localscripts"
path+=( "$localbin" "$localscripts" )

# Add my functions to fpath
for fundir in zfuns bfuns pfuns; do
  if [ -d "$HOME/.$fundir" ]; then
    fpath+=( "$HOME/.$fundir" )
    autoload -U $HOME/.$fundir/*(:t)
  fi
done

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
