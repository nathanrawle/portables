#!/usr/bin/env bash

LOG_NAME="${LOG_NAME:+$LOG_NAME.}go:${1}"
functions log >/dev/null 2>&1 || . "$PORTABLES"/log
GO_VERSION="${GO_VERSION:-1.26.0}"

case "$1" in
  install)
    command -v /usr/local/go/bin/go >/dev/null 2>&1 || echo self-install
    ;;
  self-install)
    log "installing go"
    OS="${OS:-$(uname -s)}"
    case "${OS}-$(uname -m)" in
      Darwin-aarch_64)
        os_arch="darwin-arm64"
        ;;
      Darwin-x86_64)
        os_arch="darwin-amd64"
        ;;
      Linux-aarch_64)
        os_arch="linux-arm64"
        ;;
      Linux-x86_64)
        os_arch="linux-amd64"
        ;;
    esac

    tarball="go${GO_VERSION}.${os_arch}.tar.gz"
    temp_path="/tmp/go/${tarball}"
    mkdir -p "${temp_path%/*}"

    curl -fsSLo "$temp_path" "https://go.dev/dl/${tarball}" \
    && rm -rf /usr/local/go \
    && sudo tar -C /usr/local -xzf "$temp_path"
    ;;
esac
