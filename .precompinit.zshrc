# set up completions and path for installed commands

[[ -e '/Users/nathan/google-cloud-sdk/path.zsh.inc' ]] && . '/Users/nathan/google-cloud-sdk/path.zsh.inc'
[[ -e '/Users/nathan/google-cloud-sdk/completion.zsh.inc' ]] && . '/Users/nathan/google-cloud-sdk/completion.zsh.inc'

# completions not managed by brew or omz
[[ -d ~/.zfunc ]] && fpath+=~/.zfunc

[[ -e /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv)"
hash | grep -qE ^zoxide= && eval "$(zoxide init zsh)"
hash | grep -qE ^pyenv= && eval "$(pyenv init -)"
hash | grep -qE ^direnv= && eval "$(direnv hook zsh)"
