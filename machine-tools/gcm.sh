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
    is_managed_include() {
      local included="$1" including_file="$2" candidate candidate_dir managed_dir
      case "$included" in
        "~/"*) candidate="$HOME/${included#\~/}" ;;
        /*) candidate="$included" ;;
        *) candidate="$(dirname -- "$including_file")/$included" ;;
      esac
      if [[ -e "$candidate" && "$candidate" -ef "$managed" ]]; then return 0; fi
      candidate_dir="$(cd -- "$(dirname -- "$candidate")" 2>/dev/null && pwd -P)" || return 1
      managed_dir="$(cd -- "$(dirname -- "$managed")" && pwd -P)" || return 1
      [[ "$candidate_dir/${candidate##*/}" = "$managed_dir/${managed##*/}" ]]
    }
    user_git_file
    migrate_helpers=0
    migrate_excludes=0
    migrate_includes=()
    deduplicate_includes=0
    migrate_gh_hosts=()
    gh_path="$(type -P gh || true)"
    if [[ -n "$gh_path" && "$gh_path" != /* ]]; then
      gh_path="$(cd -- "$(dirname -- "$gh_path")" && pwd -P)/${gh_path##*/}"
    fi
    gh_helper=
    if [[ -n "$gh_path" ]]; then
      quoted_gh_path=${gh_path//\'/\'\\\'\'}
      gh_helper="!'$quoted_gh_path' auth git-credential"
    fi
    if [[ -f "$GIT_USER_FILE" ]]; then
      legacy="$(git config --file "$GIT_USER_FILE" --get-all credential.helper || true)"
      if { [[ "$OS" = Darwin ]] && [[ "$legacy" = manager ]]; } ||
        [[ "$legacy" = $'manager\noauth' ]]; then
        migrate_helpers=1
      fi
      legacy_excludes="$(git config --file "$GIT_USER_FILE" --get-all core.excludesFile || true)"
      if [[ "$legacy_excludes" = "$HOME/.gitignore"$'\n'"$config_dir/ignore" ]]; then
        migrate_excludes=1
      fi
      if includes="$(git config --file "$GIT_USER_FILE" --get-all include.path 2>/dev/null || true)"; then
        managed_include_count=0
        managed_include_values=()
        while IFS= read -r included; do
          if is_managed_include "$included" "$GIT_USER_FILE"; then
            managed_include_count=$((managed_include_count + 1))
            found=0
            for existing in "${managed_include_values[@]}"; do
              [[ "$existing" != "$included" ]] || found=1
            done
            [[ "$found" = 1 ]] || managed_include_values+=( "$included" )
          fi
        done <<<"$includes"
        if [[ -z "${GIT_CONFIG_GLOBAL:-}" ]]; then
          migrate_includes=( "${managed_include_values[@]}" )
        elif [[ "$managed_include_count" -gt 1 ]]; then
          migrate_includes=( "${managed_include_values[@]}" )
          deduplicate_includes=1
        fi
      fi
      if [[ -n "$gh_path" ]]; then
        for host in github.com gist.github.com; do
          legacy_host="$(git config --file "$GIT_USER_FILE" \
            --get-all "credential.https://$host.helper" || true)"
          if [[ "$legacy_host" = $'\n'"!$gh_path auth git-credential" ||
            "$legacy_host" = $'\n'"$gh_helper" ]]; then
            migrate_gh_hosts+=( "$host" )
          fi
        done
      fi
    fi
    temp="$(mktemp -d "$config_dir/.portables-credentials.XXXXXX")"
    trap 'rm -rf -- "$temp"' EXIT
    if [[ -n "${GIT_CONFIG_GLOBAL:-}" ]]; then
      sources=( "$GIT_USER_FILE" )
    else
      sources=( "$config_dir/config" "$HOME/.gitconfig" )
    fi
    managed_seen=0
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
          fi
          continue
        fi
        [[ "$managed_seen" = 0 ]] || continue
        if [[ "$key" = includeif.*.path ]]; then
          unsupported+=( "conditional include before managed credentials: ${origin#file:}" )
          continue
        fi
        if [[ "$origin" = "file:$managed" || "${origin#file:}" -ef "$managed" ]]; then
          continue
        fi
        if [[ "$migrate_helpers" = 1 && "$key" = credential.helper &&
          "${origin#file:}" -ef "$GIT_USER_FILE" ]]; then
          continue
        fi
        allowed=0
        for host in "${migrate_gh_hosts[@]}"; do
          if [[ "$key" = "credential.https://$host.helper" &&
            "${origin#file:}" -ef "$GIT_USER_FILE" ]]; then
            allowed=1
          fi
        done
        [[ "$allowed" = 0 ]] || continue
        unsupported+=( "credential helper before managed credentials: $key (${origin#file:})" )
      done <"$temp/settings"
    done
    if [[ ${#unsupported[@]} -gt 0 ]]; then
      for item in "${unsupported[@]}"; do log -e "$item"; done
      log -e 'move custom credential settings after the managed include'
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
    backup=
    if [[ "$migrate_helpers" = 1 || "$migrate_excludes" = 1 || ${#migrate_includes[@]} -gt 0 ||
      ${#migrate_gh_hosts[@]} -gt 0 ]]; then
      backup="$(mktemp "$GIT_USER_FILE.bak.XXXXXX")"
      cp -p "$GIT_USER_FILE" "$backup"
    fi
    if [[ "$migrate_helpers" = 1 ]]; then
      git config --file "$GIT_USER_FILE" --unset-all credential.helper
    fi
    if [[ "$migrate_excludes" = 1 ]]; then
      git config --file "$GIT_USER_FILE" --unset-all core.excludesFile
    fi
    if [[ "$deduplicate_includes" = 1 ]]; then
      for included in "${migrate_includes[@]}"; do
        git config --file "$GIT_USER_FILE" --replace-all --fixed-value \
          include.path "$managed" "$included"
      done
      git config --file "$GIT_USER_FILE" --replace-all --fixed-value \
        include.path "$managed" "$managed"
    else
      for included in "${migrate_includes[@]}"; do
        git config --file "$GIT_USER_FILE" --unset-all --fixed-value include.path "$included"
      done
    fi
    for host in "${migrate_gh_hosts[@]}"; do
      git config --file "$GIT_USER_FILE" --unset-all "credential.https://$host.helper"
    done
    [[ -z "$backup" ]] || log -i "legacy Git settings backed up to $backup"
    if [[ -n "${GIT_CONFIG_GLOBAL:-}" ]]; then
      includes="$(git config --file "$GIT_USER_FILE" --get-all include.path 2>/dev/null || true)"
      found=0
      while IFS= read -r included; do
        is_managed_include "$included" "$GIT_USER_FILE" && found=1
      done <<<"$includes"
      [[ "$found" = 1 ]] || git config --file "$GIT_USER_FILE" --add include.path "$managed"
    fi
    ;;
esac
