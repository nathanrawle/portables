#!/usr/bin/env bash

[[ -n "$OS" ]] || OS="$(uname -s)"

case "$1" in
  install)
    case "$OS" in
      Linux)
        [[ -n "$ID" ]] || . /etc/os-release
        case "$ID" in
          ubuntu|fedora) command -v fdfind >/dev/null 2>&1 || echo "syspkgmgr:fd-find" ;;
          *) command -v fd >/dev/null 2>&1 || echo "syspkgmgr:fd" ;;
        esac
        ;;
      *) command -v fd >/dev/null 2>&1 || echo "syspkgmgr:fd" ;;
    esac
esac
