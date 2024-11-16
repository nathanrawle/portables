## `PORTABLES` and `MYFUNCS` must already be set in the environment
print $MYFUNCS
# add my functions to fpath
[[ -d $MYFUNCS ]] || mkdir -p $MYFUNCS
ln -f $PORTABLES/fns/* $MYFUNCS
[[ $fpath = *$MYFUNCS* ]] || fpath+=$MYFUNCS
autoload -U ${fpath[-1]}/*(:t)
