#!/usr/bin/env bash

assert_file_contains() {
  local path="$1"
  local expected="$2"

  [[ -f "$path" ]] || fail "expected file: $path"
  grep -F -- "$expected" "$path" >/dev/null ||
    fail "expected $path to contain: $expected"
}

assert_file_not_contains() {
  local path="$1"
  local unexpected="$2"

  [[ -f "$path" ]] || fail "expected file: $path"
  if grep -F -- "$unexpected" "$path" >/dev/null; then
    fail "expected $path not to contain: $unexpected"
  fi
}

assert_string_not_contains() {
  local value="$1"
  local unexpected="$2"

  case "$value" in
    *"$unexpected"*) fail "expected string not to contain: $unexpected" ;;
    *) ;;
  esac
}

assert_string_contains() {
  local value="$1"
  local expected="$2"

  case "$value" in
    *"$expected"*) ;;
    *) fail "expected string to contain: $expected" ;;
  esac
}

assert_no_tmux_work_window() {
  local path="$1"

  [[ -f "$path" ]] || return 0
  assert_file_not_contains "$path" $'new-session\t'
  assert_file_not_contains "$path" $'new-window\t'
  assert_file_not_contains "$path" $'link-window\t'
  assert_file_not_contains "$path" $'attach-session\t'
  assert_file_not_contains "$path" $'switch-client\t'
}

