# I want these no matter which zsh framework I'm using

## add my functions to fpath
### `PORTABLES` and `MYFUNCS` must already be set in the environment
[[ -d $MYFUNCS ]] || mkdir -p $MYFUNCS
ln -f $PORTABLES/fns/* $MYFUNCS
[[ $fpath = *$MYFUNCS* ]] || fpath+=$MYFUNCS
autoload -U ${fpath[-1]}/*(:t)

## preferred key bindings
bindkey '\eq' push-line-or-edit  # multi-line push
bindkey ^U backward-kill-line
bindkey ^Z kill-whole-line
