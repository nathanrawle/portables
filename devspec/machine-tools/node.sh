#!/bin/sh

# Installs the latest LTS version of Node.js using NVM.

case "$1" in
    deps)
        # This script depends on nvm.sh having been run, but nvm is not a system package.
        # The dependency is managed by the execution order in run.sh.
        ;;
    config)
        # Each script must be self-contained. Source nvm to get the nvm function.
        export NVM_DIR="$HOME/.nvm"
        if [ -s "$NVM_DIR/nvm.sh" ]; then
            . "$NVM_DIR/nvm.sh"
            
            # Check if any version of node is installed by nvm
            # `nvm list` returns a non-zero exit code if no versions are installed.
            if ! nvm list >/dev/null 2>&1;
            then
                echo "Installing latest LTS version of Node.js..."
                nvm install --lts
                nvm alias default 'lts/*' # Set a default
            else
                echo "A version of Node.js is already installed via NVM."
            fi
        else
            echo "Error: NVM not found. Cannot install Node.js." >&2
            exit 1
        fi
        ;;
esac
