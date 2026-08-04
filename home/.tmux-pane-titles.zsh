_tmux_pane_title_preexec() {
  emulate -L zsh
  [[ -n ${TMUX-} ]] || return 0

  setopt extended_glob

  local command_name="${1[(wr)^(*=*|sudo|ssh|mosh|rake|-*)]}"
  command_name="${command_name//[[:cntrl:]]/}"
  [[ -n $command_name ]] || return 0

  print -rn -- $'\e]2;'"$command_name"$'\e\\'
}

_tmux_pane_title_precmd() {
  emulate -L zsh
  [[ -n ${TMUX-} ]] || return 0

  print -rn -- $'\e]2;\e\\'
}

autoload -Uz add-zsh-hook
add-zsh-hook preexec _tmux_pane_title_preexec
add-zsh-hook precmd _tmux_pane_title_precmd
