# Syntax highlighting runs last so it observes every final editor widget.
for zsh_syntax_highlighting in \
  /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh \
  /usr/local/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh \
  "${XDG_DATA_HOME:-$HOME/.local/share}/portables/zsh/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
do
  if [[ -r "$zsh_syntax_highlighting" ]]; then
    source "$zsh_syntax_highlighting"
    break
  fi
done
unset zsh_syntax_highlighting
