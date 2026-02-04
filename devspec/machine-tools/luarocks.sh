#!/bin/sh
case "$1" in
    install) command -v luarocks >/dev/null 2>&1 || echo syspkgmgr:luarocks ;;
esac
