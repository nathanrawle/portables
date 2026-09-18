#!/usr/bin/env bash

PORTABLES="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)" || return 1
PORTABLE_HOME="$PORTABLES/home"
MACHINE_TOOLS="$PORTABLES/machine-tools"
HOME=${HOME:-~}
OS=${OS:-$(uname -s)}
if [[ "$OS" = Linux && -z "${ID:-}" && -r /etc/os-release ]]; then
  . /etc/os-release || return 1
fi
ID=${ID:-}
VERSION_ID=${VERSION_ID:-}
PRETTY_NAME=${PRETTY_NAME:-$OS}
PATH="$HOME/.local/bin:$HOME/.local/scripts:/usr/local/go/bin:$PATH"
if [[ "$OS" = Darwin ]]; then
  PATH="$PATH:/opt/homebrew/bin:/usr/local/bin"
fi
export PORTABLES PORTABLE_HOME MACHINE_TOOLS HOME OS ID VERSION_ID PRETTY_NAME PATH
. "$PORTABLES/log"
FAILURES=()

failure() {
  FAILURES+=( "$*" )
  log -e "$*"
}

finish() {
  local item
  if [[ ${#FAILURES[@]} -gt 0 ]]; then
    log -e "${#FAILURES[@]} failed or blocked step(s):"
    for item in "${FAILURES[@]}"; do log -e "  $item"; done
    return 1
  fi
  log "maintenance complete"
}

require_commands() {
  local cmd missing=0
  for cmd in "$@"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      log -e "required command unavailable: $cmd"
      missing=1
    fi
  done
  return "$missing"
}

require_files() {
  local file missing=0
  for file in "$@"; do
    if [[ ! -r "$file" ]]; then
      log -e "required file unavailable: $file"
      missing=1
    fi
  done
  return "$missing"
}

tool_init() {
  if [[ $# != 1 ]]; then
    printf 'Usage: %s install|self-install|config\n' "${0##*/}" >&2
    exit 2
  fi
  case "$1" in
    install|self-install|config) ;;
    --help) printf 'Usage: %s install|self-install|config\n' "${0##*/}"; exit 0 ;;
    *) log -e "unknown hook: $1"; exit 2 ;;
  esac
  LOG_NAME="${LOG_NAME:+$LOG_NAME.}${0##*/}:$1"
  export LOG_NAME
  set -eo pipefail
}

package_available() {
  case "$OS:$ID" in
    Darwin:*) brew info "$1" >/dev/null 2>&1 ;;
    Linux:ubuntu|Linux:debian|Linux:pop) apt-cache show "$1" 2>/dev/null | grep '^Package:' >/dev/null ;;
    Linux:arch) pacman -Si "$1" >/dev/null 2>&1 ;;
    Linux:fedora) dnf info --available "$1" >/dev/null 2>&1 ;;
    *) return 1 ;;
  esac
}

clone_missing() {
  local url="$1" destination="$2"
  if [[ -d "$destination" ]]; then return 0; fi
  if [[ -e "$destination" || -L "$destination" ]]; then
    log -e "cannot clone into existing path: $destination"
    return 1
  fi
  git clone --depth 1 "$url" "$destination"
}

user_git_file() {
  GIT_USER_FILE="${GIT_CONFIG_GLOBAL:-$HOME/.gitconfig}"
  if [[ -L "$GIT_USER_FILE" ]]; then
    log -e "refusing to write through Git user config symlink: $GIT_USER_FILE"
    return 1
  fi
  require_external_destination "$GIT_USER_FILE" || return 1
  mkdir -p "$(dirname "$GIT_USER_FILE")"
}

require_external_destination() {
  local parent
  parent="$(dirname "$1")"
  while [[ ! -e "$parent" && ! -L "$parent" ]]; do parent="$(dirname "$parent")"; done
  parent="$(cd "$parent" && pwd -P)" || return 1
  case "$parent/" in
    "$PORTABLES/"*) log -e "machine-local file must live outside the repository: $1"; return 1 ;;
  esac
}
