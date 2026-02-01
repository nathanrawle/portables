#!/bin/sh
case "$1" in
    install)
        if ! command -v fd >/dev/null 2>&1 && ! command -v fdfind >/dev/null 2>&1; then
            if [ "$OS" = "Linux" ] && . /etc/os-release && [ "$ID" = "ubuntu" ]; then
                echo "syspkgmgr:fd-find"
            else
                echo "syspkgmgr:fd"
            fi
        fi
        ;;
    config)
        # On Ubuntu, `fd-find` is the binary name. We can create a symlink
        # to `fd` to normalize it, if one doesn't exist.
        if command -v fdfind >/dev/null 2>&1 && ! command -v fd >/dev/null 2>&1; then
            if [ -d "$HOME/.local/bin" ]; then 
                echo "Symlinking fdfind to fd in ~/.local/bin"
                mkdir -p "$HOME/.local/bin"
                ln -sf "$(command -v fdfind)" "$HOME/.local/bin/fd"
            fi
        fi
        ;;
esac
