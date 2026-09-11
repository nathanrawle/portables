#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
HOOK_DIR="$SCRIPT_DIR/agent-status"

file_mode() {
  local path="$1"

  stat -f '%Lp' "$path" 2>/dev/null || stat -c '%a' "$path"
}

merge_hooks() (
  local fragment="$1"
  local requested_target="$2"
  local target="$requested_target"
  local target_dir temp mode

  if [[ -L "$requested_target" ]]; then
    target="$(realpath "$requested_target")" || {
      printf 'agent-status: refusing broken symlink: %s\n' "$requested_target" >&2
      return 1
    }
  fi

  target_dir="$(dirname -- "$target")"
  mkdir -p "$target_dir"
  if [[ -e "$target" ]]; then
    jq -e . "$target" >/dev/null || {
      printf 'agent-status: refusing malformed JSON: %s\n' "$requested_target" >&2
      return 1
    }
  fi
  jq -e . "$fragment" >/dev/null

  temp="$(mktemp "$target_dir/.taw-agent-status.XXXXXX")"
  trap 'rm -f "$temp"' EXIT
  if [[ -e "$target" ]]; then
    jq --slurpfile fragment "$fragment" -f "$HOOK_DIR/merge-hooks.jq" "$target" >"$temp"
    mode="$(file_mode "$target")"
    chmod "$mode" "$temp"
  else
    jq --slurpfile fragment "$fragment" -f "$HOOK_DIR/merge-hooks.jq" <(printf '{}\n') >"$temp"
    chmod 600 "$temp"
  fi
  mv -f "$temp" "$target"
  temp=
)

case "${1:-}" in
  install)
    if command -v jq >/dev/null 2>&1; then
      echo self-install
    else
      echo syspkgmgr:jq
    fi
    ;;
  self-install)
    ;;
  config)
    command -v jq >/dev/null 2>&1 || {
      printf 'agent-status: jq is required to merge agent hooks\n' >&2
      exit 1
    }
    merge_hooks "$HOOK_DIR/codex.json" "$HOME/.codex/hooks.json"
    merge_hooks "$HOOK_DIR/claude.json" "$HOME/.claude/settings.json"
    ;;
esac
