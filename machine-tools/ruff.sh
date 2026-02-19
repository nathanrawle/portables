#!/usr/bin/env bash
case "$1" in
    install)
        if ! command -v uv >/dev/null 2>&1 || ! uv tool list | grep -q 'ruff'; then
            echo uv:ruff
        fi
    ;;
esac
