#!/usr/bin/env bash
case "$1" in
    install) command -v rg >/dev/null 2>&1 || echo syspkgmgr:ripgrep ;; 
esac
