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
    require_git_version 2 30
    case "$OS" in
      Darwin)
        defaults=( manager osxkeychain )
        require_commands git-credential-manager
        ;;
      Linux)
        defaults=( 'cache --timeout 21600' oauth )
        require_commands git-credential-oauth
        ;;
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
    temp="$(mktemp -d "$config_dir/.portables-credentials.XXXXXX")"
    trap 'rm -rf -- "$temp"' EXIT
    is_managed_include() {
      local included="$1" including_file="$2" candidate candidate_dir managed_dir
      case "$included" in
        "~"*/*)
          git config --file "$temp/include-path" include.path "$included" || return 1
          candidate="$(git config --file "$temp/include-path" --path --get include.path)" || return 1
          ;;
        /*) candidate="$included" ;;
        *) candidate="$(dirname -- "$including_file")/$included" ;;
      esac
      if [[ -e "$candidate" && "$candidate" -ef "$managed" ]]; then return 0; fi
      candidate_dir="$(cd -- "$(dirname -- "$candidate")" 2>/dev/null && pwd -P)" || return 1
      managed_dir="$(cd -- "$(dirname -- "$managed")" && pwd -P)" || return 1
      [[ "$candidate_dir/${candidate##*/}" = "$managed_dir/${managed##*/}" ]]
    }
    user_git_file
    gh_path="$(type -P gh || true)"
    if [[ -n "$gh_path" && "$gh_path" != /* ]]; then
      gh_path="$(cd -- "$(dirname -- "$gh_path")" && pwd -P)/${gh_path##*/}"
    fi
    gh_helper=
    if [[ -n "$gh_path" ]]; then
      quoted_gh_path=${gh_path//\'/\'\\\'\'}
      gh_helper="!'$quoted_gh_path' auth git-credential"
    fi
    if [[ -n "${GIT_CONFIG_GLOBAL:-}" ]]; then
      sources=( "$GIT_USER_FILE" )
    else
      sources=( "$config_dir/config" "$HOME/.gitconfig" )
    fi
    managed_seen=0
    managed_include_count=0
    unsupported=()
    for source in "${sources[@]}"; do
      [[ -r "$source" ]] || continue
      rc=0
      git -C "$temp" config --file "$source" --includes --show-origin -z \
        --get-regexp '^(include\.path|include[Ii]f\..*\.path|credential\.helper|credential\..*\.helper)$' \
        >"$temp/settings" || rc=$?
      [[ "$rc" -le 1 ]] || exit "$rc"
      while IFS= read -r -d '' origin && IFS= read -r -d '' entry; do
        key=${entry%%$'\n'*}
        value=${entry#*$'\n'}
        if [[ "$key" = include.path ]]; then
          if is_managed_include "$value" "${origin#file:}"; then
            managed_seen=1
            managed_include_count=$((managed_include_count + 1))
          fi
          continue
        fi
        [[ "$managed_seen" = 0 ]] || continue
        if [[ "$key" = includeif.*.path ]]; then
          unsupported+=( "conditional include before managed credentials: ${origin#file:}" )
        else
          unsupported+=( "credential helper before managed credentials: $key (${origin#file:})" )
        fi
      done <"$temp/settings"
    done
    if [[ "$managed_include_count" -gt 1 ]]; then
      unsupported+=( "managed credentials included $managed_include_count times" )
    fi
    if [[ -z "${GIT_CONFIG_GLOBAL:-}" && "$managed_include_count" = 0 ]]; then
      unsupported+=( "tracked Git config does not include $managed" )
    fi
    if [[ ${#unsupported[@]} -gt 0 ]]; then
      for item in "${unsupported[@]}"; do log -e "$item"; done
      log -e 'place one managed include before custom credential settings'
      exit 1
    fi
    printf '%s\n' "$marker" >"$temp/config"
    git config --file "$temp/config" --add credential.helper ''
    for helper in "${defaults[@]}"; do
      git config --file "$temp/config" --add credential.helper "$helper"
    done
    if [[ -n "$gh_path" ]]; then
      for host in github.com gist.github.com; do
        git config --file "$temp/config" --add "credential.https://$host.helper" ''
        git config --file "$temp/config" --add "credential.https://$host.helper" "$gh_helper"
        for helper in "${defaults[@]}"; do
          git config --file "$temp/config" --add "credential.https://$host.helper" "$helper"
        done
      done
    fi
    chmod 600 "$temp/config"
    mv "$temp/config" "$managed"
    if [[ -n "${GIT_CONFIG_GLOBAL:-}" && "$managed_include_count" = 0 ]]; then
      git config --file "$GIT_USER_FILE" --add include.path "$managed"
    fi
    ;;
esac
