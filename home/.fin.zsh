# Bash completion compatibility
autoload -Uz +X bashcompinit
if (( $+commands[terraform] )); then
  _portables_terraform_complete() {
    case $words[CURRENT] in
      -var-file=*|-backend-config=*)
        compset -P '*='
        _files
        ;;
      *)
        _bash_complete -o nospace -C "$commands[terraform]" && return
        if [[ $words[CURRENT] == *=* ]]; then
          compset -P '*='
        fi
        _files
        ;;
    esac
  }
  compdef _portables_terraform_complete terraform
fi

if [[ "$PROMPT_FW" = "p10k" ]]; then
  source "$HOME/.p10k.zsh"
fi

# Ensure $path and $fpath entries are unique
typeset -U PATH path fpath

setopt hist_ignore_all_dups glob_dots

# Welcome message
if command -v fortune >/dev/null 2>&1 && command -v cowsay >/dev/null 2>&1; then
  cs_mods=( b d g p s t w y )
  cs_opt=${cs_mods[$(( RANDOM % ${#cs_mods} + 1 ))]}
  fortune | cowsay -"$cs_opt" -n
  unset cs_mods cs_opt
fi
