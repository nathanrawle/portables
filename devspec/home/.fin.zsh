# Bash completion compatibility
autoload -Uz +X bashcompinit
complete -o nospace -C "$(command -v terraform)" terraform

if [[ "$PROMPT_FW" = "p10k" ]]; then
  source "$HOME/.p10k.zsh"
fi

# Ensure $path and $fpath entries are unique
typeset -U PATH path fpath

# Welcome message
if command -v fortune >/dev/null 2>&1 && command -v cowsay >/dev/null 2>&1; then
  cs_mods=( b d g p s t w y )
  cs_opt=${cs_mods[$(( RANDOM % ${#cs_mods} + 1 ))]}
  fortune | cowsay -"$cs_opt" -n
  unset cs_mods cs_opt
fi
