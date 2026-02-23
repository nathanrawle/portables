#!/usr/bin/env bash
[[ -n "$OS" ]] || OS="$(uname -s)"
case "$1" in
    install)
      command -v lazygit >/dev/null 2>&1 && exit 0
      case "$OS" in
        Darwin) echo syspkgmgr:lazygit ;;
        Linux)
          [[ -n "$ID" ]] || . /etc/os-release
          case "$ID" in
            ubuntu)
              if [[ $VERSION_ID < 25.05 ]]; then
                echo "self-install"
              else
                echo "syspkgmgr:lazygit"
              fi
              ;;
            debian)
              if [[ $VERSION_ID < 13 ]]; then
                echo "self-install"
              else
                echo "syspkgmgr:lazygit"
              fi
              ;;
          esac
          ;;
      esac
      ;;
    self-install)
      LAZYGIT_VERSION=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | \grep -Po '"tag_name": *"v\K[^"]*')
      curl -Lo /tmp/lazygit/lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/download/v${LAZYGIT_VERSION}/lazygit_${LAZYGIT_VERSION}_Linux_x86_64.tar.gz"
      tar xf /tmp/lazygit/lazygit.tar.gz lazygit
      sudo install lazygit -D -t /usr/local/bin/
      ;;
esac
