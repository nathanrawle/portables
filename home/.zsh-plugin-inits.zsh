# Keep autosuggestions stable while autocomplete owns the editor widgets.
ZSH_AUTOSUGGEST_MANUAL_REBIND=1
for zsh_autosuggestions in \
  /opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh \
  /usr/local/share/zsh-autosuggestions/zsh-autosuggestions.zsh \
  "${XDG_DATA_HOME:-$HOME/.local/share}/portables/zsh/zsh-autosuggestions/zsh-autosuggestions.zsh"
do
  if [[ -r "$zsh_autosuggestions" ]]; then
    source "$zsh_autosuggestions"
    break
  fi
done
unset zsh_autosuggestions

if [[ "$PROMPT_FW" = starship ]]; then
  command -v starship >/dev/null 2>&1 && eval "$(starship init zsh)"
elif [[ "$PROMPT_FW" = p10k ]]; then
  for powerlevel10k in \
    /opt/homebrew/share/powerlevel10k/powerlevel10k.zsh-theme \
    /usr/local/share/powerlevel10k/powerlevel10k.zsh-theme \
    "${XDG_DATA_HOME:-$HOME/.local/share}/portables/zsh/powerlevel10k/powerlevel10k.zsh-theme"
  do
    if [[ -r "$powerlevel10k" ]]; then
      source "$powerlevel10k"
      break
    fi
  done
  unset powerlevel10k
fi
