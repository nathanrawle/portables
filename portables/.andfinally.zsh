# I want these no matter which zsh framework I'm using

## add my functions to fpath
### `PORTABLES` and `MYFUNCS` must already be set in the environment
[[ -d $MYFUNCS ]] || mkdir -p $MYFUNCS
ln -f $PORTABLES/fns/* $MYFUNCS
[[ $fpath = *$MYFUNCS* ]] || fpath+=$MYFUNCS
autoload -U ${MYFUNCS}/*(:t)

## preferred key bindings
bindkey '\eq'             push-line-or-edit  # multi-line push
bindkey ^U                backward-kill-line
bindkey ^Z                kill-whole-line

### tab to cycle through menu completions
bindkey                            '^I' menu-select
bindkey               "$terminfo[kcbt]" menu-select
bindkey -M menuselect              '^I' menu-complete
bindkey -M menuselect "$terminfo[kcbt]" reverse-menu-complete

# Named directories
[[ -e $PORTABLES/.named-dirs.zsh ]] && . $PORTABLES/.named-dirs.zsh

## ensure $path and $fpath entries are unique
typeset -U path fpath

## cowsay
local cs_mods cs_opt=r
if (( RANDOM % 2 )); then
  cs_mods=( b d g p s t w y )
  cs_opt=${cs_mods[$(( RANDOM % ${#cs_mods} + 1 ))]}
fi
fortune | cowsay -"$cs_opt" -n
unset cs_mods cs_opt
