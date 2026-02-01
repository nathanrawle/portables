#!/bin/sh

case "$1" in
    install) echo nvm:--lts ;;
    config) npm config set prefix "$HOME/.npm-global" ;;
esac
