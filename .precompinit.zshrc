# set up completions and path for installed commands

if [ -f '/Users/nathan/google-cloud-sdk/path.zsh.inc' ]; then . '/Users/nathan/google-cloud-sdk/path.zsh.inc'; fi
if [ -f '/Users/nathan/google-cloud-sdk/completion.zsh.inc' ]; then . '/Users/nathan/google-cloud-sdk/completion.zsh.inc'; fi

eval "$(/opt/homebrew/bin/brew shellenv)"
eval "$(pyenv init -)"
eval "$(zoxide init zsh)"