make_fake_tmux() {
  local root="$1"
  local bin="$root/bin"

  mkdir -p "$bin"
  cat >"$bin/tmux" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

: "${TAW_TMUX_LOG:?}"

{
  first=1
  for arg in "$@"; do
    if [[ $first -eq 1 ]]; then
      printf '%s' "$arg"
      first=0
    else
      printf '\t%s' "$arg"
    fi
  done
  printf '\n'
} >>"$TAW_TMUX_LOG"

target_is_listed() {
  local target="$1" candidates="$2" candidate

  while IFS= read -r candidate || [[ -n "$candidate" ]]; do
    [[ -n "$candidate" && "$candidate" = "$target" ]] && return 0
  done <<<"$candidates"
  return 1
}

case "${1:-}" in
  has-session)
    target=""
    shift
    while [[ $# -gt 0 ]]; do
      if [[ "$1" = "-t" && $# -ge 2 ]]; then
        target="$2"
        break
      fi
      shift
    done
    if [[ -n "${TAW_FAKE_TMUX_HAS_SESSION_TARGETS+x}" ]]; then
      while IFS= read -r candidate || [[ -n "$candidate" ]]; do
        [[ -n "$candidate" ]] || continue
        if [[ "$target" = "$candidate" ]]; then
          exit 0
        fi
      done <<<"$TAW_FAKE_TMUX_HAS_SESSION_TARGETS"
      exit 1
    fi
    if [[ "${TAW_FAKE_TMUX_HAS_SESSION:-0}" = 1 ]]; then
      exit 0
    fi
    exit 1
    ;;
  list-panes)
    panes="${TAW_FAKE_TMUX_PANES-}"
    if [[ " $* " = *" -a "* ]]; then
      panes="${TAW_FAKE_TMUX_ALL_PANES-}"
    fi
    [[ -n "$panes" ]] || exit 1
    printf '%b' "$panes"
    [[ "$panes" = *$'\n' ]] || printf '\n'
    ;;
  list-windows)
    windows="${TAW_FAKE_TMUX_CURRENT_SESSION_WINDOWS-}"
    [[ -n "$windows" ]] || exit 1
    printf '%b' "$windows"
    [[ "$windows" = *$'\n' ]] || printf '\n'
    ;;
  list-sessions)
    if [[ -n "${TAW_FAKE_TMUX_WAIT_FOR_FILE:-}" ]]; then
      for ((attempt = 0; attempt < 200; attempt++)); do
        [[ -f "$TAW_FAKE_TMUX_WAIT_FOR_FILE" ]] && break
        sleep 0.01
      done
      [[ -f "$TAW_FAKE_TMUX_WAIT_FOR_FILE" ]] || exit 98
    fi
    [[ -n "${TAW_FAKE_TMUX_SESSIONS+x}" ]] || exit 1
    sessions="$TAW_FAKE_TMUX_SESSIONS"
    if [[ -n "${TAW_FAKE_TMUX_SESSIONS_AFTER_FIRST+x}" ]]; then
      count_file="${TAW_FAKE_TMUX_LIST_SESSIONS_COUNT_FILE:-$TAW_TMUX_LOG.sessions.count}"
      count=0
      if [[ -f "$count_file" ]]; then
        count="$(<"$count_file")"
      fi
      count=$((count + 1))
      printf '%s\n' "$count" >"$count_file"
      if (( count > 1 )); then
        sessions="$TAW_FAKE_TMUX_SESSIONS_AFTER_FIRST"
      fi
    fi
    format=""
    filter=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        -F)
          format="$2"
          shift 2
          ;;
        -f)
          filter="$2"
          shift 2
          ;;
        *) shift ;;
      esac
    done
    if [[ -n "$format" ]]; then
      line_number=0
      while IFS= read -r line || [[ -n "$line" ]]; do
        line_number=$((line_number + 1))
        [[ -n "$line" ]] || continue
        IFS=$'\t' read -r first second third _ <<<"$line"
        if [[ ( "$first" = @* || "$first" = \$* ) && -n "$third" ]]; then
          session_id="$first"
          session="$second"
          path="$third"
        else
          session_id="\$${line_number}"
          session="$first"
          path="$second"
        fi
        if [[ -n "$filter" \
          && "$session_id" = "${TAW_FAKE_TMUX_CURRENT_SESSION_ID:-\$1}" ]]; then
          continue
        fi
        case "$format" in
          '#{session_id}')
            printf '%s\n' "$session_id"
            ;;
          "[TMUX] #{session_name}")
            printf '[TMUX] %s\n' "$session"
            ;;
          $'#{session_id}\t#{session_name}\t#{session_path}')
            printf '%s\t%s\t%s\n' "$session_id" "$session" "$path"
            ;;
          $'#{session_id}\t#{session_name}\t#{session_path}__taw_picker_end__')
            if [[ ( "$first" = @* || "$first" = \$* ) && -n "$third" ]]; then
              printf '%s__taw_picker_end__\n' "$line"
            else
              printf '%s\t%s__taw_picker_end__\n' "$session_id" "$line"
            fi
            ;;
          $'#{session_name}\t#{session_path}')
            printf '%s\t%s\n' "$session" "$path"
            ;;
          *)
            printf '%s\n' "$line"
            ;;
        esac
      done <<<"$sessions"
    else
      printf '%b' "$sessions"
      [[ "$sessions" = *$'\n' ]] || printf '\n'
    fi
    ;;
  new-session)
    session_name=""
    format=""
    shift
    while [[ $# -gt 0 ]]; do
      case "$1" in
        -s)
          session_name="$2"
          shift 2
          ;;
        -F)
          format="$2"
          shift 2
          ;;
        *) shift ;;
      esac
    done
    session_name="${session_name//[.:]/_}"
    if [[ "$format" = *'#{session_id}'* ]]; then
      printf '$1\t%s\t@1\t%%1\n' "$session_name"
    else
      printf '@1 %%1\n'
    fi
    ;;
  new-window)
    printf '@1 %%1\n'
    ;;
  split-window)
    count_file="${TAW_TMUX_COUNT_FILE:-$TAW_TMUX_LOG.count}"
    count=1
    if [[ -f "$count_file" ]]; then
      count="$(<"$count_file")"
    fi
    count=$((count + 1))
    printf '%s\n' "$count" >"$count_file"
    printf '%%%d\n' "$count"
    ;;
  display-message)
    target=""
    args=( "$@" )
    for ((i = 0; i < ${#args[@]}; i++)); do
      if [[ "${args[$i]}" = -t && $((i + 1)) -lt ${#args[@]} ]]; then
        target="${args[$((i + 1))]}"
      fi
    done
    if [[ "$*" = *'#{window_id}'* ]]; then
      printf '%s\n' "${TAW_FAKE_TMUX_CURRENT_WINDOW_ID:-@1}"
    elif [[ "$*" = *'#{session_name}'* ]]; then
      target_is_listed "$target" "${TAW_FAKE_TMUX_DISPLAY_FAIL_SESSION_NAME_TARGETS-}" \
        && exit 1
      if [[ -n "${TAW_FAKE_TMUX_DISPLAY_SESSION_NAME+x}" ]]; then
        value="$TAW_FAKE_TMUX_DISPLAY_SESSION_NAME"
      else
        value=""
        line_number=0
        while IFS= read -r line || [[ -n "$line" ]]; do
          line_number=$((line_number + 1))
          [[ -n "$line" ]] || continue
          IFS=$'\t' read -r first second third _ <<<"$line"
          if [[ ( "$first" = @* || "$first" = \$* ) && -n "$third" ]]; then
            session_id="$first"
            session_name="$second"
          else
            session_id="\$${line_number}"
            session_name="$first"
          fi
          [[ "$session_id" = "$target" ]] || continue
          value="$session_name"
          break
        done <<<"${TAW_FAKE_TMUX_SESSIONS-}"
      fi
      printf '%s__taw_picker_end__\n' "$value"
    elif [[ "$*" = *'#{session_path}'* ]]; then
      target_is_listed "$target" "${TAW_FAKE_TMUX_DISPLAY_FAIL_SESSION_PATH_TARGETS-}" \
        && exit 1
      if [[ -n "${TAW_FAKE_TMUX_DISPLAY_SESSION_PATH+x}" ]]; then
        value="$TAW_FAKE_TMUX_DISPLAY_SESSION_PATH"
      else
        value=""
        line_number=0
        while IFS= read -r line || [[ -n "$line" ]]; do
          line_number=$((line_number + 1))
          [[ -n "$line" ]] || continue
          IFS=$'\t' read -r first second third _ <<<"$line"
          if [[ ( "$first" = @* || "$first" = \$* ) && -n "$third" ]]; then
            session_id="$first"
            session_path="$third"
          else
            session_id="\$${line_number}"
            session_path="$second"
          fi
          [[ "$session_id" = "$target" ]] || continue
          value="$session_path"
          break
        done <<<"${TAW_FAKE_TMUX_SESSIONS-}"
      fi
      printf '%s__taw_picker_end__\n' "$value"
    elif [[ "$*" = *'#{session_id}'* ]]; then
      printf '%s\n' "${TAW_FAKE_TMUX_CURRENT_SESSION_ID:-\$1}"
    elif [[ "$*" = *'#S'* ]]; then
      printf '%s\n' "${TAW_FAKE_TMUX_CURRENT_SESSION_NAME:-current}"
    fi
    ;;
esac
EOF
  chmod +x "$bin/tmux"
  printf '%s\n' "$bin"
}

make_git_repo() {
  local repo="$1"
  local primary_branch="${2:-main}"

  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" config user.email "taw@example.invalid"
  git -C "$repo" config user.name "taw test"
  printf '%s\n' "$primary_branch" >"$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" commit -qm "initial commit"
  git -C "$repo" branch -M "$primary_branch"
  git -C "$repo" checkout -qb develop
  printf 'develop\n' >"$repo/develop.txt"
  git -C "$repo" add develop.txt
  git -C "$repo" commit -qm "develop commit"
  git -C "$repo" checkout -q "$primary_branch"
}

make_bare_wrapper() {
  local root="$1"
  local bare_name="${2:-.git}"
  local primary_branch="${3:-main}"
  local src="$root/src"
  local project="$root/project"

  make_git_repo "$src" "$primary_branch"
  mkdir -p "$project"
  git clone --bare "$src" "$project/$bare_name" >/dev/null 2>&1
  printf '%s\n' "$project"
}

make_conventional_bare_clone() {
  local root="$1"
  local name="${2:-project}"
  local primary_branch="${3:-main}"
  local src="$root/src"
  local bare="$root/$name.git"

  make_git_repo "$src" "$primary_branch"
  git clone --bare "$src" "$bare" >/dev/null 2>&1
  printf '%s\n' "$bare"
}
