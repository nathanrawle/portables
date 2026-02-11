#!/bin/sh
case "$1" in
install)
  command -v curl >/dev/null 2>&1 ||
    case "$OS" in
    Darwin)
      echo self-install
      ;;
    *) echo syspkgmgr:curl ;;
    esac
  ;;
self-install) xcode-select --install ;;
esac
