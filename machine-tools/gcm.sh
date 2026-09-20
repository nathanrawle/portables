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
      Darwin) defaults=( manager osxkeychain ) ;;
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
    host_helper_context() {
      local key="$1" host="$2" context remainder authority user_scoped=0 base matched
      context=${key#credential.}
      context=${context%.helper}
      [[ "$context" = *://* ]] || return 1
      remainder=${context#*://}
      authority=${remainder%%/*}
      if [[ "$authority" = *@* ]]; then
        user_scoped=1
        authority=${authority##*@}
      fi
      base="${context%%://*}://$authority"
      : >"$temp/urlmatch"
      git config --file "$temp/urlmatch" "credential.$base.helper" portables-match \
        2>/dev/null || return 1
      matched="$(git config --file "$temp/urlmatch" --get-urlmatch credential.helper \
        "https://$host" 2>/dev/null || true)"
      [[ "$matched" = portables-match ]] || return 1
      if [[ "$user_scoped" = 1 ]]; then
        printf 'scoped\n'
        return
      fi
      case "$remainder" in
        */?*) printf 'scoped\n' ;;
        *) printf 'base\n' ;;
      esac
    }
    custom=0
    custom_helpers=()
    conditional_before_managed=0
    if [[ -n "${GIT_CONFIG_GLOBAL:-}" ]]; then
      sources=( "$GIT_USER_FILE" )
    else
      sources=( "$config_dir/config" "$HOME/.gitconfig" )
    fi
    managed_seen=0
    for source in "${sources[@]}"; do
      [[ -r "$source" ]] || continue
      rc=0
      git -C "$temp" config --file "$source" --includes --show-origin -z \
        --get-regexp '^(include\.path|include[Ii]f\..*\.path|credential\.helper)$' \
        >"$temp/helpers" || rc=$?
      [[ "$rc" -le 1 ]] || exit "$rc"
      while IFS= read -r -d '' origin && IFS= read -r -d '' entry; do
        key=${entry%%$'\n'*}
        helper=${entry#*$'\n'}
        if [[ "$key" = include.path ]]; then
          if is_managed_include "$helper" "${origin#file:}"; then
            managed_seen=1
          fi
          continue
        fi
        if [[ "$key" = includeif.*.path ]]; then
          [[ "$managed_seen" = 1 ]] || conditional_before_managed=1
          continue
        fi
        if [[ "$migrate_helpers" = 1 && "${origin#file:}" -ef "$GIT_USER_FILE" ]]; then
          continue
        fi
        if [[ "$origin" = "file:$managed" || "${origin#file:}" -ef "$managed" ]]; then
          continue
        fi
        custom=1
        [[ "$managed_seen" = 0 ]] || continue
        if [[ -z "$helper" ]]; then
          custom_helpers=()
          continue
        fi
        found=0
        for existing in "${custom_helpers[@]}"; do [[ "$existing" != "$helper" ]] || found=1; done
        [[ "$found" = 1 ]] || custom_helpers+=( "$helper" )
      done <"$temp/helpers"
    done
    printf '%s\n' "$marker" >"$temp/config"
    if [[ "$custom" = 0 ]]; then
      case "$OS" in
        Darwin) require_commands git-credential-manager ;;
        Linux) require_commands git-credential-oauth ;;
      esac
      fallbacks=( "${defaults[@]}" )
    else
      log -i "preserving custom credential helpers"
      fallbacks=( "${custom_helpers[@]}" )
    fi
    if [[ -n "$gh_path" ]]; then
      if [[ -n "${GIT_CONFIG_GLOBAL:-}" ]]; then
        host_sources=( "$GIT_USER_FILE" )
      else
        host_sources=( "$config_dir/config" )
      fi
      for host in github.com gist.github.com; do
        preserved_helpers=()
        scoped_keys=()
        scoped_helpers=()
        migrating=0
        for migrated_host in "${migrate_gh_hosts[@]}"; do
          [[ "$migrated_host" != "$host" ]] || migrating=1
        done
        for source in "${host_sources[@]}"; do
          [[ -r "$source" ]] || continue
          rc=0
          git -C "$temp" config --file "$source" --includes --show-origin -z \
            --get-regexp '^(include\.path|include[Ii]f\..*\.path|credential\..*\.helper)$' \
            >"$temp/host-helpers" || rc=$?
          [[ "$rc" -le 1 ]] || exit "$rc"
          managed_seen=0
          while IFS= read -r -d '' origin && IFS= read -r -d '' entry; do
            key=${entry%%$'\n'*}
            helper=${entry#*$'\n'}
            if [[ "$key" = include.path ]]; then
              if is_managed_include "$helper" "${origin#file:}"; then
                managed_seen=1
              fi
              continue
            fi
            if [[ "$key" = includeif.*.path ]]; then
              [[ "$managed_seen" = 1 ]] || conditional_before_managed=1
              continue
            fi
            [[ "$managed_seen" = 0 ]] || continue
            relation="$(host_helper_context "$key" "$host" || true)"
            [[ -n "$relation" ]] || continue
            if [[ "$migrating" = 1 && "${origin#file:}" -ef "$GIT_USER_FILE" &&
              "$key" = "credential.https://$host.helper" ]]; then
              continue
            fi
            if [[ "$relation" = scoped ]]; then
              if [[ -z "$helper" ]]; then
                for index in "${!scoped_keys[@]}"; do
                  if [[ "${scoped_keys[index]}" = "$key" ]]; then
                    unset 'scoped_keys[index]' 'scoped_helpers[index]'
                  fi
                done
                scoped_keys+=( "$key" )
                scoped_helpers+=( '' )
                continue
              fi
              found=0
              for index in "${!scoped_keys[@]}"; do
                if [[ "${scoped_keys[index]}" = "$key" &&
                  "${scoped_helpers[index]}" = "$helper" ]]; then found=1; fi
              done
              if [[ "$found" = 0 ]]; then
                scoped_keys+=( "$key" )
                scoped_helpers+=( "$helper" )
              fi
              continue
            fi
            if [[ -z "$helper" ]]; then
              preserved_helpers=()
              continue
            fi
            [[ "$helper" != "!$gh_path auth git-credential" && "$helper" != "$gh_helper" ]] || continue
            found=0
            for existing in "${preserved_helpers[@]}"; do
              [[ "$existing" != "$helper" ]] || found=1
            done
            [[ "$found" = 1 ]] || preserved_helpers+=( "$helper" )
          done <"$temp/host-helpers"
        done
        if [[ "$conditional_before_managed" = 1 ]]; then
          git config --file "$temp/config" --add "credential.https://$host.helper" "$gh_helper"
          continue
        fi
        git config --file "$temp/config" --add "credential.https://$host.helper" ''
        git config --file "$temp/config" --add "credential.https://$host.helper" "$gh_helper"
        emitted_helpers=( "$gh_helper" )
        for helper in "${preserved_helpers[@]}"; do
          git config --file "$temp/config" --add "credential.https://$host.helper" "$helper"
          emitted_helpers+=( "$helper" )
        done
        if [[ "$custom" = 1 ]]; then
          for helper in "${fallbacks[@]}"; do
            found=0
            for existing in "${emitted_helpers[@]}"; do
              [[ "$existing" != "$helper" ]] || found=1
            done
            [[ "$found" = 0 ]] || continue
            git config --file "$temp/config" --add "credential.https://$host.helper" "$helper"
            emitted_helpers+=( "$helper" )
          done
        fi
        reset_scopes=()
        for index in "${!scoped_keys[@]}"; do
          key=${scoped_keys[index]}
          helper=${scoped_helpers[index]}
          if [[ -z "$helper" ]]; then
            git config --file "$temp/config" --add "$key" ''
            reset_scopes+=( "$key" )
            continue
          fi
          reset_seen=0
          for existing in "${reset_scopes[@]}"; do [[ "$existing" != "$key" ]] || reset_seen=1; done
          if [[ "$reset_seen" = 1 ]]; then
            git config --file "$temp/config" --add "$key" "$helper"
            continue
          fi
          found=0
          for existing in "${emitted_helpers[@]}"; do [[ "$existing" != "$helper" ]] || found=1; done
          [[ "$found" = 0 ]] || continue
          git config --file "$temp/config" --add "$key" "$helper"
        done
      done
    fi
    if [[ "$custom" = 0 ]]; then
      for helper in "${defaults[@]}"; do
        git config --file "$temp/config" --add credential.helper "$helper"
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
