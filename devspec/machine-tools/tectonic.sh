#!/bin/sh
case "$1" in
    install) command -v tectonic >/dev/null 2>&1 || echo syspkgmgr:tectonic ;;
esac
