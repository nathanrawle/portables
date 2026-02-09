#!/bin/sh

[ -n "$OS"] || OS="$(uname -s)"
case "$1" in
    install)
        if ! command -v uv >/dev/null 2>&1; then
          case "$OS" in
            Darwin) echo "syspkgmgr:uv" ;;
            *) echo "self-install" ;;
          esac
        fi
        ;;
    self-install)
        curl -LsSf https://astral.sh/uv/install.sh | sh
        ;;
esac
