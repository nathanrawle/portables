# This file contains preferred key bindings that should override any plugin defaults.

bindkey '\eq'             push-line-or-edit  # multi-line push
bindkey ^U                backward-kill-line
bindkey ^Z                kill-whole-line

### tab to cycle through menu completions
_clear_postdisplay_then_menu_select() {
  POSTDISPLAY=
  zle menu-select -w
}
zle -N clear-postdisplay-then-menu-select _clear_postdisplay_then_menu_select

# Autosuggestions must not wrap this widget or the completion style is lost.
ZSH_AUTOSUGGEST_IGNORE_WIDGETS+=( clear-postdisplay-then-menu-select )

bindkey                            '^I' clear-postdisplay-then-menu-select
bindkey               "$terminfo[kcbt]" clear-postdisplay-then-menu-select
bindkey -M menuselect              '^I' menu-complete
bindkey -M menuselect "$terminfo[kcbt]" reverse-menu-complete

bindkey -s ^f "taw -ts\n"
bindkey -s '\ej' "tmux-sessionizer -s 0\n"
bindkey -s '\ek' "tmux-sessionizer -s 1\n"
bindkey -s '\el' "tmux-sessionizer -s 2\n"

# Oh My Zsh resets the main map after autocomplete registers these widgets.
for autocomplete_key in '\e[A' '\eOA'; do
  bindkey -M main "$autocomplete_key" up-line-or-search
done
for autocomplete_key in '\e[B' '\eOB'; do
  bindkey -M main "$autocomplete_key" down-line-or-select
done
for autocomplete_key in '\e\e[A' '\e\eOA' '\e[1;3A'; do
  bindkey -M main "$autocomplete_key" history-search-backward
done
for autocomplete_key in '\e\e[B' '\e\eOB' '\e[1;3B'; do
  bindkey -M main "$autocomplete_key" menu-select
done
unset autocomplete_key

bindkey -s ^xgc 'git commit -m ""^b'
