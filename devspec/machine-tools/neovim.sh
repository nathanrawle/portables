#!/bin/sh
case "$1" in
    install) command -v nvim >/dev/null 2&>1 || echo syspkgmgr:neovim ;;
esac
