#!/bin/sh
case "$1" in
    deps)
        if [ "$(uname -s)" = "Linux" ] && . /etc/os-release && [ "$ID" = "ubuntu" ]; then
            echo "fd-find"
        else
            echo "fd"
        fi
        ;;
    config)
        # On Ubuntu, `fd-find` is the binary name. We can create a symlink
        # to `fd` to normalize it, if one doesn't exist.
        if command -v fdfind >/dev/null 2>&1 && ! command -v fd >/dev/null 2>&1; then
            if [ -n "$HOME/.local/bin" ]; then 
                echo "Symlinking fdfind to fd in ~/.local/bin"
                mkdir -p "$HOME/.local/bin"
                ln -sf "$(command -v fdfind)" "$HOME/.local/bin/fd"
            fi
        fi
        ;;
esac