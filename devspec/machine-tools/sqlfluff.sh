#!/bin/sh
case "$1" in
    deps) ;;
    config)
        if command -v uv >/dev/null 2>&1; then
            if ! uv tool list | grep -q 'sqlfluff'; then
                echo "Installing sqlfluff via uv..."
                uv tool install sqlfluff
            else
                echo "sqlfluff is already installed via uv."
            fi
        else
            echo "Warning: uv not found. Cannot install sqlfluff." >&2
        fi
        ;;
esac