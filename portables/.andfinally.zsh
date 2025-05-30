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

# ## Workaround for zsh_autocomplete and p10k show_on_command redraw conflict
# ### Save originals
# functions[_p9k_widget_zle-line-init-orig]=${functions[_p9k_widget_zle-line-init]}
# functions[_p9k_widget_zle-keymap-select-orig]=${functions[_p9k_widget_zle-keymap-select]}

# ### Wrap line-init to skip redraw during history-menu → LASTWIDGET is 'history-menu-widget'
# function _p9k_widget_zle-line-init() {
#   [[ $LASTWIDGET == history-menu-widget ]] && return
#   _p9k_widget_zle-line-init-orig "$@"
# }

# ### Wrap keymap-select similarly
# function _p9k_widget_zle-keymap-select() {
#   [[ $LASTWIDGET == history-menu-widget ]] && return
#   _p9k_widget_zle-keymap-select-orig "$@"
# }

# ### Rebind ZLE hooks to our wrappers
# zle -N zle-line-init   _p9k_widget_zle-line-init
# zle -N zle-keymap-select _p9k_widget_zle-keymap-select

## cowsay
local cs_mods cs_opt=r
if (( RANDOM % 2 )); then
  cs_mods=( b d g p s t w y )
  cs_opt=${cs_mods[$(( RANDOM % ${#cs_mods} + 1 ))]}
fi
fortune | cowsay -"$cs_opt" -n
unset cs_mods cs_opt
