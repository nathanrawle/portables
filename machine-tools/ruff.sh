#!/usr/bin/env bash
case "$1" in
    install)
        if ! uv tool list | grep -q 'ruff'; then
            echo uv:ruff
        fi
    ;;
esac
