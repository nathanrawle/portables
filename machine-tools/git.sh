#!/usr/bin/env bash

. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)/lib/maintenance.bash" || exit 1
tool_init "$@"

case "$1" in
  install) command -v git >/dev/null 2>&1 || echo syspkgmgr:git ;;
  config)
    require_commands git
    for field in name email; do
      if ! git config --global --includes --get "user.$field" >/dev/null; then
        case "$field" in
          name) value=${GIT_NAME:-}; variable=GIT_NAME ;;
          email) value=${GIT_EMAIL:-}; variable=GIT_EMAIL ;;
        esac
        if [[ -z "$value" ]]; then
          [[ -t 0 ]] || { log -e "set $variable or configure user.$field before retrying"; exit 1; }
          read -r -p "Git $field: " value
        fi
        [[ -n "$value" ]] || { log -e "Git $field cannot be empty"; exit 1; }
        user_git_file
        git config --file "$GIT_USER_FILE" "user.$field" "$value"
      fi
    done
    ;;
esac
