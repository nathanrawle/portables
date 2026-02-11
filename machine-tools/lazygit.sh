#!/bin/sh
case "$1" in
    install) command -v lazygit >/dev/null 2>&1 || echo syspkgmgr:lazygit ;;
esac
