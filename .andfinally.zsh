# I want these no matter which zsh framework I'm using

## add my functions to fpath
### `PORTABLES` and `MYFUNCS` must already be set in the environment
[[ -d $MYFUNCS ]] || mkdir -p $MYFUNCS
ln -f $PORTABLES/fns/* $MYFUNCS
[[ $fpath = *$MYFUNCS* ]] || fpath+=$MYFUNCS
autoload -U ${MYFUNCS}/*(:t)

## preferred key bindings
bindkey '\eq' push-line-or-edit  # multi-line push
bindkey ^U backward-kill-line
bindkey ^Z kill-whole-line

## named directories
hash -d code=~/code
hash -d homebrew=$HOMEBREW_PREFIX
hash -d portables=$PORTABLES

[[ -e $PPORTABLES/.andfinally.zsh ]] && . $PPORTABLES/.andfinally.zsh

## ensure $path and $fpath entries are unique
typeset -U path fpath