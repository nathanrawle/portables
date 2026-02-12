#!/bin/sh
case "$1" in
    install) command -v magick >/dev/null 2>&1 || echo syspkgmgr:imagemagick ;; 
esac
