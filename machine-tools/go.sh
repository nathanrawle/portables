#!/usr/bin/env bash

. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)/lib/maintenance.bash" || exit 1
tool_init "$@"

GO_VERSION=${GO_VERSION:-1.26.0}
GO_INSTALL_ROOT=${GO_INSTALL_ROOT:-/usr/local/go}
case "$1" in
  install) command -v go >/dev/null 2>&1 || echo self-install ;;
  self-install)
    require_commands curl tar
    case "$OS:$(uname -m)" in
      Darwin:arm64|Darwin:aarch64) platform=darwin-arm64 ;;
      Darwin:x86_64) platform=darwin-amd64 ;;
      Linux:arm64|Linux:aarch64) platform=linux-arm64 ;;
      Linux:x86_64) platform=linux-amd64 ;;
      *) log -e "unsupported Go platform"; exit 1 ;;
    esac
    temp="$(mktemp -d "${TMPDIR:-/tmp}/portables-go.XXXXXX")"
    trap 'rm -rf -- "$temp"' EXIT
    curl -fsSL "https://go.dev/dl/go$GO_VERSION.$platform.tar.gz" -o "$temp/go.tar.gz"
    tar -xzf "$temp/go.tar.gz" -C "$temp"
    [[ -x "$temp/go/bin/go" ]] || { log -e "invalid Go archive"; exit 1; }
    require_commands sudo
    backup=
    if [[ -e "$GO_INSTALL_ROOT" || -L "$GO_INSTALL_ROOT" ]]; then
      backup="$(sudo mktemp -d "$GO_INSTALL_ROOT.backup.XXXXXX")"
      sudo mv "$GO_INSTALL_ROOT" "$backup/go"
      log -i "previous Go installation preserved at $backup/go"
    fi
    if ! sudo mv "$temp/go" "$GO_INSTALL_ROOT"; then
      sudo rm -rf -- "$GO_INSTALL_ROOT" || { log -e "failed to remove partial Go installation"; exit 1; }
      if [[ -n "$backup" ]] && ! sudo mv "$backup/go" "$GO_INSTALL_ROOT"; then
        log -e "failed to restore previous Go installation from $backup/go"
      fi
      exit 1
    fi
    ;;
esac
