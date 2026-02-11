#!/bin/sh
case "$1" in
  install)
    command -v git >/dev/null 2>&1 \
    || case "$OS" in
      Darwin)
        echo self-install
        ;;
      *) echo syspkgmgr:git ;;
    esac
    ;;
  self-install) xcode-select --install ;;
  config)
    echo "Configuring global git excludesfile..."
    git config --global --unset-all core.excludesfile || true # Ignore error if not set
    git config --global --add core.excludesfile "$HOME/.config/git/ignore"
    git config --global --add core.excludesfile "$HOME/.gitignore"
    ;;
esac
