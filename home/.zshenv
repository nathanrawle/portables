# Disable distro completion only when this checkout owns the user startup path.
_portables_zshenv=${${(%):-%x}:A}
_portables_zshrc=${ZDOTDIR:-$HOME}/.zshrc
if [[ -e "$_portables_zshrc" && "$_portables_zshrc" -ef "${_portables_zshenv:h}/.zshrc" ]]; then
  skip_global_compinit=1
fi
unset _portables_zshenv _portables_zshrc
