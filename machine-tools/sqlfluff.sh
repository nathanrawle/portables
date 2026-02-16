#!/usr/bin/env bash
case "$1" in
    install)
        if ! uv tool list | grep -q 'sqlfluff'; then
            echo uv:sqlfluff
        fi
    ;;
esac
