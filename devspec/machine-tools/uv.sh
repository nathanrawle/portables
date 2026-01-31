#!/bin/sh
case "$1" in
    deps)
        # On macOS, we can install with brew. On Linux, we'll use the installer script.
        if [ "$(uname -s)" = "Darwin" ]; then
            echo "uv"
        fi
        ;;
    config)
        if ! command -v uv >/dev/null 2>&1; then
            echo "Installing uv..."
            curl -LsSf https://astral.sh/uv/install.sh | sh
        fi
        ;;
esac