#!/usr/bin/env bash

. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)/lib/maintenance.bash" || exit 1
tool_init "$@"

case "$1" in
  install)
    case "$OS" in
      Darwin) command -v git-credential-manager >/dev/null 2>&1 || echo syspkgmgr:cask:git-credential-manager ;;
      Linux) command -v git-credential-oauth >/dev/null 2>&1 || echo syspkgmgr:git-credential-oauth ;;
      *) log -e "unsupported credential platform: $OS"; exit 1 ;;
    esac
    ;;
  config)
    require_commands git
    case "$OS" in
      Darwin) defaults=( manager ) ;;
      Linux) defaults=( 'cache --timeout 21600' oauth ) ;;
      *) log -e "unsupported credential platform: $OS"; exit 1 ;;
    esac
    config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/git"
    managed="$config_dir/portables-credentials.conf"
    marker='# Managed by Portables: credential defaults.'
    if [[ -L "$managed" ]] || { [[ -e "$managed" ]] && [[ "$(head -n 1 "$managed")" != "$marker" ]]; }; then
      log -e "preserving unmanaged credential config: $managed"
      exit 1
    fi
    require_external_destination "$managed"
    mkdir -p "$config_dir"
    user_git_file
    legacy_pair=0
    if [[ -f "$GIT_USER_FILE" ]]; then
      legacy="$(git config --file "$GIT_USER_FILE" --get-all credential.helper || true)"
      if [[ "$legacy" = $'manager\noauth' ]]; then
        legacy_pair=1
      fi
    fi
    temp="$(mktemp -d "$config_dir/.portables-credentials.XXXXXX")"
    trap 'rm -rf -- "$temp"' EXIT
    rc=0
    git config --global --includes --show-origin -z --get-all credential.helper >"$temp/helpers" || rc=$?
    [[ "$rc" -le 1 ]] || exit "$rc"
    custom=0
    while IFS= read -r -d '' origin && IFS= read -r -d '' helper; do
      if [[ "$legacy_pair" = 1 && "${origin#file:}" -ef "$GIT_USER_FILE" ]]; then continue; fi
      [[ "$origin" = "file:$managed" || "${origin#file:}" -ef "$managed" ]] || custom=1
    done <"$temp/helpers"
    printf '%s\n' "$marker" >"$temp/config"
    if [[ "$custom" = 0 ]]; then
      case "$OS" in
        Darwin) require_commands git-credential-manager ;;
        Linux) require_commands git-credential-oauth ;;
      esac
      for helper in "${defaults[@]}"; do
        git config --file "$temp/config" --add credential.helper "$helper"
      done
    else
      log -i "preserving custom credential helpers"
    fi
    if [[ "$legacy_pair" = 1 ]]; then
      backup="$(mktemp "$GIT_USER_FILE.bak.XXXXXX")"
      cp -p "$GIT_USER_FILE" "$backup"
      git config --file "$GIT_USER_FILE" --unset-all credential.helper
      log -i "legacy helper pair backed up to $backup"
    fi
    chmod 600 "$temp/config"
    mv "$temp/config" "$managed"
    includes="$(git config --file "$GIT_USER_FILE" --get-all include.path 2>/dev/null || true)"
    found=0
    while IFS= read -r included; do [[ "$included" != "$managed" ]] || found=1; done <<<"$includes"
    [[ "$found" = 1 ]] || git config --file "$GIT_USER_FILE" --add include.path "$managed"
    ;;
esac
