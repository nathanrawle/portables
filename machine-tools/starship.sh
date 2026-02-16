#!/usr/bin/env bash
case "$1" in
    install) command -v starship >/dev/null 2>&1 || echo syspkgmgr:starship ;; 
esac
