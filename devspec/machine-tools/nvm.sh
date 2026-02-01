#!/bin/sh

# Installs Node Version Manager (NVM)

case "$1" in
    install)
        echo self-install
	;;
    self-install)
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh | bash
        ;;
esac
