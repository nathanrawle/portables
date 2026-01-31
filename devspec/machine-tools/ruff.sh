#!/bin/sh
case "$1" in
    deps) ;;
    config)
        if command -v uv >/dev/null 2>&1; then
            if ! uv tool list | grep -q 'ruff'; then
                echo "Installing ruff via uv..."
                uv tool install ruff
            else
                echo "ruff is already installed via uv."
            fi
        else
            echo "Warning: uv not found. Cannot install ruff." >&2
        fi
        ;;
esac