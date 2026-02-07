# This file contains preferred key bindings that should override any plugin defaults.

bindkey '\eq'             push-line-or-edit  # multi-line push
bindkey ^U                backward-kill-line
bindkey ^Z                kill-whole-line

### tab to cycle through menu completions
bindkey                            '^I' menu-select
bindkey               "$terminfo[kcbt]" menu-select
bindkey -M menuselect              '^I' menu-complete
bindkey -M menuselect "$terminfo[kcbt]" reverse-menu-complete

bindkey -s ^f "tmux-sessionizer\n"
bindkey -s '\ej' "tmux-sessionizer -s 0\n"
bindkey -s '\ek' "tmux-sessionizer -s 1\n"
bindkey -s '\el' "tmux-sessionizer -s 2\n"

