## named directories
hash -d code=~/code
hash -d homebrew=$HOMEBREW_PREFIX
hash -d portables=$PORTABLES
hash -d devspec=$PORTABLES/devspec
hash -d omz=$ZSH
hash -d cfg=~/.config
hash -d nvimcfg=~/.config/nvim

[[ -f $PPORTABLES/.named-dirs.zsh ]] && . $PPORTABLES/.named-dirs.zsh
