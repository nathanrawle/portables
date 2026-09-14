#!/usr/bin/env bash

. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)/lib/maintenance.bash" || exit 1
tool_init "$@"

GO_VERSION=${GO_VERSION:-1.26.0}
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
    if [[ -e /usr/local/go || -L /usr/local/go ]]; then
      backup="$(sudo mktemp -d /usr/local/go.backup.XXXXXX)"
      sudo mv /usr/local/go "$backup/go"
      log -i "previous Go installation preserved at $backup/go"
    fi
    if ! sudo mv "$temp/go" /usr/local/go; then
      [[ -z "$backup" ]] || sudo mv "$backup/go" /usr/local/go
      exit 1
    fi
    ;;
esac
