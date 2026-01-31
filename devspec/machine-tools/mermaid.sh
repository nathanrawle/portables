#!/bin/sh
case "$1" in
    deps)
        # mermaid-cli is installed via npm, which comes with Node.
        # The dependency is managed by the execution order in run.sh.
        ;;
    config)
        if command -v npm >/dev/null 2>&1; then
            if ! command -v mmdc >/dev/null 2>&1; then
                echo "Installing mermaid-cli via npm..."
                npm install -g @mermaid-js/mermaid-cli
            else
                echo "mermaid-cli is already installed."
            fi
        else
            echo "Warning: npm not found. Cannot install mermaid-cli." >&2
        fi
        ;;
esac