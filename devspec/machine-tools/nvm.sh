#!/bin/sh

# Installs Node Version Manager (NVM)

case "$1" in
    deps)
        echo "curl"
        ;;
    config)
        export NVM_DIR="$HOME/.nvm"
        if [ ! -d "$NVM_DIR" ]; then
            echo "Installing NVM..."
            # Use curl (installed in pass 1) to get the installer script
            curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
        else
            echo "NVM already installed."
        fi
        ;;
esac
