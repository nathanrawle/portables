#!/usr/bin/env bash

[[ -n "${OS-}" ]] || OS="$(uname -s)"
if [[ "$OS" = Linux ]]; then
  [[ -n "${PRETTY_NAME-}" ]] || . /etc/os-release
fi
case "$1" in
    install)
      if ! command -v starship >/dev/null 2>&1; then
      case "$OS" in
        Darwin) echo syspkgmgr:starship ;;
        Linux)
          case "$ID" in
            ubuntu)
              if [[ $VERSION_ID -ge 25.04 ]]; then
                echo syspkgmgr:starship
              else
                echo self-install
              fi
              ;;
            debian)
              if [[ $VERSION_ID -ge 13 ]]; then
                echo syspkgmgr:starship
              else
                echo self-install
              fi
              ;;
          esac
          ;;
      esac
      fi
      ;;
    self-install) curl -sS https://starship.rs/install.sh | sh ;;
esac
