#!/usr/bin/env bash
case "$1" in
    install) command -v zoxide >/dev/null 2>&1 || echo syspkgmgr:zoxide ;;
esac
