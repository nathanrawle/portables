#!/usr/bin/env bash

[[ -n "${HOME-}" ]] || HOME=~
[[ -n "${OS-}" ]] || OS="$(uname -s)"
if [[ "$OS" = Linux ]]; then
  [[ -n "${PRETTY_NAME-}" ]] || . /etc/os-release
fi
fonts_dir="${HOME}/.local/share/fonts"
case "$1" in
    install)
      FIRAFILES=( "$fonts_dir"/ttf/FiraCode* )
      if [[ ${#FIRAFILES[@]} -eq 0 ]]; then
        echo self-install
      fi
      ;;
    self-install)
      mkdir -p "${fonts_dir}"
      version=5.2
      zip=Fira_Code_v${version}.zip
      curl --fail --location --show-error https://github.com/tonsky/FiraCode/releases/download/${version}/${zip} --output ${zip}
      unzip -o -q -d ${fonts_dir} ${zip}
      rm ${zip}
      ;;
    config) fc-cache -f ;;
esac
