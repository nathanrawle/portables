# add my functions to fpath
## `PORTABLES` and `MYFUNCS` must already be set in the environment
[[ -d $MYFUNCS ]] || mkdir -p $MYFUNCS
ln -f $PORTABLES/fns/* $MYFUNCS
[[ $fpath = *$MYFUNCS* ]] || fpath+=$MYFUNCS
autoload -U ${fpath[-1]}/*(:t)

bindkey ^Q push-line-or-edit
bindkey ^U backward-kill-line
bindkey ^Z kill-whole-line