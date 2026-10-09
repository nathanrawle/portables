#!/usr/bin/env bash

. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)/lib/maintenance.bash" || exit 1
tool_init "$@"

require_tmux_version() {
  local output major minor
  output="$(tmux -V)" || return 1
  if [[ "$output" =~ ^tmux\ ([0-9]+)\.([0-9]+)([a-z]*)$ ]]; then
    major="${BASH_REMATCH[1]}"
    minor="${BASH_REMATCH[2]}"
    if ((major > 3 || (major == 3 && minor >= 8))); then return 0; fi
  fi
  log -e "tmux 3.8 or newer required (found $output); upgrade tmux before configuring it"
  return 1
}

case "$1" in
  install)
    if command -v tmux >/dev/null 2>&1; then require_tmux_version
    else echo "syspkgmgr:tmux"; fi
    command -v jq >/dev/null 2>&1 || echo "syspkgmgr:jq"
    ;;
  config) require_commands tmux jq && require_tmux_version ;;
esac
