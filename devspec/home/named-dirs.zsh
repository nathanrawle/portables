## named directories
hash -d code=~/code
hash -d homebrew=$HOMEBREW_PREFIX
hash -d portables=$PORTABLES
hash -d omz=$ZSH
hash -d cfg=~/.config
hash -d nvimcfg=~/.config/nvim

[[ -d $PPORTABLES ]] && . $PPORTABLES/.named-dirs.zsh
