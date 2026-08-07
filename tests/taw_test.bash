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

make_real_tmux_wrapper() {
  local root="$1"
  local bin="$root/bin"

  mkdir -p "$bin"
  cat >"$bin/tmux" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

: "${TAW_REAL_TMUX_BIN:?}"
: "${TAW_REAL_TMUX_SOCKET:?}"
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

case "${1:-}" in
  attach-session|switch-client) exit 0 ;;
esac

exec "$TAW_REAL_TMUX_BIN" -L "$TAW_REAL_TMUX_SOCKET" -f /dev/null "$@"
EOF
  chmod +x "$bin/tmux"
  printf '%s\n' "$bin"
}

cleanup_real_tmux() {
  "$REAL_TMUX_BIN_FOR_CLEANUP" -L "$REAL_TMUX_SOCKET_FOR_CLEANUP" \
    kill-server >/dev/null 2>&1 || true
}

real_tmux_session_id() {
  local tmux_bin="$1"
  local socket="$2"
  local expected_name="$3"
  local session_id session_name

  while IFS=$'\t' read -r session_id session_name; do
    if [[ "$session_name" = "$expected_name" ]]; then
      printf '%s\n' "$session_id"
      return 0
    fi
  done < <("$tmux_bin" -L "$socket" list-sessions -F $'#{session_id}\t#{session_name}')

  return 1
}

make_fake_fzf() {
  local bin="$1"

  cat >"$bin/fzf" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" = --version ]]; then
  if [[ -n "${TAW_FZF_VERSION_LOG:-}" ]]; then
    printf '%s\n' version >>"$TAW_FZF_VERSION_LOG"
  fi
  printf '%s\n' "${TAW_FAKE_FZF_VERSION:-0.74.2}"
  exit "${TAW_FAKE_FZF_VERSION_STATUS:-0}"
fi

print_query=0
expects_key=0
initial_query=""
args=( "$@" )
for ((i = 0; i < ${#args[@]}; i++)); do
  case "${args[$i]}" in
    --print-query)
      print_query=1
      ;;
    --expect=*)
      expects_key=1
      ;;
    --query=*)
      initial_query="${args[$i]#*=}"
      ;;
    --query)
      if (( i + 1 < ${#args[@]} )); then
        initial_query="${args[$((i + 1))]}"
      fi
      ;;
  esac
done

if [[ -n "${TAW_FZF_ARGS_LOG:-}" ]]; then
  printf '%s\t' "${args[@]}" >>"$TAW_FZF_ARGS_LOG"
  printf '\n' >>"$TAW_FZF_ARGS_LOG"
fi

if [[ -n "${TAW_FAKE_FZF_STARTED_FILE:-}" ]]; then
  : >"$TAW_FAKE_FZF_STARTED_FILE"
fi
if [[ -n "${TAW_FAKE_FZF_WAIT_FOR_FILE:-}" ]]; then
  for ((attempt = 0; attempt < 200; attempt++)); do
    [[ -f "$TAW_FAKE_FZF_WAIT_FOR_FILE" ]] && break
    sleep 0.01
  done
  [[ -f "$TAW_FAKE_FZF_WAIT_FOR_FILE" ]] || exit 98
fi

lines=()
if [[ "${TAW_FAKE_FZF_CLOSE_EARLY:-0}" = 1 ]]; then
  IFS= read -r line && lines+=( "$line" )
  exec 0<&-
else
  while IFS= read -r line; do
    lines+=( "$line" )
  done
fi

count_file="${TAW_FAKE_FZF_COUNT_FILE:-${TAW_TMUX_LOG:-/tmp/fzf}.fzf.count}"
count=1
if [[ -f "$count_file" ]]; then
  count="$(<"$count_file")"
fi
count=$((count + 1))
printf '%s\n' "$count" >"$count_file"
call_number=$((count - 1))

key=""
if [[ -n "${TAW_FAKE_FZF_KEYS:-}" ]]; then
  mapfile -t configured_keys <<<"$TAW_FAKE_FZF_KEYS"
  if (( call_number <= ${#configured_keys[@]} )); then
    key="${configured_keys[$((call_number - 1))]}"
  fi
fi
[[ "$key" = none ]] && key=""

output_query="$initial_query"
if [[ -n "${TAW_FAKE_FZF_OUTPUT_QUERIES:-}" ]]; then
  mapfile -t configured_queries <<<"$TAW_FAKE_FZF_OUTPUT_QUERIES"
  if (( call_number <= ${#configured_queries[@]} )); then
    output_query="${configured_queries[$((call_number - 1))]}"
  fi
fi

if [[ "${TAW_FAKE_FZF_FAIL_ON_SECOND:-0}" = 1 && "$count" -gt 2 ]]; then
  exit 91
fi

if [[ -n "${TAW_FZF_INPUT_LOG:-}" ]]; then
  printf '%s\n' "${lines[@]}" >>"$TAW_FZF_INPUT_LOG"
fi

if [[ -n "${TAW_FAKE_FZF_STATUS:-}" ]]; then
  exit "$TAW_FAKE_FZF_STATUS"
fi

if [[ "${TAW_FAKE_FZF_CANCEL:-0}" = 1 ]]; then
  exit 130
fi
if [[ "$key" = cancel ]]; then
  exit 130
fi

if [[ ${#lines[@]} -eq 0 ]]; then
  exit 1
fi

if (( print_query )); then
  printf '%s\n' "$output_query"
fi
if (( expects_key )); then
  printf '%s\n' "$key"
fi
if [[ "$key" = tab ]]; then
  exit 0
fi

if [[ -n "${TAW_FAKE_FZF_MATCH:-}" ]]; then
  for line in "${lines[@]}"; do
    if [[ "$line" == *"$TAW_FAKE_FZF_MATCH"* ]]; then
      printf '%s\n' "$line"
      exit 0
    fi
  done
  if [[ "${TAW_FAKE_FZF_MATCH_FALLBACK_OK:-0}" = 1 ]]; then
    exit 2
  fi
  exit 1
fi

index="${TAW_FAKE_FZF_INDEX:-1}"
if [[ "$index" =~ ^[0-9]+$ ]] && (( index >= 1 && index <= ${#lines[@]} )); then
  printf '%s\n' "${lines[$((index - 1))]}"
  exit 0
fi

exit 1
EOF
  chmod +x "$bin/fzf"
}

make_path_without_fzf() {
  local bin="$1"

  ln -sf "$(command -v bash)" "$bin/bash"
  ln -sf "$(command -v cat)" "$bin/cat"
  ln -sf "$(command -v git)" "$bin/git"
  ln -sf "$(command -v find)" "$bin/find"
  ln -sf "$(command -v mkdir)" "$bin/mkdir"
  ln -sf "$(command -v mktemp)" "$bin/mktemp"
  ln -sf "$(command -v mv)" "$bin/mv"
  ln -sf "$(command -v rm)" "$bin/rm"
  ln -sf "$(command -v rmdir)" "$bin/rmdir"
  ln -sf "$(command -v sleep)" "$bin/sleep"
  ln -sf "$(command -v zsh)" "$bin/zsh"
  printf '%s\n' "$bin"
}

make_fake_git_url_clone() {
  local bin="$1"
  local real_git

  real_git="$(command -v git)"
  rm -f "$bin/git"
  cat >"$bin/git" <<EOF
#!/usr/bin/env bash
set -euo pipefail

real_git="$real_git"

if [[ "\${1:-}" = clone && -n "\${TAW_FAKE_GIT_CLONE_SOURCE:-}" ]]; then
  if [[ "\${2:-}" = --bare && "\${3:-}" = "\${TAW_FAKE_GIT_CLONE_URL:-}" ]]; then
    if [[ "\${TAW_FAKE_GIT_CLONE_FAIL:-0}" = 1 ]]; then
      exit 1
    fi
    exec "\$real_git" clone --bare "\$TAW_FAKE_GIT_CLONE_SOURCE" "\${4:-}"
  elif [[ "\${2:-}" = "\${TAW_FAKE_GIT_CLONE_URL:-}" ]]; then
    if [[ "\${TAW_FAKE_GIT_CLONE_FAIL:-0}" = 1 ]]; then
      exit 1
    fi
    exec "\$real_git" clone "\$TAW_FAKE_GIT_CLONE_SOURCE" "\${3:-}"
  fi
fi

exec "\$real_git" "\$@"
EOF
  chmod +x "$bin/git"
}

make_logging_git() {
  local bin="$1"
  local real_git

  real_git="$(command -v git)"
  export TAW_REAL_GIT="$real_git"
  rm -f "$bin/git"
  cat >"$bin/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

: "${TAW_GIT_LOG:?}"
: "${TAW_REAL_GIT:?}"

if [[ -n "${TAW_GIT_MARKER:-}" && " $* " = *" worktree list --porcelain -z "* ]]; then
  : >"$TAW_GIT_MARKER"
fi

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
} >>"$TAW_GIT_LOG"

exec "$TAW_REAL_GIT" "$@"
EOF
  chmod +x "$bin/git"
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

run_taw() {
  local cwd="$1"
  local taw_path
  shift
  taw_path="${TAW_RUN_PATH:-${TAW_FAKE_TMUX_BIN:+$TAW_FAKE_TMUX_BIN:}$PATH}"

  (
    cd "$cwd" || exit 1
    TAW_FUNC_DIR="$REPO_ROOT/home/.zfuns" \
      PATH="$taw_path" \
      TMUX="${TAW_TEST_TMUX:-}" \
      zsh -fc 'fpath=("$TAW_FUNC_DIR" $fpath); autoload -U taw; taw "$@"' taw "$@"
  )
}

test_layout_with_overrides_and_shell_panes() {
  local repo repo_real fake_bin log no_fzf_path

  repo="$TEST_TMPDIR/repo"
  make_git_repo "$repo"
  repo_real="$(cd "$repo" && pwd -P)"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  no_fzf_path="$(make_path_without_fzf "$fake_bin")"
  log="$TEST_TMPDIR/tmux.log"

  TAW_AGENT='env-agent' TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" \
    run_taw "$repo" -p "$repo" -agent "claude --resume" -ed "nvim ." -sh -sh "npm test"

  assert_file_contains "$log" $'list-sessions\t-F\t#{session_id}\t#{session_name}\t#{session_path}'
  assert_file_contains "$log" $'new-session\t-d\t-P\t-F\t#{session_id}\t#{session_name}\t#{window_id}\t#{pane_id}\t-s\trepo\t-n\trepo\t-c\t'"$repo_real"$'\tnvim .'
  assert_file_contains "$log" $'set-window-option\t-t\t@1\tautomatic-rename\toff'
  assert_file_contains "$log" $'set-window-option\t-t\t@1\tallow-rename\toff'
  assert_file_contains "$log" $'rename-window\t-t\t@1\trepo'
  assert_file_contains "$log" $'split-window\t-h\t-P\t-F\t#{pane_id}\t-t\t%1\t-c\t'"$repo_real"$'\tclaude --resume'
  assert_file_contains "$log" $'split-window\t-v\t-P\t-F\t#{pane_id}\t-t\t%2\t-c\t'"$repo_real"
  assert_file_contains "$log" $'split-window\t-h\t-P\t-F\t#{pane_id}\t-t\t%3\t-c\t'"$repo_real"$'\tnpm test'
  assert_file_not_contains "$log" $'send-keys\t'
  assert_file_not_contains "$log" $'env-agent'
  assert_file_contains "$log" $'select-pane\t-t\t%1'
  assert_file_contains "$log" $'select-window\t-t\t@1'
  assert_file_contains "$log" $'attach-session\t-t\t$1'
}

test_real_tmux_prefix_session_does_not_count_as_exact_match() {
  local repo other repo_real real_tmux fake_bin no_fzf_path log socket session_id

  real_tmux="$(command -v tmux || true)"
  [[ -n "$real_tmux" ]] || return 0
  repo="$TEST_TMPDIR/foo"
  other="$TEST_TMPDIR/other"
  make_git_repo "$repo"
  mkdir -p "$other"
  repo_real="$(cd "$repo" && pwd -P)"
  fake_bin="$(make_real_tmux_wrapper "$TEST_TMPDIR/real-tmux")"
  no_fzf_path="$(make_path_without_fzf "$fake_bin")"
  log="$TEST_TMPDIR/tmux.log"
  socket="taw-test-$$-$RANDOM"
  REAL_TMUX_BIN_FOR_CLEANUP="$real_tmux"
  REAL_TMUX_SOCKET_FOR_CLEANUP="$socket"
  trap cleanup_real_tmux EXIT

  "$real_tmux" -L "$socket" -f /dev/null new-session -d -s foobar -c "$other" \
    zsh >/dev/null 2>&1
  EDITOR=zsh TAW_REAL_TMUX_BIN="$real_tmux" TAW_REAL_TMUX_SOCKET="$socket" \
    TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    TAW_RUN_PATH="$no_fzf_path" \
    run_taw "$repo" -p "$repo"

  session_id="$(real_tmux_session_id "$real_tmux" "$socket" foo)"
  assert_file_contains "$log" $'new-session\t-d\t-P\t-F\t#{session_id}\t#{session_name}\t#{window_id}\t#{pane_id}\t-s\tfoo\t-n\tfoo\t-c\t'"$repo_real"
  assert_file_contains "$log" $'attach-session\t-t\t'"$session_id"
}

test_real_tmux_uses_created_session_id_after_name_normalization() {
  local repo repo_real real_tmux fake_bin no_fzf_path log socket session_id

  real_tmux="$(command -v tmux || true)"
  [[ -n "$real_tmux" ]] || return 0
  repo="$TEST_TMPDIR/foo.bar"
  make_git_repo "$repo"
  repo_real="$(cd "$repo" && pwd -P)"
  fake_bin="$(make_real_tmux_wrapper "$TEST_TMPDIR/real-tmux")"
  no_fzf_path="$(make_path_without_fzf "$fake_bin")"
  log="$TEST_TMPDIR/tmux.log"
  socket="taw-test-$$-$RANDOM"
  REAL_TMUX_BIN_FOR_CLEANUP="$real_tmux"
  REAL_TMUX_SOCKET_FOR_CLEANUP="$socket"
  trap cleanup_real_tmux EXIT

  "$real_tmux" -L "$socket" -f /dev/null new-session -d -s taw-bootstrap \
    zsh >/dev/null 2>&1
  EDITOR=zsh TAW_REAL_TMUX_BIN="$real_tmux" TAW_REAL_TMUX_SOCKET="$socket" \
    TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    TAW_RUN_PATH="$no_fzf_path" \
    run_taw "$repo" -p "$repo"

  session_id="$(real_tmux_session_id "$real_tmux" "$socket" foo_bar)"
  assert_file_contains "$log" $'new-session\t-d\t-P\t-F\t#{session_id}\t#{session_name}\t#{window_id}\t#{pane_id}\t-s\tfoo.bar'
  assert_file_contains "$log" $'attach-session\t-t\t'"$session_id"
  assert_file_not_contains "$log" $'attach-session\t-t\tfoo.bar'
}

test_real_tmux_normalized_session_collision_fails_clearly() {
  local repo real_tmux fake_bin no_fzf_path log socket output session_count

  real_tmux="$(command -v tmux || true)"
  [[ -n "$real_tmux" ]] || return 0
  repo="$TEST_TMPDIR/foo.bar"
  make_git_repo "$repo"
  fake_bin="$(make_real_tmux_wrapper "$TEST_TMPDIR/real-tmux")"
  no_fzf_path="$(make_path_without_fzf "$fake_bin")"
  log="$TEST_TMPDIR/tmux.log"
  socket="taw-test-$$-$RANDOM"
  REAL_TMUX_BIN_FOR_CLEANUP="$real_tmux"
  REAL_TMUX_SOCKET_FOR_CLEANUP="$socket"
  trap cleanup_real_tmux EXIT

  "$real_tmux" -L "$socket" -f /dev/null new-session -d -s foo_bar \
    zsh >/dev/null 2>&1
  if output="$(EDITOR=zsh TAW_REAL_TMUX_BIN="$real_tmux" \
    TAW_REAL_TMUX_SOCKET="$socket" TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    TAW_RUN_PATH="$no_fzf_path" \
    run_taw "$repo" -p "$repo" 2>&1)"; then
    fail "expected normalized tmux session name collision to fail"
  fi

  assert_string_contains "$output" "could not create tmux session: foo.bar"
  session_count="$("$real_tmux" -L "$socket" list-sessions -F '#{session_id}' | wc -l | tr -d ' ')"
  assert_eq "1" "$session_count" "expected the collision not to create another session"
  assert_file_not_contains "$log" $'attach-session\t'
}

test_taw_agent_whitespace_only_defaults_to_codex() {
  local repo repo_real fake_bin log no_fzf_path

  repo="$TEST_TMPDIR/repo"
  make_git_repo "$repo"
  repo_real="$(cd "$repo" && pwd -P)"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  no_fzf_path="$(make_path_without_fzf "$fake_bin")"
  log="$TEST_TMPDIR/tmux.log"

  TAW_AGENT='   ' TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" \
    run_taw "$repo" -p "$repo"

  assert_file_contains "$log" $'split-window\t-h\t-P\t-F\t#{pane_id}\t-t\t%1\t-c\t'"$repo_real"$'\tcodex'
  assert_file_contains "$log" $'select-pane\t-t\t%1'
}

test_taw_agent_env_override_uses_trimmed_value() {
  local repo repo_real fake_bin log no_fzf_path

  repo="$TEST_TMPDIR/repo"
  make_git_repo "$repo"
  repo_real="$(cd "$repo" && pwd -P)"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  no_fzf_path="$(make_path_without_fzf "$fake_bin")"
  log="$TEST_TMPDIR/tmux.log"

  TAW_AGENT='  sleepy --watch  ' TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" \
    run_taw "$repo" -p "$repo"

  assert_file_contains "$log" $'split-window\t-h\t-P\t-F\t#{pane_id}\t-t\t%1\t-c\t'"$repo_real"$'\tsleepy --watch'
  assert_file_contains "$log" $'select-pane\t-t\t%1'
}

test_existing_session_adds_window_and_selects_it_before_attach() {
  local repo repo_real fake_bin log no_fzf_path sessions

  repo="$TEST_TMPDIR/repo"
  make_git_repo "$repo"
  repo_real="$(cd "$repo" && pwd -P)"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  no_fzf_path="$(make_path_without_fzf "$fake_bin")"
  log="$TEST_TMPDIR/tmux.log"
  sessions=$'repo\t'"$repo_real"$'\n'

  EDITOR=vim TAW_FAKE_TMUX_SESSIONS="$sessions" TAW_FAKE_TMUX_BIN="$fake_bin" \
    TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" \
    run_taw "$repo" -p "$repo"

  assert_file_contains "$log" $'list-sessions\t-F\t#{session_id}\t#{session_name}\t#{session_path}'
  assert_file_contains "$log" $'new-window\t-d\t-P\t-F\t#{window_id} #{pane_id}\t-t\t$1:\t-n\trepo\t-c\t'"$repo_real"$'\tvim'
  assert_file_contains "$log" $'set-window-option\t-t\t@1\tautomatic-rename\toff'
  assert_file_contains "$log" $'set-window-option\t-t\t@1\tallow-rename\toff'
  assert_file_contains "$log" $'rename-window\t-t\t@1\trepo'
  assert_file_contains "$log" $'select-window\t-t\t@1'
  assert_file_contains "$log" $'select-pane\t-t\t%1'
  assert_file_contains "$log" $'attach-session\t-t\t$1'
}

test_existing_worktree_window_is_reused() {
  local repo repo_real fake_bin log panes no_fzf_path sessions

  repo="$TEST_TMPDIR/repo"
  make_git_repo "$repo"
  mkdir -p "$repo/src"
  repo_real="$(cd "$repo" && pwd -P)"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  no_fzf_path="$(make_path_without_fzf "$fake_bin")"
  log="$TEST_TMPDIR/tmux.log"
  panes=$'@9\t%9\t'"$repo_real"$'/src\n'
  sessions=$'repo\t'"$repo_real"$'\n'

  EDITOR=vim TAW_FAKE_TMUX_SESSIONS="$sessions" TAW_FAKE_TMUX_PANES="$panes" \
    TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" \
    run_taw "$repo" -p "$repo"

  assert_file_contains "$log" $'list-sessions\t-F\t#{session_id}\t#{session_name}\t#{session_path}'
  assert_file_contains "$log" $'list-panes\t-s\t-t\t$1:\t-F\t#{window_id}\t#{pane_id}\t#{pane_current_path}'
  assert_file_contains "$log" $'select-window\t-t\t@9'
  assert_file_contains "$log" $'attach-session\t-t\t$1'
  assert_file_not_contains "$log" $'new-window\t'
  assert_file_not_contains "$log" $'new-session\t'
  assert_file_not_contains "$log" $'split-window\t'
  assert_file_not_contains "$log" $'rename-window\t'
}

test_taw_agent_env_disables_existing_window_reuse() {
  local repo repo_real fake_bin log panes no_fzf_path sessions

  repo="$TEST_TMPDIR/repo"
  make_git_repo "$repo"
  mkdir -p "$repo/src"
  repo_real="$(cd "$repo" && pwd -P)"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  no_fzf_path="$(make_path_without_fzf "$fake_bin")"
  log="$TEST_TMPDIR/tmux.log"
  panes=$'@9\t%9\t'"$repo_real"$'/src\n'
  sessions=$'repo\t'"$repo_real"$'\n'

  TAW_AGENT='  env-agent  ' EDITOR=vim TAW_FAKE_TMUX_SESSIONS="$sessions" TAW_FAKE_TMUX_PANES="$panes" \
    TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" \
    run_taw "$repo" -p "$repo"

  assert_file_contains "$log" $'list-sessions\t-F\t#{session_id}\t#{session_name}\t#{session_path}'
  assert_file_not_contains "$log" $'list-panes\t-s\t-t\t$1:\t-F\t#{window_id}\t#{pane_id}\t#{pane_current_path}'
  assert_file_contains "$log" $'new-window\t-d\t-P\t-F\t#{window_id} #{pane_id}\t-t\t$1:\t-n\trepo\t-c\t'"$repo_real"$'\tvim'
  assert_file_contains "$log" $'split-window\t-h\t-P\t-F\t#{pane_id}\t-t\t%1\t-c\t'"$repo_real"$'\tenv-agent'
  assert_file_not_contains "$log" $'select-window\t-t\t@9'
}

test_named_branch_checks_out_normal_repo() {
  local repo worktree_real fake_bin log branch

  repo="$TEST_TMPDIR/repo"
  make_git_repo "$repo"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"

  EDITOR="vim -u NONE" TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$repo" -p "$repo" -b develop

  worktree_real="$(cd "$repo/.worktrees/develop" && pwd -P)"
  branch="$(git -C "$worktree_real" branch --show-current)"
  assert_eq "develop" "$branch" "expected named branch worktree"
  assert_eq "main" "$(git -C "$repo" branch --show-current)" \
    "expected the primary worktree branch to remain unchanged"
  assert_file_contains "$log" $'new-session\t-d\t-P\t-F\t#{session_id}\t#{session_name}\t#{window_id}\t#{pane_id}\t-s\trepo\t-n\tdevelop\t-c\t'"$worktree_real"$'\tvim -u NONE'
  assert_file_contains "$log" $'rename-window\t-t\t@1\tdevelop'
  assert_file_contains "$log" $'split-window\t-h\t-P\t-F\t#{pane_id}\t-t\t%1\t-c\t'"$worktree_real"$'\tcodex'
  assert_file_not_contains "$log" $'send-keys\t'
}

test_normal_repo_no_explicit_branch_uses_picker_and_tracks_remote_branch() {
  local repo worktree_real fake_bin log branch upstream_ref

  repo="$TEST_TMPDIR/repo"
  make_git_repo "$repo"
  git -C "$repo" remote add origin "$TEST_TMPDIR/origin.git"
  git -C "$repo" update-ref refs/remotes/origin/feature/foo refs/heads/develop
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  make_fake_fzf "$fake_bin"
  log="$TEST_TMPDIR/tmux.log"

  EDITOR=vim TAW_FAKE_FZF_MATCH=$'feature/foo\tbranch' \
    TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$repo" -p "$repo"

  worktree_real="$(cd "$repo/.worktrees/feature/foo" && pwd -P)"
  branch="$(git -C "$worktree_real" branch --show-current)"
  upstream_ref="$(git -C "$worktree_real" rev-parse --abbrev-ref --symbolic-full-name @{u})"
  assert_eq "feature/foo" "$branch" "expected picker branch worktree"
  assert_eq "origin/feature/foo" "$upstream_ref" "expected remote branch tracking"
  assert_eq "main" "$(git -C "$repo" branch --show-current)" \
    "expected the primary worktree branch to remain unchanged"
  assert_file_contains "$log" $'new-session\t-d\t-P\t-F\t#{session_id}\t#{session_name}\t#{window_id}\t#{pane_id}\t-s\trepo\t-n\tfoo\t-c\t'"$worktree_real"$'\tvim'
  assert_file_not_contains "$log" $'send-keys\t'
}

test_normal_repo_picker_lists_deduped_branches() {
  local repo fake_bin log fzf_log main_count remote_count

  repo="$TEST_TMPDIR/repo"
  make_git_repo "$repo"
  git -C "$repo" remote add origin "$TEST_TMPDIR/origin.git"
  git -C "$repo" remote add upstream "$TEST_TMPDIR/upstream.git"
  git -C "$repo" update-ref refs/remotes/origin/main refs/heads/develop
  git -C "$repo" update-ref refs/remotes/upstream/remote-only refs/heads/main
  git -C "$repo" update-ref refs/remotes/origin/remote-only refs/heads/develop
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  make_fake_fzf "$fake_bin"
  log="$TEST_TMPDIR/tmux.log"
  fzf_log="$TEST_TMPDIR/fzf-input.log"

  EDITOR=vim TAW_FAKE_FZF_MATCH=$'remote-only\tbranch' TAW_FZF_INPUT_LOG="$fzf_log" \
    TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$repo" -p "$repo"

  main_count="$(grep -F $'main [worktree]\tworktree' "$fzf_log" | wc -l | tr -d ' ')"
  remote_count="$(grep -F $'remote-only\tbranch' "$fzf_log" | wc -l | tr -d ' ')"
  assert_eq "1" "$main_count" "expected root main worktree to suppress branch duplicates"
  assert_eq "1" "$remote_count" "expected duplicate remote branches to dedupe to one picker row"
  assert_file_contains "$fzf_log" $'remote-only\tbranch\tremote-only\torigin/remote-only\t'
  assert_file_not_contains "$fzf_log" $'origin/main'
  assert_file_not_contains "$fzf_log" $'upstream/remote-only'
}

test_branch_picker_loads_remotes_once() {
  local repo repo_real fake_bin no_fzf_path log git_log remote_call

  repo="$TEST_TMPDIR/repo"
  make_git_repo "$repo"
  git -C "$repo" remote add origin "$TEST_TMPDIR/origin.git"
  git -C "$repo" remote add upstream "$TEST_TMPDIR/upstream.git"
  git -C "$repo" remote add team/nested "$TEST_TMPDIR/team.git"
  git -C "$repo" update-ref refs/remotes/origin/remote-a refs/heads/main
  git -C "$repo" update-ref refs/remotes/upstream/remote-b refs/heads/develop
  git -C "$repo" update-ref refs/remotes/team/nested/remote-c refs/heads/main
  repo_real="$(cd "$repo" && pwd -P)"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  make_fake_fzf "$fake_bin"
  no_fzf_path="$(make_path_without_fzf "$fake_bin")"
  make_logging_git "$fake_bin"
  log="$TEST_TMPDIR/tmux.log"
  git_log="$TEST_TMPDIR/git.log"
  export TAW_GIT_LOG="$git_log"

  EDITOR=vim TAW_FAKE_FZF_MATCH=main \
    TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" \
  run_taw "$repo" --mode=branch
  unset TAW_GIT_LOG
  unset TAW_REAL_GIT

  remote_call=$'-C\t'"$repo_real"$'\tremote'
  assert_eq "1" "$(grep -Fxc -- "$remote_call" "$git_log")" \
    "expected branch picker to load configured remotes once"
}

test_normal_repo_no_explicit_branch_without_fzf_opens_repo_unchanged() {
  local repo repo_real fake_bin log branch no_fzf_path

  repo="$TEST_TMPDIR/repo"
  make_git_repo "$repo"
  repo_real="$(cd "$repo" && pwd -P)"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  no_fzf_path="$(make_path_without_fzf "$fake_bin")"
  log="$TEST_TMPDIR/tmux.log"

  EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" \
    run_taw "$repo" -p "$repo"

  branch="$(git -C "$repo" branch --show-current)"
  assert_eq "main" "$branch" "expected repo to remain on current branch"
  assert_file_contains "$log" $'new-session\t-d\t-P\t-F\t#{session_id}\t#{session_name}\t#{window_id}\t#{pane_id}\t-s\trepo\t-n\trepo\t-c\t'"$repo_real"$'\tvim'
  assert_file_not_contains "$log" $'checkout\t'
}

test_normal_linked_worktree_resolves_primary_project() {
  local repo worktree worktree_real fake_bin log no_fzf_path

  repo="$TEST_TMPDIR/repo"
  worktree="$repo/.worktrees/develop"
  make_git_repo "$repo"
  git -C "$repo" worktree add -q "$worktree" develop
  worktree_real="$(cd "$worktree" && pwd -P)"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  no_fzf_path="$(make_path_without_fzf "$fake_bin")"
  log="$TEST_TMPDIR/tmux.log"

  EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    TAW_RUN_PATH="$no_fzf_path" run_taw "$TEST_TMPDIR" -p "$worktree"

  assert_file_contains "$log" \
    $'new-session\t-d\t-P\t-F\t#{session_id}\t#{session_name}\t#{window_id}\t#{pane_id}\t-s\trepo\t-n\tdevelop\t-c\t'"$worktree_real"$'\tvim'
}

test_normal_repo_picker_cancel_returns_success_without_tmux() {
  local repo fake_bin log

  repo="$TEST_TMPDIR/repo"
  make_git_repo "$repo"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  make_fake_fzf "$fake_bin"
  log="$TEST_TMPDIR/tmux.log"

  EDITOR=vim TAW_FAKE_FZF_CANCEL=1 TAW_FAKE_FZF_MATCH=$'main\tbranch' TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$repo" -p "$repo"

  [[ ! -f "$log" ]] || fail "expected tmux not to run after picker cancel"
}

test_normal_repo_picker_error_fails_without_tmux() {
  local repo fake_bin log

  repo="$TEST_TMPDIR/repo"
  make_git_repo "$repo"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  make_fake_fzf "$fake_bin"
  log="$TEST_TMPDIR/tmux.log"

  if EDITOR=vim TAW_FAKE_FZF_INDEX=99 TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$repo" -p "$repo"; then
    fail "expected picker error to fail"
  fi
  [[ ! -f "$log" ]] || fail "expected tmux not to run after picker error"
}

test_explicit_normal_origin_topic_local_branch_wins_over_remote() {
  local repo fake_bin log branch

  repo="$TEST_TMPDIR/repo"
  make_git_repo "$repo"
  git -C "$repo" branch origin/topic main
  git -C "$repo" remote add origin "$TEST_TMPDIR/origin.git"
  git -C "$repo" update-ref refs/remotes/origin/topic refs/heads/develop
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"

  EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$repo" -p "$repo" -b origin/topic

  branch="$(git -C "$repo/.worktrees/origin/topic" branch --show-current)"
  assert_eq "origin/topic" "$branch" "expected exact local branch to win"
  assert_eq "main" "$(git -C "$repo" branch --show-current)" \
    "expected the primary worktree branch to remain unchanged"
  assert_file_contains "$log" $'new-session\t-d\t-P\t-F\t#{session_id}\t#{session_name}\t#{window_id}\t#{pane_id}\t-s\trepo\t-n\ttopic'
}

test_explicit_normal_longest_remote_prefix_resolves_to_nested_remote_branch() {
  local repo fake_bin log branch upstream_ref

  repo="$TEST_TMPDIR/repo"
  make_git_repo "$repo"
  git -C "$repo" config remote.foo.url "$TEST_TMPDIR/foo.git"
  git -C "$repo" config remote.foo.fetch "+refs/heads/*:refs/remotes/foo/*"
  git -C "$repo" config remote.foo/bar.url "$TEST_TMPDIR/foo-bar.git"
  git -C "$repo" config remote.foo/bar.fetch "+refs/heads/*:refs/remotes/foo/bar/*"
  git -C "$repo" update-ref refs/remotes/foo/bar/topic refs/heads/develop
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"

  EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$repo" -p "$repo" -b foo/bar/topic

  branch="$(git -C "$repo/.worktrees/topic" branch --show-current)"
  upstream_ref="$(git -C "$repo/.worktrees/topic" rev-parse --abbrev-ref --symbolic-full-name @{u})"
  assert_eq "topic" "$branch" "expected longest remote prefix to resolve nested remote branch"
  assert_eq "foo/bar/topic" "$upstream_ref" "expected nested remote branch tracking"
}

test_explicit_normal_branch_resolves_remote_only_by_branch_name() {
  local repo fake_bin log branch upstream_ref

  repo="$TEST_TMPDIR/repo"
  make_git_repo "$repo"
  git -C "$repo" remote add origin "$TEST_TMPDIR/origin.git"
  git -C "$repo" update-ref refs/remotes/origin/feature/foo refs/heads/develop
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"

  EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$repo" -p "$repo" -b feature/foo

  branch="$(git -C "$repo/.worktrees/feature/foo" branch --show-current)"
  upstream_ref="$(git -C "$repo/.worktrees/feature/foo" rev-parse --abbrev-ref --symbolic-full-name @{u})"
  assert_eq "feature/foo" "$branch" "expected remote-only branch to create local branch"
  assert_eq "origin/feature/foo" "$upstream_ref" "expected remote-only branch tracking"
}

test_explicit_normal_branch_ignores_stale_unconfigured_remote_ref() {
  local repo fake_bin log branch upstream_ref

  repo="$TEST_TMPDIR/repo"
  make_git_repo "$repo"
  git -C "$repo" remote add origin "$TEST_TMPDIR/origin.git"
  git -C "$repo" update-ref refs/remotes/origin/feature/foo refs/heads/develop
  git -C "$repo" update-ref refs/remotes/feature/foo refs/heads/main
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"

  EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$repo" -p "$repo" -b feature/foo

  branch="$(git -C "$repo/.worktrees/feature/foo" branch --show-current)"
  upstream_ref="$(git -C "$repo/.worktrees/feature/foo" rev-parse --abbrev-ref --symbolic-full-name @{u})"
  assert_eq "feature/foo" "$branch" "expected stale unconfigured remote ref to stay on the branch name"
  assert_eq "origin/feature/foo" "$upstream_ref" "expected configured remote to win over stale remote ref"
}

test_explicit_normal_configured_remote_prefix_missing_ref_fails() {
  local repo fake_bin log

  repo="$TEST_TMPDIR/repo"
  make_git_repo "$repo"
  git -C "$repo" remote add origin "$TEST_TMPDIR/origin.git"
  git -C "$repo" remote add upstream "$TEST_TMPDIR/upstream.git"
  git -C "$repo" update-ref refs/remotes/upstream/origin/topic refs/heads/develop
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"

  if EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$repo" -p "$repo" -b origin/topic; then
    fail "expected configured remote prefix with missing ref to fail"
  fi
  if git -C "$repo" show-ref --verify --quiet refs/heads/origin/topic; then
    fail "expected origin/topic local branch not to be created from another remote"
  fi
  [[ ! -f "$log" ]] || fail "expected tmux not to run after missing configured remote ref"
}

test_explicit_normal_branch_rejects_refs_remotes_prefix() {
  local repo fake_bin log

  repo="$TEST_TMPDIR/repo"
  make_git_repo "$repo"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"

  if EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$repo" -p "$repo" -b refs/remotes/origin/topic; then
    fail "expected refs/remotes input to be rejected"
  fi
  [[ ! -f "$log" ]] || fail "expected tmux not to run after rejected branch"
}

test_project_arg_resolves_from_projects_home() {
  local projects_home repo repo_real fake_bin log no_fzf_path

  projects_home="$TEST_TMPDIR/projects"
  repo="$projects_home/foo"
  make_git_repo "$repo"
  repo_real="$(cd "$repo" && pwd -P)"
  mkdir -p "$TEST_TMPDIR/elsewhere"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  no_fzf_path="$(make_path_without_fzf "$fake_bin")"
  log="$TEST_TMPDIR/tmux.log"

  PROJECTS_HOME="$projects_home" EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" \
    run_taw "$TEST_TMPDIR/elsewhere" -p foo

  assert_file_contains "$log" $'new-session\t-d\t-P\t-F\t#{session_id}\t#{session_name}\t#{window_id}\t#{pane_id}\t-s\tfoo\t-n\tfoo\t-c\t'"$repo_real"$'\tvim'
}

test_project_arg_direct_path_precedes_projects_home() {
  local projects_home direct_repo projects_repo direct_real projects_real fake_bin log no_fzf_path

  projects_home="$TEST_TMPDIR/projects"
  direct_repo="$TEST_TMPDIR/current/foo"
  projects_repo="$projects_home/foo"
  make_git_repo "$direct_repo"
  make_git_repo "$projects_repo"
  direct_real="$(cd "$direct_repo" && pwd -P)"
  projects_real="$(cd "$projects_repo" && pwd -P)"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  no_fzf_path="$(make_path_without_fzf "$fake_bin")"
  log="$TEST_TMPDIR/tmux.log"

  PROJECTS_HOME="$projects_home" EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" \
    run_taw "$TEST_TMPDIR/current" -p foo

  assert_file_contains "$log" $'-c\t'"$direct_real"$'\tvim'
  assert_file_not_contains "$log" $'-c\t'"$projects_real"$'\tvim'
}

test_project_arg_plain_path_opens_plain_project() {
  local plain plain_real fake_bin log no_fzf_path

  plain="$TEST_TMPDIR/plain"
  mkdir -p "$TEST_TMPDIR/elsewhere"
  mkdir -p "$plain"
  plain_real="$(cd "$plain" && pwd -P)"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  no_fzf_path="$(make_path_without_fzf "$fake_bin")"
  log="$TEST_TMPDIR/tmux.log"

  EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" \
    run_taw "$TEST_TMPDIR/elsewhere" -p "$plain"

  assert_file_contains "$log" $'new-session\t-d\t-P\t-F\t#{session_id}\t#{session_name}\t#{window_id}\t#{pane_id}\t-s\tplain\t-n\tplain\t-c\t'"$plain_real"$'\tvim'
  assert_file_contains "$log" $'select-pane\t-t\t%1'
  assert_file_not_contains "$log" $'checkout\t'
  assert_file_not_contains "$log" $'worktree\tadd'
}

test_plain_project_picker_target_opens_plain_directory() {
  local xdg projects_home plain plain_real fake_bin log fzf_log no_fzf_path

  xdg="$TEST_TMPDIR/xdg"
  projects_home="$TEST_TMPDIR/projects"
  plain="$projects_home/plain"
  mkdir -p "$xdg/tmux-sessionizer" "$projects_home" "$TEST_TMPDIR/elsewhere"
  printf 'TS_SEARCH_PATHS=("%s")\n' "$projects_home" >"$xdg/tmux-sessionizer/tmux-sessionizer.conf"
  mkdir -p "$plain"
  plain_real="$(cd "$plain" && pwd -P)"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  make_fake_fzf "$fake_bin"
  no_fzf_path="$(make_path_without_fzf "$fake_bin")"
  log="$TEST_TMPDIR/tmux.log"
  fzf_log="$TEST_TMPDIR/fzf-input.log"

  XDG_CONFIG_HOME="$xdg" EDITOR=vim TAW_FAKE_FZF_MATCH="$plain" TAW_FZF_INPUT_LOG="$fzf_log" \
    TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" \
    run_taw "$TEST_TMPDIR/elsewhere" --pick-project

  assert_file_contains "$fzf_log" "$plain"
  assert_file_contains "$log" $'new-session\t-d\t-P\t-F\t#{session_id}\t#{session_name}\t#{window_id}\t#{pane_id}\t-s\tplain\t-n\tplain\t-c\t'"$plain_real"$'\tvim'
  assert_file_not_contains "$log" $'worktree\tadd'
}

test_plain_project_rejects_branch_and_operands() {
  local plain fake_bin log

  plain="$TEST_TMPDIR/plain"
  mkdir -p "$plain"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"

  if EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$TEST_TMPDIR/elsewhere" -p "$plain" -b develop; then
    fail "expected plain project to reject -b"
  fi
  [[ ! -f "$log" ]] || fail "expected tmux not to run after plain -b"

  if EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$TEST_TMPDIR/elsewhere" -p "$plain" feature-x; then
    fail "expected plain project to reject positional operands"
  fi
  [[ ! -f "$log" ]] || fail "expected tmux not to run after plain positional operands"
}

test_outside_promotion_uses_single_positional_as_project_arg() {
  local repo repo_real fake_bin log no_fzf_path

  repo="$TEST_TMPDIR/repo"
  mkdir -p "$TEST_TMPDIR/elsewhere"
  make_git_repo "$repo"
  repo_real="$(cd "$repo" && pwd -P)"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  no_fzf_path="$(make_path_without_fzf "$fake_bin")"
  log="$TEST_TMPDIR/tmux.log"

  EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" \
    run_taw "$TEST_TMPDIR/elsewhere" "$repo"

  assert_file_contains "$log" $'new-session\t-d\t-P\t-F\t#{session_id}\t#{session_name}\t#{window_id}\t#{pane_id}\t-s\trepo\t-n\trepo\t-c\t'"$repo_real"$'\tvim'
}

test_outside_promotion_uses_project_and_operand_positionals() {
  local project fake_bin log branch worktree_real

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  git --git-dir "$project/.git" branch feature-x main
  mkdir -p "$TEST_TMPDIR/elsewhere"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"

  EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$TEST_TMPDIR/elsewhere" "$project" feature-x

  branch="$(git -C "$project/.worktrees/feature-x" branch --show-current)"
  worktree_real="$(cd "$project/.worktrees/feature-x" && pwd -P)"
  assert_eq "feature-x" "$branch" "expected promoted positional project to keep remaining operand"
  assert_file_contains "$log" $'new-session\t-d\t-P\t-F\t#{session_id}\t#{session_name}\t#{window_id}\t#{pane_id}\t-s\tproject\t-n\tfeature-x'
  assert_file_contains "$log" $'-c\t'"$worktree_real"$'\tvim'
}

test_outside_promotion_rejects_branch_flag() {
  local fake_bin log

  mkdir -p "$TEST_TMPDIR/elsewhere"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"

  if EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$TEST_TMPDIR/elsewhere" -b develop; then
    fail "expected -b outside a project to fail"
  fi
  [[ ! -f "$log" ]] || fail "expected tmux not to run after outside -b"
}

test_project_arg_preserves_invoking_shell_cwd() {
  local repo start start_real fake_bin log after no_fzf_path

  repo="$TEST_TMPDIR/repo"
  start="$TEST_TMPDIR/start"
  make_git_repo "$repo"
  mkdir -p "$start"
  start_real="$(cd "$start" && pwd -P)"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  no_fzf_path="$(make_path_without_fzf "$fake_bin")"
  log="$TEST_TMPDIR/tmux.log"

  after="$(
    cd "$start" || exit 1
    TAW_FUNC_DIR="$REPO_ROOT/home/.zfuns" \
      PATH="$no_fzf_path" \
      TMUX= \
      EDITOR=vim \
      TAW_TMUX_LOG="$log" \
      zsh -fc 'fpath=("$TAW_FUNC_DIR" $fpath); autoload -U taw; taw "$@" || return; print -r -- "${PWD:A}"' taw -p "$repo"
  )" || fail "expected taw to succeed"

  assert_eq "$start_real" "$after" "expected taw to preserve invoking shell cwd"
}

test_project_arg_github_url_clones_and_opens_project() {
  local src dest fake_bin no_fzf_path log url branch worktree_real

  src="$TEST_TMPDIR/src"
  dest="$TEST_TMPDIR/cloned"
  url="https://example.invalid/repo.git"
  make_git_repo "$src"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  no_fzf_path="$(make_path_without_fzf "$fake_bin")"
  make_fake_git_url_clone "$fake_bin"
  log="$TEST_TMPDIR/tmux.log"

  printf '%s\n\n' "$dest" | EDITOR=vim \
    TAW_FAKE_GIT_CLONE_SOURCE="$src" TAW_FAKE_GIT_CLONE_URL="$url" \
    TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" \
    run_taw "$TEST_TMPDIR" -p "$url"

  branch="$(git -C "$dest" branch --show-current)"
  worktree_real="$(cd "$dest" && pwd -P)"
  assert_eq "main" "$branch" "expected -p URL to clone and open a normal repository"
  assert_exists "$dest/.git"
  assert_file_contains "$log" $'new-session\t-d\t-P\t-F\t#{session_id}\t#{session_name}\t#{window_id}\t#{pane_id}\t-s\tcloned\t-n\tcloned'
  assert_file_contains "$log" $'-c\t'"$worktree_real"$'\tvim'
}

test_project_arg_url_allows_explicit_bare_clone() {
  local src dest fake_bin no_fzf_path log url branch

  src="$TEST_TMPDIR/src"
  dest="$TEST_TMPDIR/cloned"
  url="https://example.invalid/repo.git"
  make_git_repo "$src"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  no_fzf_path="$(make_path_without_fzf "$fake_bin")"
  make_fake_git_url_clone "$fake_bin"
  log="$TEST_TMPDIR/tmux.log"

  printf '%s\nbare\n' "$dest" | EDITOR=vim \
    TAW_FAKE_GIT_CLONE_SOURCE="$src" TAW_FAKE_GIT_CLONE_URL="$url" \
    TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" \
    run_taw "$TEST_TMPDIR" -p "$url"

  branch="$(git --git-dir "$dest/.git" symbolic-ref --quiet --short HEAD)"
  assert_eq "true" "$(git --git-dir "$dest/.git" rev-parse --is-bare-repository)" \
    "expected explicit bare clone selection to remain available"
  assert_eq "$branch" "$(git -C "$dest/.worktrees/$branch" branch --show-current)" \
    "expected explicit bare clone worktree under .worktrees"
}

test_project_arg_resolves_by_tmux_session_name() {
  local repo repo_real fake_bin log sessions no_fzf_path

  repo="$TEST_TMPDIR/session-repo"
  make_git_repo "$repo"
  repo_real="$(cd "$repo" && pwd -P)"
  mkdir -p "$TEST_TMPDIR/elsewhere"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  no_fzf_path="$(make_path_without_fzf "$fake_bin")"
  log="$TEST_TMPDIR/tmux.log"
  sessions=$'agent\t'"$repo_real"$'\n'

  EDITOR=vim TAW_FAKE_TMUX_HAS_SESSION=1 TAW_FAKE_TMUX_SESSIONS="$sessions" \
    TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" \
    run_taw "$TEST_TMPDIR/elsewhere" -p agent

  assert_file_contains "$log" $'list-sessions\t-F\t#{session_id}\t#{session_name}\t#{session_path}'
  assert_file_contains "$log" $'has-session\t-t\t$1'
  assert_file_contains "$log" $'new-window\t-d\t-P\t-F\t#{window_id} #{pane_id}\t-t\t$1:\t-n\tsession-repo\t-c\t'"$repo_real"$'\tvim'
  assert_file_contains "$log" $'rename-window\t-t\t@1\tsession-repo'
}

test_project_arg_resolves_by_tmux_session_path_basename() {
  local repo repo_real fake_bin log sessions no_fzf_path

  repo="$TEST_TMPDIR/path-match"
  make_git_repo "$repo"
  repo_real="$(cd "$repo" && pwd -P)"
  mkdir -p "$TEST_TMPDIR/elsewhere"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  no_fzf_path="$(make_path_without_fzf "$fake_bin")"
  log="$TEST_TMPDIR/tmux.log"
  sessions=$'alpha\t'"$repo_real"$'\n'

  EDITOR=vim TAW_FAKE_TMUX_HAS_SESSION=1 TAW_FAKE_TMUX_SESSIONS="$sessions" \
    TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" \
    run_taw "$TEST_TMPDIR/elsewhere" -p path-match

  assert_file_contains "$log" $'has-session\t-t\t$1'
  assert_file_contains "$log" $'new-window\t-d\t-P\t-F\t#{window_id} #{pane_id}\t-t\t$1:\t-n\tpath-match\t-c\t'"$repo_real"$'\tvim'
}

test_project_arg_exact_tmux_match_failure_does_not_fallback() {
  local fallback_repo fallback_real missing_path elsewhere fake_bin log sessions no_fzf_path

  fallback_repo="$TEST_TMPDIR/agent"
  missing_path="$TEST_TMPDIR/missing-agent"
  elsewhere="$TEST_TMPDIR/elsewhere"
  make_git_repo "$fallback_repo"
  fallback_real="$(cd "$fallback_repo" && pwd -P)"
  mkdir -p "$elsewhere"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  no_fzf_path="$(make_path_without_fzf "$fake_bin")"
  log="$TEST_TMPDIR/tmux.log"
  sessions=$'agent\t'"$missing_path"$'\nalpha\t'"$fallback_real"$'\n'

  if printf 'y\nrepo\n' | EDITOR=vim TAW_FAKE_TMUX_HAS_SESSION=1 TAW_FAKE_TMUX_SESSIONS="$sessions" \
    TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" \
    run_taw "$elsewhere" -p agent; then
    fail "expected unusable exact tmux session to fail"
  fi

  assert_not_exists "$elsewhere/agent"
  assert_no_tmux_work_window "$log"
  assert_file_not_contains "$log" $'-c\t'"$fallback_real"
}

test_project_arg_unresolved_create_refusal_makes_no_mutation() {
  local repo repo_real fake_bin log sessions

  repo="$TEST_TMPDIR/other"
  make_git_repo "$repo"
  repo_real="$(cd "$repo" && pwd -P)"
  mkdir -p "$TEST_TMPDIR/elsewhere"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"
  sessions=$'alpha\t'"$repo_real"$'\n'

  if printf 'n\n' | EDITOR=vim TAW_FAKE_TMUX_SESSIONS="$sessions" TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$TEST_TMPDIR/elsewhere" -p missing; then
    fail "expected unresolved -p project refusal to fail"
  fi

  assert_file_contains "$log" $'list-sessions\t-F\t#{session_id}\t#{session_name}\t#{session_path}'
  assert_file_not_contains "$log" $'new-session\t'
  assert_file_not_contains "$log" $'new-window\t'
}

test_project_arg_unresolved_rejects_invalid_create_kind() {
  local fake_bin log

  mkdir -p "$TEST_TMPDIR/elsewhere"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"

  if printf 'y\ninvalid\n' | EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$TEST_TMPDIR/elsewhere" -p missing; then
    fail "expected invalid create kind to fail"
  fi

  assert_no_tmux_work_window "$log"
}

test_unresolved_project_flag_creates_plain_repo_and_bare_projects() {
  local projects_home fake_bin no_fzf_path log plain_target plain_target_real repo_target repo_target_real bare_target branch worktree_real

  projects_home="$TEST_TMPDIR/projects"
  mkdir -p "$TEST_TMPDIR/elsewhere" "$projects_home"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  no_fzf_path="$(make_path_without_fzf "$fake_bin")"
  log="$TEST_TMPDIR/tmux.log"

  printf 'y\nplain\n' | PROJECTS_HOME="$projects_home" EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" \
    run_taw "$TEST_TMPDIR/elsewhere" -p plain-missing
  plain_target="$projects_home/plain-missing"
  assert_exists "$plain_target"
  plain_target_real="$(cd "$plain_target" && pwd -P)"
  assert_file_contains "$log" $'-c\t'"$plain_target_real"$'\tvim'

  rm -f "$log"
  printf 'y\nrepo\n' | PROJECTS_HOME="$projects_home" EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" \
    run_taw "$TEST_TMPDIR/elsewhere" -p repo-missing
  repo_target="$projects_home/repo-missing"
  assert_exists "$repo_target/.git"
  [[ -n "$(git -C "$repo_target" branch --show-current)" ]] || fail "expected created repo to have a current branch"
  repo_target_real="$(cd "$repo_target" && pwd -P)"
  assert_file_contains "$log" $'-c\t'"$repo_target_real"$'\tvim'

  rm -f "$log"
  printf 'y\nbare\n' | PROJECTS_HOME="$projects_home" EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" \
    run_taw "$TEST_TMPDIR/elsewhere" -p bare-missing
  bare_target="$projects_home/bare-missing"
  branch="$(git --git-dir "$bare_target/.git" symbolic-ref --quiet --short HEAD)"
  worktree_real="$(cd "$bare_target/.worktrees/$branch" && pwd -P)"
  assert_exists "$bare_target/.git"
  assert_exists "$bare_target/.worktrees/$branch"
  assert_eq "$branch" "$(git -C "$bare_target/.worktrees/$branch" branch --show-current)" "expected bare creation to open orphan worktree"
  assert_file_contains "$log" $'-c\t'"$worktree_real"$'\tvim'
}

test_prompt_input_unresolved_creates_repo_project() {
  local fake_bin no_fzf_path log repo_real

  mkdir -p "$TEST_TMPDIR/elsewhere"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  no_fzf_path="$(make_path_without_fzf "$fake_bin")"
  log="$TEST_TMPDIR/tmux.log"

  repo_real="$TEST_TMPDIR/elsewhere/prompted-missing"
  printf '%s\ny\nrepo\n' "$repo_real" | EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" \
    run_taw "$TEST_TMPDIR/elsewhere"

  assert_exists "$repo_real/.git"
  repo_real="$(cd "$repo_real" && pwd -P)"
  assert_file_contains "$log" $'new-session\t-d\t-P\t-F\t#{session_id}\t#{session_name}\t#{window_id}\t#{pane_id}\t-s\tprompted-missing\t-n\tprompted-missing\t-c\t'"$repo_real"$'\tvim'
}

test_outside_positional_unresolved_creates_repo_project() {
  local fake_bin no_fzf_path log repo_real

  mkdir -p "$TEST_TMPDIR/elsewhere"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  no_fzf_path="$(make_path_without_fzf "$fake_bin")"
  log="$TEST_TMPDIR/tmux.log"

  repo_real="$TEST_TMPDIR/elsewhere/missing"
  printf 'y\nrepo\n' | EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" \
    run_taw "$TEST_TMPDIR/elsewhere" "$repo_real"

  assert_exists "$repo_real/.git"
  repo_real="$(cd "$repo_real" && pwd -P)"
  assert_file_contains "$log" $'new-session\t-d\t-P\t-F\t#{session_id}\t#{session_name}\t#{window_id}\t#{pane_id}\t-s\tmissing\t-n\tmissing\t-c\t'"$repo_real"$'\tvim'
}

test_unresolved_repo_branch_target_creates_worktree() {
  local repo fake_bin log worktree_real

  repo="$TEST_TMPDIR/repo"
  mkdir -p "$TEST_TMPDIR/elsewhere"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"

  printf 'y\nrepo\n' | EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$TEST_TMPDIR/elsewhere" -p "$repo" -b feature/topic

  worktree_real="$(cd "$repo/.worktrees/feature/topic" && pwd -P)"
  assert_eq "feature/topic" "$(git -C "$worktree_real" branch --show-current)" \
    "expected the requested branch in a managed worktree"
  assert_file_contains "$log" $'-c\t'"$worktree_real"$'\tvim'
}

test_unresolved_project_creation_rejects_invalid_repo_and_bare_names_before_mkdir() {
  local fake_bin log repo_target bare_target

  mkdir -p "$TEST_TMPDIR/elsewhere"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"
  repo_target="$TEST_TMPDIR/elsewhere/repo-invalid"
  bare_target="$TEST_TMPDIR/elsewhere/bare-invalid"

  if printf 'y\nrepo\n' | EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$TEST_TMPDIR/elsewhere" -p "$repo_target" -b 'bad..branch'; then
    fail "expected invalid repo branch to fail"
  fi
  assert_not_exists "$repo_target"

  rm -f "$log"
  if printf 'y\nbare\n' | EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$TEST_TMPDIR/elsewhere" -p "$bare_target" 'bad..branch'; then
    fail "expected invalid bare worktree branch to fail"
  fi
  assert_not_exists "$bare_target"
}

test_url_clone_failure_does_not_prompt_create() {
  local src fake_bin no_fzf_path log

  src="$TEST_TMPDIR/src"
  mkdir -p "$TEST_TMPDIR/elsewhere"
  make_git_repo "$src"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  no_fzf_path="$(make_path_without_fzf "$fake_bin")"
  make_fake_git_url_clone "$fake_bin"
  log="$TEST_TMPDIR/tmux.log"

  if printf '%s\n\n' "$TEST_TMPDIR/cloned" | EDITOR=vim \
    TAW_FAKE_GIT_CLONE_SOURCE="$src" TAW_FAKE_GIT_CLONE_URL="https://example.invalid/repo.git" TAW_FAKE_GIT_CLONE_FAIL=1 \
    TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" \
    run_taw "$TEST_TMPDIR/elsewhere" -p "https://example.invalid/repo.git"; then
    fail "expected clone failure to fail"
  fi

  [[ ! -f "$log" ]] || fail "expected tmux not to run after clone failure"
}

test_existing_file_and_broken_symlink_fail_without_create_prompt() {
  local fake_bin log file symlink target

  mkdir -p "$TEST_TMPDIR/elsewhere"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"

  file="$TEST_TMPDIR/elsewhere/existing-file"
  printf 'content\n' >"$file"
  if printf 'n\n' | EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$TEST_TMPDIR/elsewhere" -p "$file"; then
    fail "expected existing file to fail"
  fi
  [[ ! -f "$log" ]] || fail "expected tmux not to run after existing file"

  rm -f "$log"
  target="$TEST_TMPDIR/elsewhere/missing"
  symlink="$TEST_TMPDIR/elsewhere/broken-link"
  ln -s "$target" "$symlink"
  if printf 'n\n' | EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$TEST_TMPDIR/elsewhere" -p "$symlink"; then
    fail "expected broken symlink to fail"
  fi
  [[ ! -f "$log" ]] || fail "expected tmux not to run after broken symlink"
}

test_projects_home_file_and_broken_symlink_fail_without_create_prompt() {
  local projects_home elsewhere fake_bin log output file symlink target rc

  projects_home="$TEST_TMPDIR/projects"
  elsewhere="$TEST_TMPDIR/elsewhere"
  mkdir -p "$projects_home" "$elsewhere"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"

  file="$projects_home/existing-file"
  printf 'content\n' >"$file"
  set +e
  output="$(printf 'y\nrepo\n' | PROJECTS_HOME="$projects_home" EDITOR=vim \
    TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$elsewhere" -p existing-file 2>&1)"
  rc=$?
  set -e
  [[ $rc -ne 0 ]] || fail "expected PROJECTS_HOME file candidate to fail"
  assert_string_not_contains "$output" "Create project at"
  [[ ! -f "$log" ]] || fail "expected tmux not to run after PROJECTS_HOME file"

  rm -f "$log"
  target="$projects_home/missing"
  symlink="$projects_home/broken-link"
  ln -s "$target" "$symlink"
  set +e
  output="$(printf 'y\nrepo\n' | PROJECTS_HOME="$projects_home" EDITOR=vim \
    TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$elsewhere" -p broken-link 2>&1)"
  rc=$?
  set -e
  [[ $rc -ne 0 ]] || fail "expected PROJECTS_HOME broken symlink candidate to fail"
  assert_string_not_contains "$output" "Create project at"
  [[ ! -f "$log" ]] || fail "expected tmux not to run after PROJECTS_HOME broken symlink"
}

test_creates_bare_worktree_from_positional_base_ref() {
  local project fake_bin log expected actual branch worktree_real

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"

  EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$TEST_TMPDIR" -p "$project" fix/broken-feature develop

  branch="$(git -C "$project/.worktrees/fix/broken-feature" branch --show-current)"
  expected="$(git -C "$project" rev-parse develop)"
  actual="$(git -C "$project/.worktrees/fix/broken-feature" rev-parse HEAD)"
  worktree_real="$(cd "$project/.worktrees/fix/broken-feature" && pwd -P)"
  assert_eq "fix/broken-feature" "$branch" "expected worktree branch named after worktree path"
  assert_eq "$expected" "$actual" "expected worktree branch to start from positional base ref"
  assert_file_contains "$log" $'new-session\t-d\t-P\t-F\t#{session_id}\t#{session_name}\t#{window_id}\t#{pane_id}\t-s\tproject\t-n\tbroken-feature'
  assert_file_contains "$log" $'rename-window\t-t\t@1\tbroken-feature'
  assert_file_contains "$log" $'-c\t'"$worktree_real"
}

test_creates_bare_worktree_from_positional_path_branch() {
  local project fake_bin log branch worktree_real

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"

  EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$TEST_TMPDIR" -p "$project" fix/broken-feature

  branch="$(git -C "$project/.worktrees/fix/broken-feature" branch --show-current)"
  worktree_real="$(cd "$project/.worktrees/fix/broken-feature" && pwd -P)"
  assert_eq "fix/broken-feature" "$branch" "expected positional path to become the branch name"
  assert_file_contains "$log" $'new-session\t-d\t-P\t-F\t#{session_id}\t#{session_name}\t#{window_id}\t#{pane_id}\t-s\tproject\t-n\tbroken-feature'
  assert_file_contains "$log" $'-c\t'"$worktree_real"$'\tvim'
}

test_bare_positional_worktree_supports_shell_equals_command() {
  local project fake_bin log worktree_real

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  git --git-dir "$project/.git" branch provisional-venues main
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"

  EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$TEST_TMPDIR" -p "$project" -sh='ADDR=:8081 go run ./cmd/web' -- provisional-venues

  worktree_real="$(cd "$project/.worktrees/provisional-venues" && pwd -P)"
  assert_file_contains "$log" $'new-session\t-d\t-P\t-F\t#{session_id}\t#{session_name}\t#{window_id}\t#{pane_id}\t-s\tproject\t-n\tprovisional-venues'
  assert_file_contains "$log" $'split-window\t-h\t-P\t-F\t#{pane_id}\t-t\t%1\t-c\t'"$worktree_real"$'\tcodex'
  assert_file_contains "$log" $'split-window\t-v\t-P\t-F\t#{pane_id}\t-t\t%2\t-c\t'"$worktree_real"$'\tADDR=:8081 go run ./cmd/web'
}

test_shell_option_skips_existing_window_reuse() {
  local project fake_bin log worktree_real panes sessions

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  git --git-dir "$project/.git" branch provisional-venues main
  git --git-dir "$project/.git" worktree add "$project/.worktrees/provisional-venues" provisional-venues >/dev/null 2>&1
  worktree_real="$(cd "$project/.worktrees/provisional-venues" && pwd -P)"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"
  panes=$'@8\t'"$worktree_real"$'\n'
  sessions=$'project\t'"$worktree_real"$'\n'

  EDITOR=vim TAW_FAKE_TMUX_SESSIONS="$sessions" TAW_FAKE_TMUX_PANES="$panes" \
    TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$TEST_TMPDIR" -p "$project" -sh='ADDR=:8081 go run ./cmd/web' -- provisional-venues

  assert_file_contains "$log" $'list-sessions\t-F\t#{session_id}\t#{session_name}\t#{session_path}'
  assert_file_not_contains "$log" $'list-panes\t'
  assert_file_contains "$log" $'new-window\t-d\t-P\t-F\t#{window_id} #{pane_id}\t-t\t$1:\t-n\tprovisional-venues\t-c\t'"$worktree_real"$'\tvim'
  assert_file_contains "$log" $'split-window\t-v\t-P\t-F\t#{pane_id}\t-t\t%2\t-c\t'"$worktree_real"$'\tADDR=:8081 go run ./cmd/web'
}

test_positional_base_ref_overrides_named_branch() {
  local project fake_bin log expected actual

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"

  if EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$TEST_TMPDIR" -p "$project" -b main feature-x develop; then
    fail "expected -b with positional operands to fail"
  fi

  [[ ! -f "$log" ]] || fail "expected tmux not to run after invalid bare operands"
}

test_supports_bare_child_not_named_git() {
  local project fake_bin log branch

  project="$(make_bare_wrapper "$TEST_TMPDIR" ".bare")"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"

  EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$TEST_TMPDIR" -p "$project" feature-x develop

  branch="$(git -C "$project/.worktrees/feature-x" branch --show-current)"
  assert_eq "feature-x" "$branch" "expected worktree branch from .bare repo"
  assert_file_contains "$log" $'new-session\t-d\t-P\t-F\t#{session_id}\t#{session_name}\t#{window_id}\t#{pane_id}\t-s\tproject\t-n\tfeature-x'
}

test_conventional_bare_clone_places_worktrees_outside_git_dir() {
  local bare project fake_bin log branch worktree_real expected actual

  bare="$(make_conventional_bare_clone "$TEST_TMPDIR" "project")"
  project="${bare%.git}"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"

  EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$TEST_TMPDIR" -p "$bare" feature-x develop

  branch="$(git -C "$project/.worktrees/feature-x" branch --show-current)"
  expected="$(git --git-dir "$bare" rev-parse develop)"
  actual="$(git -C "$project/.worktrees/feature-x" rev-parse HEAD)"
  worktree_real="$(cd "$project/.worktrees/feature-x" && pwd -P)"
  assert_eq "feature-x" "$branch" "expected conventional bare clone worktree branch"
  assert_eq "$expected" "$actual" "expected worktree branch to start from positional base ref"
  assert_not_exists "$bare/feature-x"
  assert_file_contains "$log" $'new-session\t-d\t-P\t-F\t#{session_id}\t#{session_name}\t#{window_id}\t#{pane_id}\t-s\tproject\t-n\tfeature-x'
  assert_file_contains "$log" $'-c\t'"$worktree_real"$'\tvim'
}

test_conventional_bare_worktree_detection_keeps_project_root() {
  local bare project fake_bin log branch worktree_real

  bare="$(make_conventional_bare_clone "$TEST_TMPDIR" "project")"
  project="${bare%.git}"
  git --git-dir "$bare" worktree add "$project/.worktrees/main" main >/dev/null 2>&1
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"

  EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$project/.worktrees/main" feature-x develop

  branch="$(git -C "$project/.worktrees/feature-x" branch --show-current)"
  worktree_real="$(cd "$project/.worktrees/feature-x" && pwd -P)"
  assert_eq "feature-x" "$branch" "expected detected conventional bare project root"
  assert_not_exists "$TEST_TMPDIR/feature-x"
  assert_file_contains "$log" $'new-session\t-d\t-P\t-F\t#{session_id}\t#{session_name}\t#{window_id}\t#{pane_id}\t-s\tproject\t-n\tfeature-x'
  assert_file_contains "$log" $'-c\t'"$worktree_real"$'\tvim'
}

test_bare_project_without_worktree_opens_default_branch_worktree() {
  local project fake_bin log branch worktree_real no_fzf_path

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  no_fzf_path="$(make_path_without_fzf "$fake_bin")"
  log="$TEST_TMPDIR/tmux.log"

  EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" \
    run_taw "$TEST_TMPDIR" -p "$project"

  branch="$(git -C "$project/.worktrees/main" branch --show-current)"
  worktree_real="$(cd "$project/.worktrees/main" && pwd -P)"
  assert_eq "main" "$branch" "expected bare project default branch worktree"
  assert_file_contains "$log" $'new-session\t-d\t-P\t-F\t#{session_id}\t#{session_name}\t#{window_id}\t#{pane_id}\t-s\tproject\t-n\tmain'
  assert_file_contains "$log" $'set-window-option\t-t\t@1\tallow-rename\toff'
  assert_file_contains "$log" $'rename-window\t-t\t@1\tmain'
  assert_file_contains "$log" $'-c\t'"$worktree_real"$'\tvim'
}

test_bare_default_worktree_window_is_reused() {
  local project fake_bin log fzf_log branch worktree_real panes display sessions

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  git --git-dir "$project/.git" worktree add "$project/.worktrees/main" main >/dev/null 2>&1
  worktree_real="$(cd "$project/.worktrees/main" && pwd -P)"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  make_fake_fzf "$fake_bin"
  log="$TEST_TMPDIR/tmux.log"
  fzf_log="$TEST_TMPDIR/fzf-input.log"
  panes=$'@8\t%8\t'"$worktree_real"$'\n'
  sessions=$'project\t'"$worktree_real"$'\n'

  EDITOR=vim TAW_FAKE_FZF_MATCH='main [worktree]' \
    TAW_FZF_INPUT_LOG="$fzf_log" \
    TAW_FAKE_TMUX_SESSIONS="$sessions" TAW_FAKE_TMUX_PANES="$panes" \
    TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$TEST_TMPDIR" -p "$project"

  display="$(grep -F $'main [worktree]\tworktree' "$fzf_log" | cut -f1)"
  assert_eq "main [worktree]" "$display" "expected fzf worktree display to omit path"
  branch="$(git -C "$project/.worktrees/main" branch --show-current)"
  assert_eq "main" "$branch" "expected bare project default branch worktree"
  assert_file_contains "$log" $'list-sessions\t-F\t#{session_id}\t#{session_name}\t#{session_path}'
  assert_file_contains "$log" $'list-panes\t-s\t-t\t$1:\t-F\t#{window_id}\t#{pane_id}\t#{pane_current_path}'
  assert_file_contains "$log" $'select-window\t-t\t@8'
  assert_file_contains "$log" $'select-pane\t-t\t%8'
  assert_file_contains "$log" $'attach-session\t-t\t$1'
  assert_file_not_contains "$log" $'new-window\t'
  assert_file_not_contains "$log" $'new-session\t'
  assert_file_not_contains "$log" $'split-window\t'
}

test_bare_project_without_default_falls_back_to_master() {
  local project fake_bin log branch worktree_real no_fzf_path

  project="$(make_bare_wrapper "$TEST_TMPDIR" ".git" "master")"
  git --git-dir "$project/.git" symbolic-ref HEAD refs/heads/missing
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  no_fzf_path="$(make_path_without_fzf "$fake_bin")"
  log="$TEST_TMPDIR/tmux.log"

  EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    TAW_RUN_PATH="$no_fzf_path" \
    run_taw "$TEST_TMPDIR" -p "$project"

  branch="$(git -C "$project/.worktrees/master" branch --show-current)"
  worktree_real="$(cd "$project/.worktrees/master" && pwd -P)"
  assert_eq "master" "$branch" "expected bare project to fall back to master"
  assert_file_contains "$log" $'new-session\t-d\t-P\t-F\t#{session_id}\t#{session_name}\t#{window_id}\t#{pane_id}\t-s\tproject\t-n\tmaster'
  assert_file_contains "$log" $'-c\t'"$worktree_real"$'\tvim'
}

test_bare_project_origin_head_only_creates_local_default_worktree() {
  local project fake_bin log branch worktree_real no_fzf_path

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  git --git-dir "$project/.git" update-ref refs/remotes/origin/main refs/heads/main
  git --git-dir "$project/.git" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
  git --git-dir "$project/.git" symbolic-ref HEAD refs/heads/missing
  git --git-dir "$project/.git" update-ref -d refs/heads/main
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  no_fzf_path="$(make_path_without_fzf "$fake_bin")"
  log="$TEST_TMPDIR/tmux.log"

  EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" \
    run_taw "$TEST_TMPDIR" -p "$project"

  branch="$(git -C "$project/.worktrees/main" branch --show-current)"
  worktree_real="$(cd "$project/.worktrees/main" && pwd -P)"
  assert_eq "main" "$branch" "expected origin/HEAD-only repo to create local main worktree"
  assert_file_contains "$log" $'new-session\t-d\t-P\t-F\t#{session_id}\t#{session_name}\t#{window_id}\t#{pane_id}\t-s\tproject\t-n\tmain'
  assert_file_contains "$log" $'-c\t'"$worktree_real"$'\tvim'
}

test_bare_picker_lists_deduped_branches() {
  local project fake_bin log fzf_log main_count remote_count

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  git --git-dir "$project/.git" worktree add "$project/.worktrees/main" main >/dev/null 2>&1
  git --git-dir "$project/.git" update-ref refs/remotes/origin/main refs/heads/develop
  git --git-dir "$project/.git" update-ref refs/remotes/upstream/remote-only refs/heads/main
  git --git-dir "$project/.git" update-ref refs/remotes/origin/remote-only refs/heads/develop
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  make_fake_fzf "$fake_bin"
  log="$TEST_TMPDIR/tmux.log"
  fzf_log="$TEST_TMPDIR/fzf-input.log"

  EDITOR=vim TAW_FAKE_FZF_MATCH=$'remote-only\tbranch' TAW_FZF_INPUT_LOG="$fzf_log" \
    TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$TEST_TMPDIR" -p "$project"

  main_count="$(grep -F $'main [worktree]\tworktree\tmain\tmain\t' "$fzf_log" | wc -l | tr -d ' ')"
  remote_count="$(grep -F $'remote-only\tbranch' "$fzf_log" | wc -l | tr -d ' ')"
  assert_eq "1" "$main_count" "expected worktree main to suppress branch duplicates"
  assert_eq "1" "$remote_count" "expected duplicate remote branches to dedupe to one picker row"
  assert_file_contains "$fzf_log" $'remote-only\tbranch\tremote-only\torigin/remote-only\t'
  assert_file_not_contains "$fzf_log" $'origin/main'
  assert_file_not_contains "$fzf_log" $'upstream/remote-only'
}

test_bare_picker_remote_branch_creates_local_worktree() {
  local project fake_bin log branch worktree_real expected actual

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  git --git-dir "$project/.git" worktree add "$project/.worktrees/main" main >/dev/null 2>&1
  git --git-dir "$project/.git" update-ref refs/remotes/origin/feature/remote refs/heads/develop
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  make_fake_fzf "$fake_bin"
  log="$TEST_TMPDIR/tmux.log"

  EDITOR=vim TAW_FAKE_FZF_MATCH=$'feature/remote\tbranch' \
    TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$TEST_TMPDIR" -p "$project"

  branch="$(git -C "$project/.worktrees/feature/remote" branch --show-current)"
  worktree_real="$(cd "$project/.worktrees/feature/remote" && pwd -P)"
  expected="$(git --git-dir "$project/.git" rev-parse refs/remotes/origin/feature/remote)"
  actual="$(git -C "$project/.worktrees/feature/remote" rev-parse HEAD)"
  assert_eq "feature/remote" "$branch" "expected remote picker branch to create local branch"
  assert_eq "$expected" "$actual" "expected remote picker branch to start from remote ref"
  assert_file_contains "$log" $'new-session\t-d\t-P\t-F\t#{session_id}\t#{session_name}\t#{window_id}\t#{pane_id}\t-s\tproject\t-n\tremote'
  assert_file_contains "$log" $'-c\t'"$worktree_real"$'\tvim'
}

test_bare_picker_prefers_origin_for_duplicate_remotes() {
  local project fake_bin log expected actual

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  git --git-dir "$project/.git" worktree add "$project/.worktrees/main" main >/dev/null 2>&1
  git --git-dir "$project/.git" update-ref refs/remotes/upstream/remote-choice refs/heads/main
  git --git-dir "$project/.git" update-ref refs/remotes/origin/remote-choice refs/heads/develop
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  make_fake_fzf "$fake_bin"
  log="$TEST_TMPDIR/tmux.log"

  EDITOR=vim TAW_FAKE_FZF_MATCH=$'remote-choice\tbranch' \
    TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$TEST_TMPDIR" -p "$project"

  expected="$(git --git-dir "$project/.git" rev-parse refs/remotes/origin/remote-choice)"
  actual="$(git -C "$project/.worktrees/remote-choice" rev-parse HEAD)"
  assert_eq "$expected" "$actual" "expected duplicate remote branch to prefer origin"
}

test_bare_picker_strips_slash_remote_names() {
  local project fake_bin log expected actual branch worktree_real

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  git --git-dir "$project/.git" worktree add "$project/.worktrees/main" main >/dev/null 2>&1
  git --git-dir "$project/.git" remote add "foo/bar" "$TEST_TMPDIR/remote.git"
  git --git-dir "$project/.git" update-ref refs/remotes/foo/bar/topic refs/heads/develop
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  make_fake_fzf "$fake_bin"
  log="$TEST_TMPDIR/tmux.log"

  EDITOR=vim TAW_FAKE_FZF_MATCH=$'topic\tbranch' \
    TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$TEST_TMPDIR" -p "$project"

  branch="$(git -C "$project/.worktrees/topic" branch --show-current)"
  worktree_real="$(cd "$project/.worktrees/topic" && pwd -P)"
  expected="$(git --git-dir "$project/.git" rev-parse refs/remotes/foo/bar/topic)"
  actual="$(git -C "$project/.worktrees/topic" rev-parse HEAD)"
  assert_eq "topic" "$branch" "expected slash remote name to be stripped from branch"
  assert_eq "$expected" "$actual" "expected slash remote branch to start from full remote ref"
  assert_not_exists "$project/bar/topic"
  assert_file_contains "$log" $'new-session\t-d\t-P\t-F\t#{session_id}\t#{session_name}\t#{window_id}\t#{pane_id}\t-s\tproject\t-n\ttopic'
  assert_file_contains "$log" $'-c\t'"$worktree_real"$'\tvim'
}

test_bare_picker_cancel_returns_success_without_tmux() {
  local project fake_bin log

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  git --git-dir "$project/.git" worktree add "$project/.worktrees/main" main >/dev/null 2>&1
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  make_fake_fzf "$fake_bin"
  log="$TEST_TMPDIR/tmux.log"

  EDITOR=vim TAW_FAKE_FZF_CANCEL=1 TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$TEST_TMPDIR" -p "$project"
  [[ ! -f "$log" ]] || fail "expected tmux not to run after fzf cancellation"
}

test_bare_picker_without_fzf_falls_back_to_default_worktree() {
  local project fake_bin log branch worktree_real no_fzf_path

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  git --git-dir "$project/.git" worktree add "$project/.worktrees/main" main >/dev/null 2>&1
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  no_fzf_path="$(make_path_without_fzf "$fake_bin")"
  log="$TEST_TMPDIR/tmux.log"

  EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" \
    run_taw "$TEST_TMPDIR" -p "$project"

  branch="$(git -C "$project/.worktrees/main" branch --show-current)"
  worktree_real="$(cd "$project/.worktrees/main" && pwd -P)"
  assert_eq "main" "$branch" "expected bare picker fallback to open default worktree"
  assert_file_contains "$log" $'new-session\t-d\t-P\t-F\t#{session_id}\t#{session_name}\t#{window_id}\t#{pane_id}\t-s\tproject\t-n\tmain'
  assert_file_contains "$log" $'-c\t'"$worktree_real"$'\tvim'
}

test_bare_picker_error_fails_without_tmux() {
  local project fake_bin log

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  git --git-dir "$project/.git" worktree add "$project/.worktrees/main" main >/dev/null 2>&1
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  make_fake_fzf "$fake_bin"
  log="$TEST_TMPDIR/tmux.log"

  if EDITOR=vim TAW_FAKE_FZF_INDEX=99 TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$TEST_TMPDIR" -p "$project"; then
    fail "expected picker error to fail"
  fi
  [[ ! -f "$log" ]] || fail "expected tmux not to run after picker error"
}

test_bare_remote_only_branch_sets_upstream_tracking() {
  local project fake_bin log branch upstream_ref worktree_real

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  git --git-dir "$project/.git" update-ref refs/remotes/origin/feature/foo refs/heads/develop
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"

  EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$TEST_TMPDIR" -p "$project" -b feature/foo

  branch="$(git -C "$project/.worktrees/feature/foo" branch --show-current)"
  upstream_ref="$(git -C "$project/.worktrees/feature/foo" rev-parse --abbrev-ref --symbolic-full-name @{u})"
  worktree_real="$(cd "$project/.worktrees/feature/foo" && pwd -P)"
  assert_eq "feature/foo" "$branch" "expected bare remote-only branch to create local branch"
  assert_eq "origin/feature/foo" "$upstream_ref" "expected bare remote-only branch tracking"
  assert_file_contains "$log" $'new-session\t-d\t-P\t-F\t#{session_id}\t#{session_name}\t#{window_id}\t#{pane_id}\t-s\tproject\t-n\tfoo'
  assert_file_contains "$log" $'-c\t'"$worktree_real"$'\tvim'
}

test_bare_zero_worktree_uses_head_branch_when_no_refs_exist() {
  local project fake_bin log branch worktree_real

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  git --git-dir "$project/.git" update-ref -d refs/heads/main
  git --git-dir "$project/.git" update-ref -d refs/heads/develop
  git --git-dir "$project/.git" symbolic-ref HEAD refs/heads/missing
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"

  EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$TEST_TMPDIR" -p "$project"

  branch="$(git -C "$project/.worktrees/missing" branch --show-current)"
  worktree_real="$(cd "$project/.worktrees/missing" && pwd -P)"
  assert_eq "missing" "$branch" "expected orphan worktree branch to use HEAD symbolic-ref"
  assert_file_contains "$log" $'new-session\t-d\t-P\t-F\t#{session_id}\t#{session_name}\t#{window_id}\t#{pane_id}\t-s\tproject\t-n\tmissing'
  assert_file_contains "$log" $'-c\t'"$worktree_real"$'\tvim'
}

test_bare_zero_worktree_fails_when_refs_exist_but_no_default_resolves() {
  local project fake_bin log

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  git --git-dir "$project/.git" branch topic develop
  git --git-dir "$project/.git" update-ref -d refs/heads/main
  git --git-dir "$project/.git" update-ref -d refs/heads/develop
  git --git-dir "$project/.git" symbolic-ref HEAD refs/heads/missing
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"

  if EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$TEST_TMPDIR" -p "$project"; then
    fail "expected bare project with unresolved refs to fail"
  fi

  assert_not_exists "$project/.worktrees/missing"
  [[ ! -f "$log" ]] || fail "expected tmux not to run after unresolved bare default"
}

test_bare_zero_worktree_fails_when_only_tag_ref_exists() {
  local project fake_bin log

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  git --git-dir "$project/.git" tag release main
  git --git-dir "$project/.git" update-ref -d refs/heads/main
  git --git-dir "$project/.git" update-ref -d refs/heads/develop
  git --git-dir "$project/.git" symbolic-ref HEAD refs/heads/missing
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"

  if EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$TEST_TMPDIR" -p "$project"; then
    fail "expected bare project with only a tag ref to fail"
  fi

  assert_not_exists "$project/.worktrees/missing"
  [[ ! -f "$log" ]] || fail "expected tmux not to run after tag-only bare default"
}

test_bare_project_named_branch_without_worktree_opens_branch_worktree() {
  local project fake_bin log branch worktree_real

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"

  EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$TEST_TMPDIR" -p "$project" -b develop

  branch="$(git -C "$project/.worktrees/develop" branch --show-current)"
  worktree_real="$(cd "$project/.worktrees/develop" && pwd -P)"
  assert_eq "develop" "$branch" "expected bare -b to open branch worktree"
  assert_file_contains "$log" $'new-session\t-d\t-P\t-F\t#{session_id}\t#{session_name}\t#{window_id}\t#{pane_id}\t-s\tproject\t-n\tdevelop'
  assert_file_contains "$log" $'-c\t'"$worktree_real"$'\tvim'
}

test_explicit_bare_worktree_subdir_with_branch_opens_project_root_worktree() {
  local project fake_bin log branch worktree_real

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  git --git-dir "$project/.git" worktree add "$project/.worktrees/main" main >/dev/null 2>&1
  git --git-dir "$project/.git" branch feature-x main
  mkdir -p "$project/.worktrees/main/src"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"

  EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$TEST_TMPDIR" -p "$project/.worktrees/main/src" -b feature-x

  branch="$(git -C "$project/.worktrees/feature-x" branch --show-current)"
  worktree_real="$(cd "$project/.worktrees/feature-x" && pwd -P)"
  assert_eq "feature-x" "$branch" "expected bare worktree subdir -b to target project root"
  assert_not_exists "$project/.worktrees/main/src/feature-x"
  assert_file_contains "$log" $'new-session\t-d\t-P\t-F\t#{session_id}\t#{session_name}\t#{window_id}\t#{pane_id}\t-s\tproject\t-n\tfeature-x'
  assert_file_contains "$log" $'-c\t'"$worktree_real"$'\tvim'
}

test_explicit_bare_worktree_subdir_without_operands_opens_containing_worktree_root() {
  local project fake_bin log branch worktree_real

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  git --git-dir "$project/.git" worktree add "$project/.worktrees/develop" develop >/dev/null 2>&1
  mkdir -p "$project/.worktrees/develop/src"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"

  EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$TEST_TMPDIR" -p "$project/.worktrees/develop/src"

  branch="$(git -C "$project/.worktrees/develop" branch --show-current)"
  worktree_real="$(cd "$project/.worktrees/develop" && pwd -P)"
  assert_eq "develop" "$branch" "expected explicit bare subdir to open containing worktree"
  assert_file_contains "$log" $'new-session\t-d\t-P\t-F\t#{session_id}\t#{session_name}\t#{window_id}\t#{pane_id}\t-s\tproject\t-n\tdevelop\t-c\t'"$worktree_real"$'\tvim'
  assert_file_not_contains "$log" $'worktree\tadd'
}

test_explicit_bare_worktree_root_without_operands_opens_containing_worktree_root() {
  local project fake_bin log branch worktree_real

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  git --git-dir "$project/.git" worktree add "$project/.worktrees/develop" develop >/dev/null 2>&1
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"

  EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$TEST_TMPDIR" -p "$project/.worktrees/develop"

  branch="$(git -C "$project/.worktrees/develop" branch --show-current)"
  worktree_real="$(cd "$project/.worktrees/develop" && pwd -P)"
  assert_eq "develop" "$branch" "expected explicit bare worktree root to open itself"
  assert_file_contains "$log" $'new-session\t-d\t-P\t-F\t#{session_id}\t#{session_name}\t#{window_id}\t#{pane_id}\t-s\tproject\t-n\tdevelop\t-c\t'"$worktree_real"$'\tvim'
  assert_file_not_contains "$log" $'worktree\tadd'
}

test_bare_project_reuses_existing_default_branch_worktree_when_confirmed() {
  local project fake_bin log branch existing_real

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  git --git-dir "$project/.git" worktree add "$TEST_TMPDIR/main-existing" main >/dev/null 2>&1
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  make_fake_fzf "$fake_bin"
  log="$TEST_TMPDIR/tmux.log"

  printf 'y\n' | EDITOR=vim TAW_FAKE_FZF_MATCH='main [worktree]' \
    TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$TEST_TMPDIR" -p "$project"

  branch="$(git -C "$TEST_TMPDIR/main-existing" branch --show-current)"
  existing_real="$(cd "$TEST_TMPDIR/main-existing" && pwd -P)"
  assert_eq "main" "$branch" "expected accepted existing worktree to stay on main"
  assert_not_exists "$project/.worktrees/main"
  assert_file_contains "$log" $'new-session\t-d\t-P\t-F\t#{session_id}\t#{session_name}\t#{window_id}\t#{pane_id}\t-s\tproject\t-n\tmain-existing'
  assert_file_contains "$log" $'-c\t'"$existing_real"$'\tvim'
}

test_bare_project_branch_with_slash_creates_nested_worktree() {
  local project fake_bin log branch worktree_real

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  git --git-dir "$project/.git" branch "feature/nested" main
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"

  EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$TEST_TMPDIR" -p "$project" -b "feature/nested"

  branch="$(git -C "$project/.worktrees/feature/nested" branch --show-current)"
  worktree_real="$(cd "$project/.worktrees/feature/nested" && pwd -P)"
  assert_eq "feature/nested" "$branch" "expected branch with slash to create nested worktree"
  assert_file_contains "$log" $'new-session\t-d\t-P\t-F\t#{session_id}\t#{session_name}\t#{window_id}\t#{pane_id}\t-s\tproject\t-n\tnested'
  assert_file_contains "$log" $'-c\t'"$worktree_real"$'\tvim'
}

test_bare_project_local_slash_base_ref_stays_local() {
  local project fake_bin log branch expected actual worktree_real

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  git --git-dir "$project/.git" branch "feature/base" main
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"

  EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$TEST_TMPDIR" -p "$project" fix/broken-feature "feature/base"

  branch="$(git -C "$project/.worktrees/fix/broken-feature" branch --show-current)"
  expected="$(git --git-dir "$project/.git" rev-parse feature/base)"
  actual="$(git -C "$project/.worktrees/fix/broken-feature" rev-parse HEAD)"
  worktree_real="$(cd "$project/.worktrees/fix/broken-feature" && pwd -P)"
  assert_eq "fix/broken-feature" "$branch" "expected local slash base to create the requested path branch"
  assert_eq "$expected" "$actual" "expected local slash base to be used as the start point"
  assert_file_contains "$log" $'new-session\t-d\t-P\t-F\t#{session_id}\t#{session_name}\t#{window_id}\t#{pane_id}\t-s\tproject\t-n\tbroken-feature'
  assert_file_contains "$log" $'-c\t'"$worktree_real"$'\tvim'
}

test_bare_project_invalid_branch_does_not_create_parent_dirs() {
  local project fake_bin log

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"

  if EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$TEST_TMPDIR" -p "$project" -b "../outside/foo"; then
    fail "expected invalid bare branch to fail"
  fi
  assert_not_exists "$TEST_TMPDIR/outside"
  [[ ! -f "$log" ]] || fail "expected tmux not to run after invalid bare branch"
}

test_bare_project_relative_worktree_escape_is_rejected() {
  local project fake_bin log

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"

  if EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$TEST_TMPDIR" -p "$project" "../outside/foo"; then
    fail "expected relative bare worktree escape to fail"
  fi
  assert_not_exists "$TEST_TMPDIR/outside"
  [[ ! -f "$log" ]] || fail "expected tmux not to run after escaping bare worktree path"
}

test_bare_project_absolute_worktree_path_must_stay_under_wrapper() {
  local project fake_bin log branch absolute_under outside_target worktree_real

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"
  absolute_under="$project/.worktrees/fix/broken-feature"
  outside_target="$TEST_TMPDIR/project-other/fix/broken-feature"

  EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$TEST_TMPDIR" -p "$project" "$absolute_under"
  branch="$(git -C "$absolute_under" branch --show-current)"
  worktree_real="$(cd "$absolute_under" && pwd -P)"
  assert_eq "fix/broken-feature" "$branch" "expected absolute path under wrapper to derive relative branch"
  assert_file_contains "$log" $'-c\t'"$worktree_real"$'\tvim'

  rm -f "$log"
  if EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$TEST_TMPDIR" -p "$project" "$outside_target"; then
    fail "expected absolute bare worktree path outside wrapper to fail"
  fi
  assert_not_exists "$outside_target"
  [[ ! -f "$log" ]] || fail "expected tmux not to run after absolute worktree path outside wrapper"
}

test_bare_project_dot_segment_worktree_paths_are_rejected() {
  local project fake_bin log input log_name

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"

  for input in "../outside/foo" "fix/../broken-feature" "fix/./broken-feature"; do
    log_name="${input//[^[:alnum:]]/_}"
    log="$TEST_TMPDIR/tmux-$log_name.log"
    if EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
      run_taw "$TEST_TMPDIR" -p "$project" "$input"; then
      fail "expected bare worktree path with dot segment to fail: $input"
    fi
    assert_not_exists "$project/broken-feature"
    assert_not_exists "$project/fix"
    assert_not_exists "$TEST_TMPDIR/outside"
    [[ ! -f "$log" ]] || fail "expected tmux not to run after dot-segment worktree path: $input"
  done
}

test_normal_repo_checks_out_branch_from_single_positional() {
  local repo worktree_real fake_bin log branch

  repo="$TEST_TMPDIR/repo"
  make_git_repo "$repo"
  git -C "$repo" branch feature-x develop
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"

  EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$repo" -p "$repo" feature-x

  worktree_real="$(cd "$repo/.worktrees/feature-x" && pwd -P)"
  branch="$(git -C "$worktree_real" branch --show-current)"
  assert_eq "feature-x" "$branch" "expected single positional to open a managed worktree"
  assert_eq "main" "$(git -C "$repo" branch --show-current)" \
    "expected the primary worktree branch to remain unchanged"
  assert_file_contains "$log" $'new-session\t-d\t-P\t-F\t#{session_id}\t#{session_name}\t#{window_id}\t#{pane_id}\t-s\trepo\t-n\tfeature-x\t-c\t'"$worktree_real"$'\tvim'
}

test_normal_repo_single_positional_tracks_remote_only_branch() {
  local repo worktree fake_bin log upstream_ref

  repo="$TEST_TMPDIR/repo"
  make_git_repo "$repo"
  git -C "$repo" remote add origin "$TEST_TMPDIR/origin.git"
  git -C "$repo" update-ref refs/remotes/origin/feature/foo refs/heads/develop
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"

  EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$repo" -p "$repo" feature/foo

  worktree="$repo/.worktrees/feature/foo"
  upstream_ref="$(git -C "$worktree" rev-parse --abbrev-ref --symbolic-full-name @{u})"
  assert_eq "feature/foo" "$(git -C "$worktree" branch --show-current)" \
    "expected positional remote-only branch to create a local branch"
  assert_eq "origin/feature/foo" "$upstream_ref" \
    "expected positional remote-only branch tracking"
  assert_eq "$(git -C "$repo" rev-parse develop)" "$(git -C "$worktree" rev-parse HEAD)" \
    "expected positional branch to start from the remote commit"
  assert_eq "main" "$(git -C "$repo" branch --show-current)" \
    "expected the primary worktree branch to remain unchanged"
}

test_normal_repo_positional_remote_branch_preserves_narrow_fetch_refspec() {
  local repo worktree fake_bin log refspec

  repo="$TEST_TMPDIR/repo"
  make_git_repo "$repo"
  git -C "$repo" remote add origin "$TEST_TMPDIR/origin.git"
  git -C "$repo" config --unset-all remote.origin.fetch
  refspec='+refs/heads/feature/foo:refs/remotes/origin/feature/foo'
  git -C "$repo" config --add remote.origin.fetch "$refspec"
  git -C "$repo" update-ref refs/remotes/origin/feature/foo refs/heads/develop
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"

  EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$repo" -p "$repo" feature/foo

  worktree="$repo/.worktrees/feature/foo"
  assert_eq "$refspec" "$(git -C "$repo" config --get-all remote.origin.fetch)" \
    "expected a narrow fetch refspec to remain unchanged"
  assert_eq "origin/feature/foo" \
    "$(git -C "$worktree" rev-parse --abbrev-ref --symbolic-full-name @{u})" \
    "expected the new branch to track the remote branch"
}

test_normal_repo_positional_remote_branch_preserves_multiple_fetch_refspecs() {
  local repo worktree fake_bin log before

  repo="$TEST_TMPDIR/repo"
  make_git_repo "$repo"
  git -C "$repo" remote add origin "$TEST_TMPDIR/origin.git"
  git -C "$repo" config --unset-all remote.origin.fetch
  git -C "$repo" config --add remote.origin.fetch \
    '+refs/heads/feature/foo:refs/remotes/origin/feature/foo'
  git -C "$repo" config --add remote.origin.fetch \
    '+refs/heads/release/*:refs/remotes/origin/release/*'
  before="$(git -C "$repo" config --get-all remote.origin.fetch)"
  git -C "$repo" update-ref refs/remotes/origin/feature/foo refs/heads/develop
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"

  EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$repo" -p "$repo" feature/foo

  worktree="$repo/.worktrees/feature/foo"
  assert_eq "$before" "$(git -C "$repo" config --get-all remote.origin.fetch)" \
    "expected multiple fetch refspecs to remain unchanged"
  assert_eq "origin/feature/foo" \
    "$(git -C "$worktree" rev-parse --abbrev-ref --symbolic-full-name @{u})" \
    "expected the new branch to track the remote branch"
  assert_file_contains "$log" $'new-session\t'
}

test_normal_repo_positional_remote_branch_adds_missing_fetch_refspec() {
  local repo fake_bin log

  repo="$TEST_TMPDIR/repo"
  make_git_repo "$repo"
  git -C "$repo" remote add origin "$TEST_TMPDIR/origin.git"
  git -C "$repo" config --unset-all remote.origin.fetch
  git -C "$repo" update-ref refs/remotes/origin/feature/foo refs/heads/develop
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"

  EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$repo" -p "$repo" feature/foo

  assert_eq '+refs/heads/*:refs/remotes/origin/*' \
    "$(git -C "$repo" config --get-all remote.origin.fetch)" \
    "expected a missing fetch refspec to receive the default"
  assert_eq "origin/feature/foo" \
    "$(git -C "$repo/.worktrees/feature/foo" rev-parse \
      --abbrev-ref --symbolic-full-name @{u})" \
    "expected the new branch to track the remote branch"
}

test_normal_repo_remote_prefixed_positional_uses_resolved_branch() {
  local repo worktree fake_bin log output upstream_ref

  repo="$TEST_TMPDIR/repo"
  make_git_repo "$repo"
  git -C "$repo" remote add origin "$TEST_TMPDIR/origin.git"
  git -C "$repo" update-ref refs/remotes/origin/feature/foo refs/heads/develop
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"

  output="$(
    EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
      run_taw "$repo" -p "$repo" origin/feature/foo 2>&1
  )"

  worktree="$repo/.worktrees/feature/foo"
  upstream_ref="$(git -C "$worktree" rev-parse --abbrev-ref --symbolic-full-name @{u})"
  assert_eq "feature/foo" "$(git -C "$worktree" branch --show-current)" \
    "expected the resolved remote branch name locally"
  assert_eq "origin/feature/foo" "$upstream_ref" \
    "expected the resolved local branch to track origin"
  assert_eq "$(git -C "$repo" rev-parse develop)" "$(git -C "$worktree" rev-parse HEAD)" \
    "expected the resolved local branch to start from the remote commit"
  assert_not_exists "$repo/.worktrees/origin/feature/foo"
  if git -C "$repo" show-ref --verify --quiet refs/heads/origin/feature/foo; then
    fail "expected no remote-prefixed local branch"
  fi
  assert_string_not_contains "$output" "ambiguous"
}

test_normal_repo_positional_missing_configured_remote_ref_fails() {
  local repo fake_bin log

  repo="$TEST_TMPDIR/repo"
  make_git_repo "$repo"
  git -C "$repo" remote add origin "$TEST_TMPDIR/origin.git"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"

  if EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$repo" -p "$repo" origin/topic; then
    fail "expected missing configured remote ref to fail"
  fi

  assert_not_exists "$repo/.worktrees/origin/topic"
  if git -C "$repo" show-ref --verify --quiet refs/heads/origin/topic; then
    fail "expected no local branch shadowing a configured remote"
  fi
  [[ ! -f "$log" ]] || fail "expected tmux not to run after missing remote ref"
}

test_normal_repo_positional_rejects_refs_remotes_prefix() {
  local repo fake_bin log

  repo="$TEST_TMPDIR/repo"
  make_git_repo "$repo"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"

  if EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$repo" -p "$repo" refs/remotes/origin/topic; then
    fail "expected refs/remotes positional input to fail"
  fi

  assert_not_exists "$repo/.worktrees/refs/remotes/origin/topic"
  if git -C "$repo" show-ref --verify --quiet refs/heads/refs/remotes/origin/topic; then
    fail "expected no local branch for refs/remotes positional input"
  fi
  [[ ! -f "$log" ]] || fail "expected tmux not to run after rejected remote syntax"
}

test_normal_repo_positional_unresolved_slash_branch_uses_head() {
  local repo worktree fake_bin log

  repo="$TEST_TMPDIR/repo"
  make_git_repo "$repo"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"

  EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$repo" -p "$repo" feature/new

  worktree="$repo/.worktrees/feature/new"
  assert_eq "feature/new" "$(git -C "$worktree" branch --show-current)" \
    "expected an ordinary unresolved slash branch to remain creatable"
  assert_eq "$(git -C "$repo" rev-parse main)" "$(git -C "$worktree" rev-parse HEAD)" \
    "expected an ordinary unresolved slash branch to start from HEAD"
}

test_normal_repo_rejects_two_positional_operands() {
  local repo fake_bin log worktree

  repo="$TEST_TMPDIR/repo"
  make_git_repo "$repo"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"

  EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$repo" -p "$repo" feature-x develop

  worktree="$repo/.worktrees/feature-x"
  assert_eq "feature-x" "$(git -C "$worktree" branch --show-current)" \
    "expected the first positional to name the worktree branch"
  assert_eq "$(git -C "$repo" rev-parse develop)" "$(git -C "$worktree" rev-parse HEAD)" \
    "expected the second positional to provide the base ref"
}

test_rejects_unrelated_git_repo_at_worktree_path() {
  local project fake_bin log unrelated

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  unrelated="$project/.worktrees/feature-x"
  make_git_repo "$unrelated"
  git -C "$unrelated" checkout -qb feature-x
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"

  if EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$TEST_TMPDIR" -p "$project" feature-x; then
    fail "expected unrelated git repo at worktree path to fail"
  fi
  [[ ! -f "$log" ]] || fail "expected tmux not to run for unrelated git repo"
}

test_rejects_empty_required_command_values() {
  local repo fake_bin log

  repo="$TEST_TMPDIR/repo"
  make_git_repo "$repo"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"

  if EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$repo" -p "$repo" -agent=; then
    fail "expected empty -agent= to fail"
  fi
  [[ ! -f "$log" ]] || fail "expected tmux not to run after empty -agent="

  if EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$repo" -p "$repo" -ed=; then
    fail "expected empty -ed= to fail"
  fi
  [[ ! -f "$log" ]] || fail "expected tmux not to run after empty -ed="
}

test_existing_worktree_branch_switch_prompts() {
  local project fake_bin log branch

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  git -C "$project" branch feature-x develop
  git -C "$project" worktree add -b other "$project/.worktrees/feature-x" main >/dev/null 2>&1
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"

  printf 'y\n' | EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$TEST_TMPDIR" -p "$project" feature-x develop

  branch="$(git -C "$project/.worktrees/feature-x" branch --show-current)"
  assert_eq "feature-x" "$branch" "expected existing worktree to switch after confirmation"
  assert_file_contains "$log" $'new-session\t-d\t-P\t-F\t#{session_id}\t#{session_name}\t#{window_id}\t#{pane_id}\t-s\tproject\t-n\tfeature-x'
}

test_existing_normal_worktree_remote_branch_preserves_fetch_refspecs() {
  local repo worktree fake_bin log before

  repo="$TEST_TMPDIR/repo"
  worktree="$repo/.worktrees/feature/foo"
  make_git_repo "$repo"
  git -C "$repo" remote add origin "$TEST_TMPDIR/origin.git"
  git -C "$repo" config --unset-all remote.origin.fetch
  git -C "$repo" config --add remote.origin.fetch \
    '+refs/heads/feature/foo:refs/remotes/origin/feature/foo'
  git -C "$repo" config --add remote.origin.fetch \
    '+refs/heads/release/*:refs/remotes/origin/release/*'
  before="$(git -C "$repo" config --get-all remote.origin.fetch)"
  git -C "$repo" update-ref refs/remotes/origin/feature/foo refs/heads/develop
  mkdir -p "$repo/.worktrees/feature"
  git -C "$repo" worktree add -q --detach "$worktree" main
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"

  printf 'y\n' | EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$repo" -p "$repo" -b feature/foo

  assert_eq "$before" "$(git -C "$repo" config --get-all remote.origin.fetch)" \
    "expected branch switching to preserve multiple fetch refspecs"
  assert_eq "feature/foo" "$(git -C "$worktree" branch --show-current)" \
    "expected the existing worktree to switch branches"
  assert_eq "origin/feature/foo" \
    "$(git -C "$worktree" rev-parse --abbrev-ref --symbolic-full-name @{u})" \
    "expected the switched branch to track the remote branch"
  assert_file_contains "$log" $'new-session\t'
}

test_existing_worktree_without_base_uses_project_head() {
  local project fake_bin log expected actual branch

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  git -C "$project" branch other develop
  git -C "$project" worktree add "$project/.worktrees/feature-x" other >/dev/null 2>&1
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"

  printf 'y\n' | EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$TEST_TMPDIR" -p "$project" feature-x

  branch="$(git -C "$project/.worktrees/feature-x" branch --show-current)"
  expected="$(git -C "$project" rev-parse HEAD)"
  actual="$(git -C "$project/.worktrees/feature-x" rev-parse HEAD)"
  assert_eq "feature-x" "$branch" "expected existing worktree to switch to basename branch"
  assert_eq "$expected" "$actual" "expected missing basename branch to start from project HEAD"
}

test_rejects_empty_project_and_branch_values() {
  local repo fake_bin log

  repo="$TEST_TMPDIR/repo"
  make_git_repo "$repo"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"

  if EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$repo" -p ""; then
    fail "expected empty -p value to fail"
  fi
  [[ ! -f "$log" ]] || fail "expected tmux not to run after empty -p value"

  if EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$repo" -p=; then
    fail "expected empty -p= value to fail"
  fi
  [[ ! -f "$log" ]] || fail "expected tmux not to run after empty -p= value"

  if EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$repo" -p "$repo" -b ""; then
    fail "expected empty -b value to fail"
  fi
  [[ ! -f "$log" ]] || fail "expected tmux not to run after empty -b value"

  if EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$repo" -p "$repo" -b=; then
    fail "expected empty -b= value to fail"
  fi
  [[ ! -f "$log" ]] || fail "expected tmux not to run after empty -b= value"
}

test_prompts_for_existing_repo_when_not_inside_git() {
  local repo fake_bin log no_fzf_path

  repo="$TEST_TMPDIR/repo"
  make_git_repo "$repo"
  mkdir -p "$TEST_TMPDIR/elsewhere"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  no_fzf_path="$(make_path_without_fzf "$fake_bin")"
  log="$TEST_TMPDIR/tmux.log"

  printf '%s\n' "$repo" | EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" \
    run_taw "$TEST_TMPDIR/elsewhere"

  assert_file_contains "$log" $'new-session\t-d\t-P\t-F\t#{session_id}\t#{session_name}\t#{window_id}\t#{pane_id}\t-s\trepo\t-n\trepo'
}

test_debug_option_prints_state_snapshot() {
  local repo fake_bin log output no_fzf_path

  repo="$TEST_TMPDIR/repo"
  make_git_repo "$repo"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  no_fzf_path="$(make_path_without_fzf "$fake_bin")"
  log="$TEST_TMPDIR/tmux.log"

  output="$(EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" \
    run_taw "$repo" --debug -p "$repo" 2>&1)"

  if ! grep -F "taw debug: before project resolution" <<<"$output" >/dev/null; then
    fail "expected --debug to print state before project resolution"
  fi
  if ! grep -F "taw debug: before tmux window" <<<"$output" >/dev/null; then
    fail "expected --debug to print state before tmux window"
  fi
  if ! grep -F "_taw_project_arg='$repo'" <<<"$output" >/dev/null; then
    fail "expected --debug output to include taw project arg"
  fi
}

test_prompted_project_resolves_from_projects_home() {
  local projects_home repo repo_real fake_bin log no_fzf_path

  projects_home="$TEST_TMPDIR/projects"
  repo="$projects_home/foo"
  make_git_repo "$repo"
  repo_real="$(cd "$repo" && pwd -P)"
  mkdir -p "$TEST_TMPDIR/elsewhere"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  no_fzf_path="$(make_path_without_fzf "$fake_bin")"
  log="$TEST_TMPDIR/tmux.log"

  printf 'foo\n' | PROJECTS_HOME="$projects_home" EDITOR=vim \
    TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" \
    run_taw "$TEST_TMPDIR/elsewhere"

  assert_file_contains "$log" $'new-session\t-d\t-P\t-F\t#{session_id}\t#{session_name}\t#{window_id}\t#{pane_id}\t-s\tfoo\t-n\tfoo\t-c\t'"$repo_real"$'\tvim'
}

test_non_git_child_under_bare_wrapper_prompts_for_project() {
  local wrapper_root project scratch repo repo_real fake_bin no_fzf_path log

  wrapper_root="$TEST_TMPDIR/wrapper"
  project="$(make_bare_wrapper "$wrapper_root")"
  scratch="$project/scratch"
  repo="$TEST_TMPDIR/repo"
  make_git_repo "$repo"
  repo_real="$(cd "$repo" && pwd -P)"
  mkdir -p "$scratch"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  no_fzf_path="$(make_path_without_fzf "$fake_bin")"
  log="$TEST_TMPDIR/tmux.log"

  printf '%s\n' "$repo" | EDITOR=vim \
    TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" \
    run_taw "$scratch"

  assert_file_contains "$log" $'new-session\t-d\t-P\t-F\t#{session_id}\t#{session_name}\t#{window_id}\t#{pane_id}\t-s\trepo\t-n\trepo\t-c\t'"$repo_real"$'\tvim'
  assert_file_not_contains "$log" $'-s\tproject'
  assert_not_exists "$project/.worktrees/main"
}

test_non_git_parent_with_bare_wrapper_child_prompts_for_project() {
  local parent project repo repo_real fake_bin no_fzf_path log

  parent="$TEST_TMPDIR/parent"
  project="$(make_bare_wrapper "$parent")"
  repo="$TEST_TMPDIR/repo"
  make_git_repo "$repo"
  repo_real="$(cd "$repo" && pwd -P)"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  no_fzf_path="$(make_path_without_fzf "$fake_bin")"
  log="$TEST_TMPDIR/tmux.log"

  printf '%s\n' "$repo" | EDITOR=vim \
    TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" \
    run_taw "$parent"

  assert_file_contains "$log" $'new-session\t-d\t-P\t-F\t#{session_id}\t#{session_name}\t#{window_id}\t#{pane_id}\t-s\trepo\t-n\trepo\t-c\t'"$repo_real"$'\tvim'
  assert_file_not_contains "$log" $'-s\tproject'
  assert_not_exists "$project/.worktrees/main"
}

test_current_bare_wrapper_auto_detects_without_prompt() {
  local project fake_bin no_fzf_path log branch worktree_real

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  no_fzf_path="$(make_path_without_fzf "$fake_bin")"
  log="$TEST_TMPDIR/tmux.log"

  EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    TAW_RUN_PATH="$no_fzf_path" \
    run_taw "$project"

  branch="$(git -C "$project/.worktrees/main" branch --show-current)"
  worktree_real="$(cd "$project/.worktrees/main" && pwd -P)"
  assert_eq "main" "$branch" "expected current bare wrapper to auto-detect"
  assert_file_contains "$log" $'new-session\t-d\t-P\t-F\t#{session_id}\t#{session_name}\t#{window_id}\t#{pane_id}\t-s\tproject\t-n\tmain'
  assert_file_contains "$log" $'-c\t'"$worktree_real"$'\tvim'
}

test_empty_prompt_selects_project_from_tmux_sessionizer_config() {
  local xdg projects_home repo repo_real elsewhere fake_bin log fzf_log no_fzf_path

  xdg="$TEST_TMPDIR/xdg"
  projects_home="$TEST_TMPDIR/projects"
  repo="$projects_home/repo"
  elsewhere="$TEST_TMPDIR/elsewhere"
  mkdir -p "$xdg/tmux-sessionizer" "$projects_home" "$elsewhere"
  printf 'TS_SEARCH_PATHS=("%s")\n' "$projects_home" >"$xdg/tmux-sessionizer/tmux-sessionizer.conf"
  make_git_repo "$repo"
  repo_real="$(cd "$repo" && pwd -P)"

  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  make_fake_fzf "$fake_bin"
  no_fzf_path="$(make_path_without_fzf "$fake_bin")"
  log="$TEST_TMPDIR/tmux.log"
  fzf_log="$TEST_TMPDIR/fzf-input.log"

  printf '\n' | XDG_CONFIG_HOME="$xdg" EDITOR=vim TAW_FAKE_FZF_MATCH="$repo" TAW_FAKE_FZF_MATCH_FALLBACK_OK=1 TAW_FAKE_FZF_FAIL_ON_SECOND=1 \
    TAW_FZF_INPUT_LOG="$fzf_log" TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" \
    run_taw "$elsewhere"

  assert_file_contains "$fzf_log" "$repo"
  assert_file_contains "$log" $'new-session\t-d\t-P\t-F\t#{session_id}\t#{session_name}\t#{window_id}\t#{pane_id}\t-s\trepo\t-n\trepo\t-c\t'"$repo_real"$'\tvim'
}

test_empty_project_prompt_mentions_fzf() {
  assert_file_contains "$REPO_ROOT/home/.zfuns/taw" "empty opens fzf"
}

test_project_picker_uses_zsh_directory_traversal() {
  local xdg projects_home extra_home external_home elsewhere fake_bin
  local log fzf_log find_log

  xdg="$TEST_TMPDIR/xdg"
  projects_home="$TEST_TMPDIR/projects"
  extra_home="$TEST_TMPDIR/extra"
  external_home="$TEST_TMPDIR/external"
  elsewhere="$TEST_TMPDIR/elsewhere"
  mkdir -p "$xdg/tmux-sessionizer" "$projects_home/visible/nested/too-deep" \
    "$projects_home/visible/.git/ignored" "$projects_home/.hidden" \
    "$extra_home/one/two" "$external_home/linked/child" "$elsewhere"
  ln -s "$external_home/linked" "$projects_home/link"
  {
    printf 'TS_SEARCH_PATHS=("%s")\n' "$projects_home"
    printf 'TS_MAX_DEPTH=2\n'
    printf 'TS_EXTRA_SEARCH_PATHS=("%s:1")\n' "$extra_home"
  } >"$xdg/tmux-sessionizer/tmux-sessionizer.conf"

  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  make_fake_fzf "$fake_bin"
  cat >"$fake_bin/find" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

: "${TAW_FIND_LOG:?}"
printf 'called\n' >"$TAW_FIND_LOG"
exit 99
EOF
  chmod +x "$fake_bin/find"
  log="$TEST_TMPDIR/tmux.log"
  fzf_log="$TEST_TMPDIR/fzf.log"
  find_log="$TEST_TMPDIR/find.log"

  XDG_CONFIG_HOME="$xdg" EDITOR=vim TAW_FAKE_FZF_CANCEL=1 \
    TAW_FZF_INPUT_LOG="$fzf_log" TAW_FIND_LOG="$find_log" \
    TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$elsewhere" --pick-project

  assert_file_contains "$fzf_log" "$projects_home/visible"
  assert_file_contains "$fzf_log" "$projects_home/visible/nested"
  assert_file_contains "$fzf_log" "$projects_home/.hidden"
  assert_file_contains "$fzf_log" "$extra_home/one"
  assert_file_not_contains "$fzf_log" "$projects_home/visible/nested/too-deep"
  assert_file_not_contains "$fzf_log" "$projects_home/visible/.git"
  assert_file_not_contains "$fzf_log" "$projects_home/link"
  assert_file_not_contains "$fzf_log" "$extra_home/one/two"
  assert_not_exists "$find_log"
}

test_project_picker_skips_control_characters_in_discovered_paths() {
  local xdg projects_home unsafe_project safe_project safe_real elsewhere
  local fake_bin no_fzf_path log fzf_log

  xdg="$TEST_TMPDIR/xdg"
  projects_home="$TEST_TMPDIR/projects"
  unsafe_project="$projects_home/unsafe"$'\n'"project"
  safe_project="$projects_home/safe"
  elsewhere="$TEST_TMPDIR/elsewhere"
  mkdir -p "$xdg/tmux-sessionizer" "$projects_home" "$elsewhere"
  printf 'TS_SEARCH_PATHS=("%s")\n' "$projects_home" >"$xdg/tmux-sessionizer/tmux-sessionizer.conf"
  make_git_repo "$unsafe_project"
  make_git_repo "$safe_project"
  safe_real="$(cd "$safe_project" && pwd -P)"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  make_fake_fzf "$fake_bin"
  no_fzf_path="$(make_path_without_fzf "$fake_bin")"
  log="$TEST_TMPDIR/tmux.log"
  fzf_log="$TEST_TMPDIR/fzf.log"

  XDG_CONFIG_HOME="$xdg" EDITOR=vim TAW_FAKE_FZF_MATCH="$safe_project" \
    TAW_FZF_INPUT_LOG="$fzf_log" TAW_FAKE_TMUX_BIN="$fake_bin" \
    TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" \
    run_taw "$elsewhere" --pick-project

  assert_file_contains "$fzf_log" "$safe_project"
  assert_file_not_contains "$fzf_log" unsafe
  assert_file_contains "$log" $'-c\t'"$safe_real"$'\tvim'
}

test_project_picker_rejects_control_characters_in_tmux_sessions() {
  local xdg empty_search session_path elsewhere fake_bin log output sessions

  xdg="$TEST_TMPDIR/xdg"
  empty_search="$TEST_TMPDIR/empty"
  session_path="$TEST_TMPDIR/session-path"
  elsewhere="$TEST_TMPDIR/elsewhere"
  mkdir -p "$xdg/tmux-sessionizer" "$empty_search" "$session_path" "$elsewhere"
  printf 'TS_SEARCH_PATHS=("%s")\n' "$empty_search" >"$xdg/tmux-sessionizer/tmux-sessionizer.conf"
  sessions=$'$7\tunsafe\tname\t'"$session_path"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  make_fake_fzf "$fake_bin"
  log="$TEST_TMPDIR/tmux.log"

  if output="$(XDG_CONFIG_HOME="$xdg" EDITOR=vim \
    TAW_FAKE_TMUX_SESSIONS="$sessions" \
    TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$elsewhere" --pick-project 2>&1)"; then
    fail "expected project picker to reject a tab in a tmux session name"
  fi

  assert_string_contains "$output" \
    "tmux session contains control characters and cannot be used by the picker"
  assert_no_tmux_work_window "$log"
}

test_project_picker_batches_tmux_session_metadata() {
  local xdg empty_search first_path second_path elsewhere fake_bin
  local sessions log fzf_log metadata_call metadata_call_count

  xdg="$TEST_TMPDIR/xdg"
  empty_search="$TEST_TMPDIR/empty"
  first_path="$TEST_TMPDIR/first"
  second_path="$TEST_TMPDIR/second"
  elsewhere="$TEST_TMPDIR/elsewhere"
  mkdir -p "$xdg/tmux-sessionizer" "$empty_search" "$first_path" \
    "$second_path" "$elsewhere"
  printf 'TS_SEARCH_PATHS=("%s")\n' "$empty_search" >"$xdg/tmux-sessionizer/tmux-sessionizer.conf"
  sessions=$'$7\tfirst\t'"$first_path"$'\n$8\tsecond\t'"$second_path"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  make_fake_fzf "$fake_bin"
  log="$TEST_TMPDIR/tmux.log"
  fzf_log="$TEST_TMPDIR/fzf.log"

  XDG_CONFIG_HOME="$xdg" EDITOR=vim TAW_FAKE_TMUX_SESSIONS="$sessions" \
    TAW_FAKE_FZF_CANCEL=1 TAW_FZF_INPUT_LOG="$fzf_log" \
    TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$elsewhere" --pick-project

  assert_file_contains "$fzf_log" '[TMUX] first'
  assert_file_contains "$fzf_log" '[TMUX] second'
  metadata_call=$'list-sessions\t-F\t#{session_id}\t#{session_name}\t#{session_path}__taw_picker_end__'
  metadata_call_count="$(grep -Fxc -- "$metadata_call" "$log" || true)"
  assert_eq "1" "$metadata_call_count" "expected one batched tmux metadata query"
  assert_file_not_contains "$log" $'display-message\t-p\t-t\t'
}

test_explicit_picker_prefetches_mode_snapshots() {
  local xdg projects_home target repo repo_real fake_bin no_fzf_path
  local log git_log marker picker_tmp args_log version_log metadata_call
  local worktree_call branch_call
  local -a fzf_args

  xdg="$TEST_TMPDIR/xdg"
  projects_home="$TEST_TMPDIR/projects"
  target="$projects_home/target"
  repo="$TEST_TMPDIR/repo"
  mkdir -p "$xdg/tmux-sessionizer" "$projects_home"
  printf 'TS_SEARCH_PATHS=("%s")\n' "$projects_home" >"$xdg/tmux-sessionizer/tmux-sessionizer.conf"
  make_git_repo "$target"
  make_git_repo "$repo"
  repo_real="$(cd "$repo" && pwd -P)"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  make_fake_fzf "$fake_bin"
  no_fzf_path="$(make_path_without_fzf "$fake_bin")"
  make_logging_git "$fake_bin"
  log="$TEST_TMPDIR/tmux.log"
  git_log="$TEST_TMPDIR/git.log"
  marker="$TEST_TMPDIR/worktree-prefetch-started"
  picker_tmp="$TEST_TMPDIR/picker-tmp"
  args_log="$TEST_TMPDIR/fzf-args.log"
  version_log="$TEST_TMPDIR/fzf-version.log"
  mkdir -p "$picker_tmp"
  export TAW_GIT_LOG="$git_log"
  export TAW_GIT_MARKER="$marker"

  XDG_CONFIG_HOME="$xdg" TMPDIR="$picker_tmp" EDITOR=vim TAW_FAKE_TMUX_SESSIONS= \
    TAW_FAKE_FZF_KEYS=$'tab\ntab\ntab\ntab\nnone' \
    TAW_FAKE_FZF_MATCH='main [worktree]' TAW_FAKE_FZF_WAIT_FOR_FILE="$marker" \
    TAW_FZF_ARGS_LOG="$args_log" TAW_FZF_VERSION_LOG="$version_log" \
    TAW_FAKE_TMUX_BIN="$fake_bin" \
    TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" run_taw "$repo" --mode=session
  unset TAW_GIT_LOG TAW_GIT_MARKER TAW_REAL_GIT

  assert_exists "$marker"
  mapfile -t fzf_args <"$args_log"
  assert_eq "5" "${#fzf_args[@]}" "expected repeated cycling through cached modes"
  worktree_call=$'-C\t'"$repo_real"$'\tworktree\tlist\t--porcelain\t-z'
  branch_call=$'-C\t'"$repo_real"$'\tfor-each-ref\t--sort=refname\t--format=%(refname)\trefs/heads'
  assert_eq "1" "$(grep -Fxc -- "$worktree_call" "$git_log")" \
    "expected one worktree snapshot"
  assert_eq "1" "$(grep -Fxc -- "$branch_call" "$git_log")" \
    "expected one branch snapshot"
  metadata_call=$'list-sessions\t-F\t#{session_id}\t#{session_name}\t#{session_path}__taw_picker_end__'
  assert_eq "1" "$(grep -Fxc -- "$metadata_call" "$log")" \
    "expected one session snapshot"
  assert_eq "1" "$(wc -l <"$version_log" | tr -d ' ')" \
    "expected one fzf version check"
  if compgen -G "$picker_tmp/taw-picker.*" >/dev/null; then
    fail "expected picker snapshot files to be cleaned up"
  fi
}

test_explicit_picker_starts_fzf_before_rows_finish() {
  local xdg projects_home target target_real elsewhere fake_bin no_fzf_path
  local log fzf_log started

  xdg="$TEST_TMPDIR/xdg"
  projects_home="$TEST_TMPDIR/projects"
  target="$projects_home/target"
  elsewhere="$TEST_TMPDIR/elsewhere"
  mkdir -p "$xdg/tmux-sessionizer" "$projects_home" "$elsewhere"
  printf 'TS_SEARCH_PATHS=("%s")\n' "$projects_home" >"$xdg/tmux-sessionizer/tmux-sessionizer.conf"
  make_git_repo "$target"
  target_real="$(cd "$target" && pwd -P)"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  make_fake_fzf "$fake_bin"
  no_fzf_path="$(make_path_without_fzf "$fake_bin")"
  log="$TEST_TMPDIR/tmux.log"
  fzf_log="$TEST_TMPDIR/fzf.log"
  started="$TEST_TMPDIR/fzf-started"

  XDG_CONFIG_HOME="$xdg" EDITOR=vim TAW_FAKE_TMUX_SESSIONS= \
    TAW_FAKE_TMUX_WAIT_FOR_FILE="$started" TAW_FAKE_FZF_STARTED_FILE="$started" \
    TAW_FAKE_FZF_MATCH="$target" TAW_FZF_INPUT_LOG="$fzf_log" \
    TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" \
    run_taw "$elsewhere" --mode=session

  assert_exists "$started"
  assert_file_contains "$fzf_log" "$target"
  assert_file_contains "$log" $'-c\t'"$target_real"$'\tvim'
}

test_explicit_picker_handles_early_fzf_exit() {
  local xdg projects_home target elsewhere fake_bin no_fzf_path
  local log cancel_log picker_tmp directory_name i rc

  xdg="$TEST_TMPDIR/xdg"
  projects_home="$TEST_TMPDIR/projects"
  target="$projects_home/000-target"
  elsewhere="$TEST_TMPDIR/elsewhere"
  mkdir -p "$xdg/tmux-sessionizer" "$projects_home" "$elsewhere" "$target"
  printf 'TS_SEARCH_PATHS=("%s")\n' "$projects_home" >"$xdg/tmux-sessionizer/tmux-sessionizer.conf"
  for ((i = 0; i < 800; i++)); do
    printf -v directory_name \
      'project-%04d-abcdefghijklmnopqrstuvwxyz-abcdefghijklmnopqrstuvwxyz-abcdefghijklmnopqrstuvwxyz' "$i"
    mkdir "$projects_home/$directory_name"
  done
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  make_fake_fzf "$fake_bin"
  no_fzf_path="$(make_path_without_fzf "$fake_bin")"
  log="$TEST_TMPDIR/tmux.log"
  picker_tmp="$TEST_TMPDIR/picker-tmp"
  mkdir -p "$picker_tmp"

  XDG_CONFIG_HOME="$xdg" TMPDIR="$picker_tmp" EDITOR=vim TAW_FAKE_TMUX_SESSIONS= \
    TAW_FAKE_FZF_CLOSE_EARLY=1 TAW_FAKE_TMUX_BIN="$fake_bin" \
    TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" \
    run_taw "$elsewhere" --mode=session

  assert_file_contains "$log" $'new-session\t'
  assert_file_contains "$log" "$projects_home/"

  cancel_log="$TEST_TMPDIR/tmux-cancel.log"
  set +e
  XDG_CONFIG_HOME="$xdg" TMPDIR="$picker_tmp" EDITOR=vim TAW_FAKE_TMUX_SESSIONS= \
    TAW_FAKE_FZF_CLOSE_EARLY=1 TAW_FAKE_FZF_CANCEL=1 \
    TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$cancel_log" \
    TAW_RUN_PATH="$no_fzf_path" run_taw "$elsewhere" --mode=session
  rc=$?
  set -e

  assert_eq "0" "$rc" "expected early fzf cancellation to return successfully"
  assert_no_tmux_work_window "$cancel_log"
  if compgen -G "$picker_tmp/taw-picker.*" >/dev/null; then
    fail "expected picker snapshot files to be cleaned up after fzf exits"
  fi
}

test_project_picker_skips_unsafe_current_tmux_session() {
  local xdg projects_home repo elsewhere unsafe_path fake_bin no_fzf_path
  local sessions log fzf_log

  xdg="$TEST_TMPDIR/xdg"
  projects_home="$TEST_TMPDIR/projects"
  repo="$projects_home/repo"
  elsewhere="$TEST_TMPDIR/elsewhere"
  unsafe_path="$TEST_TMPDIR/current"$'\t'"session"
  mkdir -p "$xdg/tmux-sessionizer" "$projects_home" "$elsewhere" "$unsafe_path"
  printf 'TS_SEARCH_PATHS=("%s")\n' "$projects_home" >"$xdg/tmux-sessionizer/tmux-sessionizer.conf"
  make_git_repo "$repo"
  sessions=$'$1\tcurrent\t'"$unsafe_path"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  make_fake_fzf "$fake_bin"
  no_fzf_path="$(make_path_without_fzf "$fake_bin")"
  log="$TEST_TMPDIR/tmux.log"
  fzf_log="$TEST_TMPDIR/fzf-input.log"

  printf '\n' | XDG_CONFIG_HOME="$xdg" EDITOR=vim TAW_TEST_TMUX=/tmp/tmux \
    TAW_FAKE_TMUX_CURRENT_SESSION_ID='$1' TAW_FAKE_TMUX_SESSIONS="$sessions" \
    TAW_FAKE_FZF_MATCH="$repo" \
    TAW_FAKE_FZF_MATCH_FALLBACK_OK=1 TAW_FAKE_FZF_FAIL_ON_SECOND=1 \
    TAW_FZF_INPUT_LOG="$fzf_log" TAW_FAKE_TMUX_BIN="$fake_bin" \
    TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" \
    run_taw "$elsewhere" --pick-project

  assert_file_contains "$fzf_log" "$repo"
  assert_file_not_contains "$fzf_log" '[TMUX] current'
  assert_file_contains "$log" \
    $'list-sessions\t-F\t#{session_id}\t#{session_name}\t#{session_path}__taw_picker_end__\t-f\t#{!=:#{session_id},$1}'
  assert_file_not_contains "$log" $'display-message\t-p\t-t\t$1\t#{session_path}'
}

test_empty_prompt_project_picker_resolves_tmux_session_row() {
  local xdg empty_search repo repo_real elsewhere fake_bin log fzf_log sessions no_fzf_path

  xdg="$TEST_TMPDIR/xdg"
  empty_search="$TEST_TMPDIR/empty"
  repo="$TEST_TMPDIR/repo"
  elsewhere="$TEST_TMPDIR/elsewhere"
  mkdir -p "$xdg/tmux-sessionizer" "$empty_search" "$elsewhere"
  printf 'TS_SEARCH_PATHS=("%s")\n' "$empty_search" >"$xdg/tmux-sessionizer/tmux-sessionizer.conf"
  make_git_repo "$repo"
  repo_real="$(cd "$repo" && pwd -P)"
  sessions=$'agent\t'"$repo_real"

  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  make_fake_fzf "$fake_bin"
  no_fzf_path="$(make_path_without_fzf "$fake_bin")"
  log="$TEST_TMPDIR/tmux.log"
  fzf_log="$TEST_TMPDIR/fzf-input.log"

  printf '\n' | XDG_CONFIG_HOME="$xdg" EDITOR=vim TAW_AGENT='ignored-agent' TAW_FAKE_TMUX_HAS_SESSION=1 \
    TAW_FAKE_TMUX_SESSIONS="$sessions" TAW_FAKE_FZF_MATCH='[TMUX] agent' TAW_FAKE_FZF_MATCH_FALLBACK_OK=1 TAW_FAKE_FZF_FAIL_ON_SECOND=1 \
    TAW_FZF_INPUT_LOG="$fzf_log" TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" \
    run_taw "$elsewhere"

  assert_file_contains "$fzf_log" '[TMUX] agent'
  assert_file_contains "$log" $'attach-session\t-t\t$1'
  assert_file_not_contains "$log" $'new-window\t'
  assert_file_not_contains "$log" $'select-window\t'
  assert_file_not_contains "$log" $'ignored-agent'
}

test_project_picker_tmux_row_preserves_active_window_inside_tmux() {
  local xdg empty_search session_path elsewhere fake_bin log fzf_log sessions no_fzf_path

  xdg="$TEST_TMPDIR/xdg"
  empty_search="$TEST_TMPDIR/empty"
  session_path="$TEST_TMPDIR/session-path"
  elsewhere="$TEST_TMPDIR/elsewhere"
  mkdir -p "$xdg/tmux-sessionizer" "$empty_search" "$session_path" "$elsewhere"
  printf 'TS_SEARCH_PATHS=("%s")\n' "$empty_search" >"$xdg/tmux-sessionizer/tmux-sessionizer.conf"
  sessions=$'$9\ttarget\t'"$session_path"

  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  make_fake_fzf "$fake_bin"
  no_fzf_path="$(make_path_without_fzf "$fake_bin")"
  log="$TEST_TMPDIR/tmux.log"
  fzf_log="$TEST_TMPDIR/fzf-input.log"

  XDG_CONFIG_HOME="$xdg" EDITOR=vim TAW_TEST_TMUX=/tmp/tmux TAW_FAKE_FZF_KEYS=alt-enter \
    TAW_FAKE_TMUX_CURRENT_SESSION_NAME=current TAW_FAKE_TMUX_HAS_SESSION_TARGETS='$9' \
    TAW_FAKE_TMUX_SESSIONS="$sessions" TAW_FAKE_FZF_MATCH='[TMUX] target' \
    TAW_FAKE_FZF_MATCH_FALLBACK_OK=1 TAW_FZF_INPUT_LOG="$fzf_log" \
    TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" \
    run_taw "$elsewhere" -ts -agent "claude --resume" -ed "nvim ." -sh "npm test"

  assert_file_contains "$fzf_log" '[TMUX] target'
  assert_file_contains "$log" $'switch-client\t-t\t$9'
  assert_file_not_contains "$log" $'attach-session\t'
  assert_file_not_contains "$log" $'new-window\t'
  assert_file_not_contains "$log" $'select-window\t'
  assert_file_not_contains "$log" $'select-pane\t'
  assert_file_not_contains "$log" $'claude --resume'
  assert_file_not_contains "$log" $'nvim .'
  assert_file_not_contains "$log" $'npm test'
}

test_project_picker_tmux_row_links_active_window_with_peer() {
  local xdg empty_search session_path elsewhere fake_bin log fzf_log sessions no_fzf_path

  xdg="$TEST_TMPDIR/xdg"
  empty_search="$TEST_TMPDIR/empty"
  session_path="$TEST_TMPDIR/session-path"
  elsewhere="$TEST_TMPDIR/elsewhere"
  mkdir -p "$xdg/tmux-sessionizer" "$empty_search" "$session_path" "$elsewhere"
  printf 'TS_SEARCH_PATHS=("%s")\n' "$empty_search" >"$xdg/tmux-sessionizer/tmux-sessionizer.conf"
  sessions=$'$9\ttarget\t'"$session_path"

  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  make_fake_fzf "$fake_bin"
  no_fzf_path="$(make_path_without_fzf "$fake_bin")"
  log="$TEST_TMPDIR/tmux.log"
  fzf_log="$TEST_TMPDIR/fzf-input.log"

  XDG_CONFIG_HOME="$xdg" EDITOR=vim TAW_TEST_TMUX=/tmp/tmux \
    TAW_FAKE_TMUX_CURRENT_SESSION_ID='$1' TAW_FAKE_TMUX_HAS_SESSION_TARGETS='$9' \
    TAW_FAKE_TMUX_CURRENT_WINDOW_ID='@9' \
    TAW_FAKE_TMUX_CURRENT_SESSION_WINDOWS=$'@1\n@2' TAW_FAKE_TMUX_SESSIONS="$sessions" \
    TAW_FAKE_FZF_MATCH='[TMUX] target' TAW_FAKE_FZF_MATCH_FALLBACK_OK=1 \
    TAW_FZF_INPUT_LOG="$fzf_log" TAW_FAKE_TMUX_BIN="$fake_bin" \
    TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" \
    run_taw "$elsewhere" -ts --peer

  assert_file_contains "$fzf_log" '[TMUX] target'
  assert_file_contains "$log" $'display-message\t-p\t-t\t$9:\t#{window_id}'
  assert_file_contains "$log" $'list-windows\t-t\t$1\t-F\t#{window_id}'
  assert_file_contains "$log" $'link-window\t-d\t-s\t@9\t-t\t$1:'
  assert_file_contains "$log" $'select-window\t-t\t@9'
  assert_file_not_contains "$log" $'switch-client\t'
  assert_file_not_contains "$log" $'attach-session\t'
  assert_file_not_contains "$log" $'new-window\t'
  assert_file_not_contains "$log" $'new-session\t'
  assert_file_not_contains "$log" $'select-pane\t'
}

test_project_picker_tmux_row_reuses_linked_active_window_with_peer() {
  local xdg empty_search session_path elsewhere fake_bin log fzf_log sessions no_fzf_path

  xdg="$TEST_TMPDIR/xdg"
  empty_search="$TEST_TMPDIR/empty"
  session_path="$TEST_TMPDIR/session-path"
  elsewhere="$TEST_TMPDIR/elsewhere"
  mkdir -p "$xdg/tmux-sessionizer" "$empty_search" "$session_path" "$elsewhere"
  printf 'TS_SEARCH_PATHS=("%s")\n' "$empty_search" >"$xdg/tmux-sessionizer/tmux-sessionizer.conf"
  sessions=$'$9\ttarget\t'"$session_path"

  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  make_fake_fzf "$fake_bin"
  no_fzf_path="$(make_path_without_fzf "$fake_bin")"
  log="$TEST_TMPDIR/tmux.log"
  fzf_log="$TEST_TMPDIR/fzf-input.log"

  XDG_CONFIG_HOME="$xdg" EDITOR=vim TAW_TEST_TMUX=/tmp/tmux \
    TAW_FAKE_TMUX_CURRENT_SESSION_ID='$1' TAW_FAKE_TMUX_HAS_SESSION_TARGETS='$9' \
    TAW_FAKE_TMUX_CURRENT_WINDOW_ID='@9' \
    TAW_FAKE_TMUX_CURRENT_SESSION_WINDOWS=$'@1\n@9' TAW_FAKE_TMUX_SESSIONS="$sessions" \
    TAW_FAKE_FZF_MATCH='[TMUX] target' TAW_FAKE_FZF_MATCH_FALLBACK_OK=1 \
    TAW_FZF_INPUT_LOG="$fzf_log" TAW_FAKE_TMUX_BIN="$fake_bin" \
    TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" \
    run_taw "$elsewhere" -ts --peer

  assert_file_contains "$fzf_log" '[TMUX] target'
  assert_file_contains "$log" $'select-window\t-t\t@9'
  assert_file_not_contains "$log" $'link-window\t'
  assert_file_not_contains "$log" $'switch-client\t'
  assert_file_not_contains "$log" $'attach-session\t'
}

test_project_picker_tmux_row_uses_session_identity() {
  local xdg empty_search tmux_repo tmux_real collision elsewhere fake_bin log fzf_log sessions no_fzf_path

  xdg="$TEST_TMPDIR/xdg"
  empty_search="$TEST_TMPDIR/empty"
  tmux_repo="$TEST_TMPDIR/session-repo"
  elsewhere="$TEST_TMPDIR/elsewhere"
  collision="$elsewhere/dupe"
  mkdir -p "$xdg/tmux-sessionizer" "$empty_search" "$elsewhere"
  printf 'TS_SEARCH_PATHS=("%s")\n' "$empty_search" >"$xdg/tmux-sessionizer/tmux-sessionizer.conf"
  make_git_repo "$tmux_repo"
  make_git_repo "$collision"
  tmux_real="$(cd "$tmux_repo" && pwd -P)"
  sessions=$'dupe\t'"$tmux_real"

  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  make_fake_fzf "$fake_bin"
  no_fzf_path="$(make_path_without_fzf "$fake_bin")"
  log="$TEST_TMPDIR/tmux.log"
  fzf_log="$TEST_TMPDIR/fzf-input.log"

  printf '\n' | XDG_CONFIG_HOME="$xdg" EDITOR=vim TAW_FAKE_TMUX_HAS_SESSION=1 \
    TAW_FAKE_TMUX_SESSIONS="$sessions" TAW_FAKE_FZF_MATCH='[TMUX] dupe' TAW_FAKE_FZF_MATCH_FALLBACK_OK=1 \
    TAW_FZF_INPUT_LOG="$fzf_log" TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" \
    run_taw "$elsewhere"

  assert_file_contains "$fzf_log" '[TMUX] dupe'
  assert_file_contains "$log" $'attach-session\t-t\t$1'
  assert_file_not_contains "$log" $'new-window\t'
  assert_file_not_contains "$log" $'select-window\t'
  assert_file_not_contains "$log" $'-c\t'"$collision"
}

test_project_picker_tmux_row_ignores_projects_home_collision() {
  local xdg empty_search projects_home tmux_repo tmux_real collision elsewhere fake_bin log fzf_log sessions no_fzf_path

  xdg="$TEST_TMPDIR/xdg"
  empty_search="$TEST_TMPDIR/empty"
  projects_home="$TEST_TMPDIR/projects"
  tmux_repo="$TEST_TMPDIR/session-repo"
  elsewhere="$TEST_TMPDIR/elsewhere"
  collision="$projects_home/dupe"
  mkdir -p "$xdg/tmux-sessionizer" "$empty_search" "$projects_home" "$elsewhere"
  printf 'TS_SEARCH_PATHS=("%s")\n' "$empty_search" >"$xdg/tmux-sessionizer/tmux-sessionizer.conf"
  make_git_repo "$tmux_repo"
  make_git_repo "$collision"
  tmux_real="$(cd "$tmux_repo" && pwd -P)"
  sessions=$'dupe\t'"$tmux_real"

  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  make_fake_fzf "$fake_bin"
  no_fzf_path="$(make_path_without_fzf "$fake_bin")"
  log="$TEST_TMPDIR/tmux.log"
  fzf_log="$TEST_TMPDIR/fzf-input.log"

  printf '\n' | PROJECTS_HOME="$projects_home" XDG_CONFIG_HOME="$xdg" EDITOR=vim TAW_FAKE_TMUX_HAS_SESSION=1 \
    TAW_FAKE_TMUX_SESSIONS="$sessions" TAW_FAKE_FZF_MATCH='[TMUX] dupe' TAW_FAKE_FZF_MATCH_FALLBACK_OK=1 \
    TAW_FZF_INPUT_LOG="$fzf_log" TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" \
    run_taw "$elsewhere"

  assert_file_contains "$fzf_log" '[TMUX] dupe'
  assert_file_contains "$log" $'attach-session\t-t\t$1'
  assert_file_not_contains "$log" $'new-window\t'
  assert_file_not_contains "$log" $'select-window\t'
  assert_file_not_contains "$log" $'-c\t'"$collision"
}

test_project_picker_tmux_row_fails_if_session_disappears() {
  local xdg empty_search selected_repo basename_repo basename_real elsewhere fake_bin log fzf_log sessions after_sessions no_fzf_path rc

  xdg="$TEST_TMPDIR/xdg"
  empty_search="$TEST_TMPDIR/empty"
  selected_repo="$TEST_TMPDIR/selected-repo"
  basename_repo="$TEST_TMPDIR/dupe"
  elsewhere="$TEST_TMPDIR/elsewhere"
  mkdir -p "$xdg/tmux-sessionizer" "$empty_search" "$elsewhere"
  printf 'TS_SEARCH_PATHS=("%s")\n' "$empty_search" >"$xdg/tmux-sessionizer/tmux-sessionizer.conf"
  make_git_repo "$selected_repo"
  make_git_repo "$basename_repo"
  basename_real="$(cd "$basename_repo" && pwd -P)"
  sessions=$'dupe\t'"$selected_repo"
  after_sessions=$'other\t'"$basename_real"

  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  make_fake_fzf "$fake_bin"
  no_fzf_path="$(make_path_without_fzf "$fake_bin")"
  log="$TEST_TMPDIR/tmux.log"
  fzf_log="$TEST_TMPDIR/fzf-input.log"

  set +e
  printf '\n' | XDG_CONFIG_HOME="$xdg" EDITOR=vim TAW_FAKE_TMUX_HAS_SESSION=1 \
    TAW_FAKE_TMUX_SESSIONS="$sessions" TAW_FAKE_TMUX_SESSIONS_AFTER_FIRST="$after_sessions" \
    TAW_FAKE_FZF_MATCH='[TMUX] dupe' TAW_FAKE_FZF_MATCH_FALLBACK_OK=1 \
    TAW_FZF_INPUT_LOG="$fzf_log" TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" \
    run_taw "$elsewhere"
  rc=$?
  set -e

  [[ $rc -ne 0 ]] || fail "expected disappeared tmux session to fail"
  assert_file_contains "$fzf_log" '[TMUX] dupe'
  assert_no_tmux_work_window "$log"
  assert_file_not_contains "$log" $'-c\t'"$basename_real"
}

test_project_picker_tmux_row_rejects_same_name_replacement() {
  local xdg empty_search selected_repo selected_real elsewhere fake_bin log fzf_log sessions after_sessions no_fzf_path rc

  xdg="$TEST_TMPDIR/xdg"
  empty_search="$TEST_TMPDIR/empty"
  selected_repo="$TEST_TMPDIR/selected-repo"
  elsewhere="$TEST_TMPDIR/elsewhere"
  mkdir -p "$xdg/tmux-sessionizer" "$empty_search" "$elsewhere"
  printf 'TS_SEARCH_PATHS=("%s")\n' "$empty_search" >"$xdg/tmux-sessionizer/tmux-sessionizer.conf"
  make_git_repo "$selected_repo"
  selected_real="$(cd "$selected_repo" && pwd -P)"
  sessions=$'$1\tdupe\t'"$selected_real"
  after_sessions=$'$2\tdupe\t'"$selected_real"

  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  make_fake_fzf "$fake_bin"
  no_fzf_path="$(make_path_without_fzf "$fake_bin")"
  log="$TEST_TMPDIR/tmux.log"
  fzf_log="$TEST_TMPDIR/fzf-input.log"

  set +e
  printf '\n' | XDG_CONFIG_HOME="$xdg" EDITOR=vim TAW_FAKE_TMUX_HAS_SESSION=1 \
    TAW_FAKE_TMUX_SESSIONS="$sessions" TAW_FAKE_TMUX_SESSIONS_AFTER_FIRST="$after_sessions" \
    TAW_FAKE_FZF_MATCH='[TMUX] dupe' TAW_FAKE_FZF_MATCH_FALLBACK_OK=1 \
    TAW_FZF_INPUT_LOG="$fzf_log" TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" \
    run_taw "$elsewhere"
  rc=$?
  set -e

  [[ $rc -ne 0 ]] || fail "expected same-name replacement tmux session to fail"
  assert_file_contains "$fzf_log" '[TMUX] dupe'
  assert_no_tmux_work_window "$log"
  assert_file_not_contains "$log" $'-c\t'"$selected_real"
}

test_project_picker_tmux_row_rejects_replacement_after_revalidation() {
  local xdg empty_search selected_repo selected_real elsewhere fake_bin log fzf_log sessions no_fzf_path rc

  xdg="$TEST_TMPDIR/xdg"
  empty_search="$TEST_TMPDIR/empty"
  selected_repo="$TEST_TMPDIR/selected-repo"
  elsewhere="$TEST_TMPDIR/elsewhere"
  mkdir -p "$xdg/tmux-sessionizer" "$empty_search" "$elsewhere"
  printf 'TS_SEARCH_PATHS=("%s")\n' "$empty_search" >"$xdg/tmux-sessionizer/tmux-sessionizer.conf"
  make_git_repo "$selected_repo"
  selected_real="$(cd "$selected_repo" && pwd -P)"
  sessions=$'$1\tdupe\t'"$selected_real"

  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  make_fake_fzf "$fake_bin"
  no_fzf_path="$(make_path_without_fzf "$fake_bin")"
  log="$TEST_TMPDIR/tmux.log"
  fzf_log="$TEST_TMPDIR/fzf-input.log"

  set +e
  printf '\n' | XDG_CONFIG_HOME="$xdg" EDITOR=vim \
    TAW_FAKE_TMUX_HAS_SESSION_TARGETS=$'dupe\n' TAW_FAKE_TMUX_SESSIONS="$sessions" \
    TAW_FAKE_FZF_MATCH='[TMUX] dupe' TAW_FAKE_FZF_MATCH_FALLBACK_OK=1 \
    TAW_FZF_INPUT_LOG="$fzf_log" TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" \
    run_taw "$elsewhere"
  rc=$?
  set -e

  [[ $rc -ne 0 ]] || fail "expected post-revalidation tmux session replacement to fail"
  assert_file_contains "$fzf_log" '[TMUX] dupe'
  assert_file_contains "$log" $'has-session\t-t\t$1'
  assert_file_not_contains "$log" $'has-session\t-t\tdupe'
  assert_no_tmux_work_window "$log"
  assert_file_not_contains "$log" $'-c\t'"$selected_real"
}

test_empty_prompt_project_picker_cancel_returns_without_tmux_window() {
  local xdg projects_home repo elsewhere fake_bin log rc

  xdg="$TEST_TMPDIR/xdg"
  projects_home="$TEST_TMPDIR/projects"
  repo="$projects_home/repo"
  elsewhere="$TEST_TMPDIR/elsewhere"
  mkdir -p "$xdg/tmux-sessionizer" "$projects_home" "$elsewhere"
  printf 'TS_SEARCH_PATHS=("%s")\n' "$projects_home" >"$xdg/tmux-sessionizer/tmux-sessionizer.conf"
  make_git_repo "$repo"

  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  make_fake_fzf "$fake_bin"
  log="$TEST_TMPDIR/tmux.log"

  set +e
  printf '\n' | XDG_CONFIG_HOME="$xdg" EDITOR=vim TAW_FAKE_FZF_CANCEL=1 \
    TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$elsewhere"
  rc=$?
  set -e

  assert_eq "0" "$rc" "expected fzf cancellation to return successfully"
  assert_no_tmux_work_window "$log"
}

test_project_picker_flag_error_fails_without_tmux_window() {
  local xdg projects_home repo current_repo fake_bin log rc

  xdg="$TEST_TMPDIR/xdg"
  projects_home="$TEST_TMPDIR/projects"
  repo="$projects_home/repo"
  current_repo="$TEST_TMPDIR/current"
  mkdir -p "$xdg/tmux-sessionizer" "$projects_home"
  printf 'TS_SEARCH_PATHS=("%s")\n' "$projects_home" >"$xdg/tmux-sessionizer/tmux-sessionizer.conf"
  make_git_repo "$repo"
  make_git_repo "$current_repo"

  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  make_fake_fzf "$fake_bin"
  log="$TEST_TMPDIR/tmux.log"

  set +e
  XDG_CONFIG_HOME="$xdg" EDITOR=vim TAW_FAKE_FZF_STATUS=1 \
    TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$current_repo" --pick-project
  rc=$?
  set -e

  [[ $rc -ne 0 ]] || fail "expected project picker fzf error to fail"
  assert_no_tmux_work_window "$log"
}

test_project_prompt_escape_returns_without_tmux_window() {
  local elsewhere fake_bin log rc

  elsewhere="$TEST_TMPDIR/elsewhere"
  mkdir -p "$elsewhere"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"

  set +e
  printf '\033\n' | EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$elsewhere"
  rc=$?
  set -e

  assert_eq "0" "$rc" "expected prompt escape to return successfully"
  [[ ! -f "$log" ]] || fail "expected tmux not to run after prompt escape"
}

test_project_picker_flag_bypasses_current_repo_detection() {
  local xdg projects_home current_repo picked_repo picked_real fake_bin log fzf_log no_fzf_path

  xdg="$TEST_TMPDIR/xdg"
  projects_home="$TEST_TMPDIR/projects"
  current_repo="$TEST_TMPDIR/current"
  picked_repo="$projects_home/picked"
  mkdir -p "$xdg/tmux-sessionizer" "$projects_home"
  printf 'TS_SEARCH_PATHS=("%s")\n' "$projects_home" >"$xdg/tmux-sessionizer/tmux-sessionizer.conf"
  make_git_repo "$current_repo"
  make_git_repo "$picked_repo"
  picked_real="$(cd "$picked_repo" && pwd -P)"

  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  make_fake_fzf "$fake_bin"
  no_fzf_path="$(make_path_without_fzf "$fake_bin")"
  log="$TEST_TMPDIR/tmux.log"
  fzf_log="$TEST_TMPDIR/fzf-input.log"

  XDG_CONFIG_HOME="$xdg" EDITOR=vim TAW_AGENT='ignored' TAW_FAKE_FZF_MATCH="$picked_repo" \
    TAW_FAKE_FZF_MATCH_FALLBACK_OK=1 TAW_FAKE_FZF_FAIL_ON_SECOND=1 TAW_FZF_INPUT_LOG="$fzf_log" TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" \
    run_taw "$current_repo" --pick-project -agent "claude --resume" -ed "nvim ." -sh "npm test"

  assert_file_contains "$fzf_log" "$picked_repo"
  assert_file_contains "$log" $'new-session\t-d\t-P\t-F\t#{session_id}\t#{session_name}\t#{window_id}\t#{pane_id}\t-s\tpicked\t-n\tpicked\t-c\t'"$picked_real"$'\tnvim .'
  assert_file_contains "$log" $'split-window\t-h\t-P\t-F\t#{pane_id}\t-t\t%1\t-c\t'"$picked_real"$'\tclaude --resume'
  assert_file_contains "$log" $'split-window\t-v\t-P\t-F\t#{pane_id}\t-t\t%2\t-c\t'"$picked_real"$'\tnpm test'
  assert_file_contains "$log" $'select-pane\t-t\t%1'
  assert_file_not_contains "$log" $'ignored'
  assert_file_not_contains "$log" $'-s\tcurrent'
}

test_project_picker_flag_cancel_returns_without_tmux_window() {
  local xdg projects_home repo current_repo fake_bin log rc

  xdg="$TEST_TMPDIR/xdg"
  projects_home="$TEST_TMPDIR/projects"
  repo="$projects_home/repo"
  current_repo="$TEST_TMPDIR/current"
  mkdir -p "$xdg/tmux-sessionizer" "$projects_home"
  printf 'TS_SEARCH_PATHS=("%s")\n' "$projects_home" >"$xdg/tmux-sessionizer/tmux-sessionizer.conf"
  make_git_repo "$repo"
  make_git_repo "$current_repo"

  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  make_fake_fzf "$fake_bin"
  log="$TEST_TMPDIR/tmux.log"

  set +e
  XDG_CONFIG_HOME="$xdg" EDITOR=vim TAW_FAKE_FZF_CANCEL=1 \
    TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$current_repo" --pick-project
  rc=$?
  set -e

  assert_eq "0" "$rc" "expected project picker flag cancellation to return successfully"
  assert_no_tmux_work_window "$log"
}

test_project_picker_flag_ignores_taw_agent_without_explicit_agent() {
  local xdg projects_home repo current_repo picked_real fake_bin log fzf_log no_fzf_path

  xdg="$TEST_TMPDIR/xdg"
  projects_home="$TEST_TMPDIR/projects"
  repo="$projects_home/repo"
  current_repo="$TEST_TMPDIR/current"
  mkdir -p "$xdg/tmux-sessionizer" "$projects_home"
  printf 'TS_SEARCH_PATHS=("%s")\n' "$projects_home" >"$xdg/tmux-sessionizer/tmux-sessionizer.conf"
  make_git_repo "$current_repo"
  make_git_repo "$repo"
  picked_real="$(cd "$repo" && pwd -P)"

  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  make_fake_fzf "$fake_bin"
  no_fzf_path="$(make_path_without_fzf "$fake_bin")"
  log="$TEST_TMPDIR/tmux.log"
  fzf_log="$TEST_TMPDIR/fzf-input.log"

  XDG_CONFIG_HOME="$xdg" EDITOR=vim TAW_AGENT='ignored-agent' TAW_FAKE_FZF_MATCH="$repo" \
    TAW_FAKE_FZF_MATCH_FALLBACK_OK=1 TAW_FAKE_FZF_FAIL_ON_SECOND=1 TAW_FZF_INPUT_LOG="$fzf_log" TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" \
    run_taw "$current_repo" --pick-project -sh "npm test" -sh "echo later"

  assert_file_contains "$fzf_log" "$repo"
  assert_file_contains "$log" $'new-session\t-d\t-P\t-F\t#{session_id}\t#{session_name}\t#{window_id}\t#{pane_id}\t-s\trepo\t-n\trepo\t-c\t'"$picked_real"$'\tvim'
  assert_file_contains "$log" $'split-window\t-h\t-P\t-F\t#{pane_id}\t-t\t%1\t-c\t'"$picked_real"$'\tnpm test'
  assert_file_contains "$log" $'split-window\t-h\t-P\t-F\t#{pane_id}\t-t\t%2\t-c\t'"$picked_real"$'\techo later'
  assert_file_not_contains "$log" $'split-window\t-v\t'
  assert_file_not_contains "$log" $'ignored-agent'
  assert_file_contains "$log" $'select-pane\t-t\t%1'
}

test_project_picker_flag_opens_bare_wrapper_default_worktree_without_second_picker() {
  local xdg projects_home current_repo project project_real fake_bin log fzf_log no_fzf_path

  xdg="$TEST_TMPDIR/xdg"
  projects_home="$TEST_TMPDIR/projects"
  current_repo="$TEST_TMPDIR/current"
  mkdir -p "$xdg/tmux-sessionizer" "$projects_home"
  printf 'TS_SEARCH_PATHS=("%s")\n' "$projects_home" >"$xdg/tmux-sessionizer/tmux-sessionizer.conf"
  make_git_repo "$current_repo"
  project="$(make_bare_wrapper "$projects_home")"

  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  make_fake_fzf "$fake_bin"
  no_fzf_path="$(make_path_without_fzf "$fake_bin")"
  log="$TEST_TMPDIR/tmux.log"
  fzf_log="$TEST_TMPDIR/fzf-input.log"

  XDG_CONFIG_HOME="$xdg" EDITOR=vim TAW_FAKE_FZF_MATCH="$project" \
    TAW_FAKE_FZF_MATCH_FALLBACK_OK=1 TAW_FAKE_FZF_FAIL_ON_SECOND=1 TAW_FZF_INPUT_LOG="$fzf_log" \
    TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" \
    run_taw "$current_repo" --pick-project

  assert_file_contains "$fzf_log" "$project"
  project_real="$(cd "$project/.worktrees/main" && pwd -P)"
  assert_file_contains "$log" $'new-session\t-d\t-P\t-F\t#{session_id}\t#{session_name}\t#{window_id}\t#{pane_id}\t-s\tproject\t-n\tmain\t-c\t'"$project_real"$'\tvim'
  assert_file_not_contains "$log" $'split-window\t'
  assert_file_contains "$log" $'select-pane\t-t\t%1'
}

test_project_picker_flag_rejects_project_arg() {
  local repo fake_bin log

  repo="$TEST_TMPDIR/repo"
  make_git_repo "$repo"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"

  if EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$repo" --pick-project -p "$repo"; then
    fail "expected --pick-project with -p to fail"
  fi

  [[ ! -f "$log" ]] || fail "expected tmux not to run after invalid picker/project args"
}

test_unresolved_project_creation_rejects_two_pending_operands_before_mkdir() {
  local fake_bin log repo_target bare_target

  mkdir -p "$TEST_TMPDIR/elsewhere"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"
  repo_target="$TEST_TMPDIR/elsewhere/repo-two"
  bare_target="$TEST_TMPDIR/elsewhere/bare-two"

  if printf 'y\nrepo\n' | EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$TEST_TMPDIR/elsewhere" -p "$repo_target" feature-x develop; then
    fail "expected repo create with two operands to fail"
  fi
  assert_not_exists "$repo_target"

  rm -f "$log"
  if printf 'y\nbare\n' | EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$TEST_TMPDIR/elsewhere" -p "$bare_target" feature-x develop; then
    fail "expected bare create with two operands to fail"
  fi
  assert_not_exists "$bare_target"
}

test_bare_creation_rejects_escape_and_absolute_worktree_inputs_before_mkdir() {
  local fake_bin log escape_target absolute_target

  mkdir -p "$TEST_TMPDIR/elsewhere"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"
  escape_target="$TEST_TMPDIR/elsewhere/bare-escape"
  absolute_target="$TEST_TMPDIR/elsewhere/bare-absolute"

  if printf 'y\nbare\n' | EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$TEST_TMPDIR/elsewhere" -p "$escape_target" '../outside/foo'; then
    fail "expected bare create with escaping relative path to fail"
  fi
  assert_not_exists "$escape_target"

  rm -f "$log"
  if printf 'y\nbare\n' | EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$TEST_TMPDIR/elsewhere" -p "$absolute_target" "$TEST_TMPDIR/absolute/foo"; then
    fail "expected bare create with absolute path to fail"
  fi
  assert_not_exists "$absolute_target"
}

test_bare_creation_pending_worktree_path_becomes_branch() {
  local fake_bin log positional_target branch_target branch worktree_real

  mkdir -p "$TEST_TMPDIR/elsewhere"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"
  positional_target="$TEST_TMPDIR/elsewhere/bare-positional"
  branch_target="$TEST_TMPDIR/elsewhere/bare-branch"

  printf 'y\nbare\n' | EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$TEST_TMPDIR/elsewhere" -p "$positional_target" fix/broken-feature
  branch="$(git -C "$positional_target/.worktrees/fix/broken-feature" branch --show-current)"
  worktree_real="$(cd "$positional_target/.worktrees/fix/broken-feature" && pwd -P)"
  assert_eq "fix/broken-feature" "$branch" "expected pending positional bare worktree path to become branch"
  assert_file_contains "$log" $'-c\t'"$worktree_real"$'\tvim'

  rm -f "$log"
  printf 'y\nbare\n' | EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$TEST_TMPDIR/elsewhere" -p "$branch_target" -b fix/broken-feature
  branch="$(git -C "$branch_target/.worktrees/fix/broken-feature" branch --show-current)"
  worktree_real="$(cd "$branch_target/.worktrees/fix/broken-feature" && pwd -P)"
  assert_eq "fix/broken-feature" "$branch" "expected pending -b bare worktree path to become branch"
  assert_file_contains "$log" $'-c\t'"$worktree_real"$'\tvim'
}

test_project_picker_aliases_reject_project_branch_and_positionals() {
  local repo fake_bin alias log

  repo="$TEST_TMPDIR/repo"
  make_git_repo "$repo"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"

  for alias in -ts --ts -picker --picker -pick-project --pick-project; do
    log="$TEST_TMPDIR/tmux-${alias//[^[:alnum:]]/_}.log"

    if EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
      run_taw "$repo" "$alias" -p "$repo"; then
      fail "expected $alias with -p to fail"
    fi
    [[ ! -f "$log" ]] || fail "expected tmux not to run after $alias with -p"

    if EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
      run_taw "$repo" "$alias" -b develop; then
      fail "expected $alias with -b to fail"
    fi
    [[ ! -f "$log" ]] || fail "expected tmux not to run after $alias with -b"

    if EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
      run_taw "$repo" "$alias" feature-x; then
      fail "expected $alias with one positional to fail"
    fi
    [[ ! -f "$log" ]] || fail "expected tmux not to run after $alias with one positional"

    if EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
      run_taw "$repo" "$alias" feature-x develop; then
      fail "expected $alias with two positionals to fail"
    fi
    [[ ! -f "$log" ]] || fail "expected tmux not to run after $alias with two positionals"
  done
}

test_project_picker_aliases_allow_agent_editor_and_shells() {
  local xdg projects_home current_repo picked_repo picked_real fake_bin no_fzf_path alias log fzf_log

  xdg="$TEST_TMPDIR/xdg"
  projects_home="$TEST_TMPDIR/projects"
  current_repo="$TEST_TMPDIR/current"
  picked_repo="$projects_home/picked"
  mkdir -p "$xdg/tmux-sessionizer" "$projects_home"
  printf 'TS_SEARCH_PATHS=("%s")\n' "$projects_home" >"$xdg/tmux-sessionizer/tmux-sessionizer.conf"
  make_git_repo "$current_repo"
  make_git_repo "$picked_repo"
  picked_real="$(cd "$picked_repo" && pwd -P)"

  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  make_fake_fzf "$fake_bin"
  no_fzf_path="$(make_path_without_fzf "$fake_bin")"

  for alias in -ts --ts -picker --picker -pick-project --pick-project; do
    log="$TEST_TMPDIR/tmux-${alias//[^[:alnum:]]/_}.log"
    fzf_log="$TEST_TMPDIR/fzf-${alias//[^[:alnum:]]/_}.log"

    XDG_CONFIG_HOME="$xdg" EDITOR=vim TAW_AGENT='ignored' TAW_FAKE_FZF_MATCH="$picked_repo" \
      TAW_FAKE_FZF_MATCH_FALLBACK_OK=1 TAW_FAKE_FZF_FAIL_ON_SECOND=1 TAW_FZF_INPUT_LOG="$fzf_log" TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" \
      run_taw "$current_repo" "$alias" -agent "claude --resume" -ed "nvim ." -sh "npm test"

    assert_file_contains "$fzf_log" "$picked_repo"
    assert_file_contains "$log" $'new-session\t-d\t-P\t-F\t#{session_id}\t#{session_name}\t#{window_id}\t#{pane_id}\t-s\tpicked\t-n\tpicked\t-c\t'"$picked_real"$'\tnvim .'
    assert_file_contains "$log" $'split-window\t-h\t-P\t-F\t#{pane_id}\t-t\t%1\t-c\t'"$picked_real"$'\tclaude --resume'
    assert_file_contains "$log" $'split-window\t-v\t-P\t-F\t#{pane_id}\t-t\t%2\t-c\t'"$picked_real"$'\tnpm test'
    assert_file_contains "$log" $'select-pane\t-t\t%1'
    assert_file_not_contains "$log" $'ignored'
  done
}

test_explicit_picker_mode_aliases_are_accepted() {
  local repo repo_real fake_bin no_fzf_path mode log fzf_log expected_row

  repo="$TEST_TMPDIR/repo"
  make_git_repo "$repo"
  repo_real="$(cd "$repo" && pwd -P)"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  make_fake_fzf "$fake_bin"
  no_fzf_path="$(make_path_without_fzf "$fake_bin")"

  for mode in wt worktree b branch; do
    case "$mode" in
      wt|worktree) expected_row=$'main [worktree]\tworktree\tmain\tmain\t' ;;
      b|branch) expected_row=$'main\tbranch\tmain\tmain\t' ;;
    esac
    log="$TEST_TMPDIR/tmux-$mode.log"
    fzf_log="$TEST_TMPDIR/fzf-$mode.log"
    EDITOR=vim TAW_FAKE_FZF_MATCH=main TAW_FZF_INPUT_LOG="$fzf_log" \
      TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" \
      run_taw "$repo" --mode="$mode"

    assert_file_contains "$fzf_log" "$expected_row"
    assert_file_contains "$log" $'-c\t'"$repo_real"$'\tvim'
  done

  log="$TEST_TMPDIR/tmux-separated.log"
  EDITOR=vim TAW_FAKE_FZF_MATCH='main [worktree]' \
    TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" \
    run_taw "$repo" --mode worktree
  assert_file_contains "$log" $'-c\t'"$repo_real"$'\tvim'
}

test_session_mode_aliases_use_project_picker() {
  local xdg projects_home target target_real elsewhere fake_bin no_fzf_path mode log

  xdg="$TEST_TMPDIR/xdg"
  projects_home="$TEST_TMPDIR/projects"
  target="$projects_home/target"
  elsewhere="$TEST_TMPDIR/elsewhere"
  mkdir -p "$xdg/tmux-sessionizer" "$projects_home" "$elsewhere"
  printf 'TS_SEARCH_PATHS=("%s")\n' "$projects_home" >"$xdg/tmux-sessionizer/tmux-sessionizer.conf"
  make_git_repo "$target"
  target_real="$(cd "$target" && pwd -P)"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  make_fake_fzf "$fake_bin"
  no_fzf_path="$(make_path_without_fzf "$fake_bin")"

  for mode in ts session; do
    log="$TEST_TMPDIR/tmux-$mode.log"
    XDG_CONFIG_HOME="$xdg" EDITOR=vim TAW_FAKE_FZF_MATCH="$target" \
      TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" \
      run_taw "$elsewhere" --mode="$mode"
    assert_file_contains "$log" $'-c\t'"$target_real"$'\tvim'
  done
}

test_worktree_mode_opens_linked_normal_worktree() {
  local repo linked linked_real detached detached_real fake_bin no_fzf_path log fzf_log

  repo="$TEST_TMPDIR/repo"
  linked="$TEST_TMPDIR/develop-worktree"
  detached="$TEST_TMPDIR/detached-worktree"
  make_git_repo "$repo"
  git -C "$repo" worktree add "$linked" develop >/dev/null 2>&1
  git -C "$repo" worktree add --detach "$detached" HEAD >/dev/null 2>&1
  linked_real="$(cd "$linked" && pwd -P)"
  detached_real="$(cd "$detached" && pwd -P)"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  make_fake_fzf "$fake_bin"
  no_fzf_path="$(make_path_without_fzf "$fake_bin")"
  log="$TEST_TMPDIR/tmux.log"
  fzf_log="$TEST_TMPDIR/fzf.log"

  EDITOR=vim TAW_FAKE_FZF_MATCH='develop [worktree]' TAW_FZF_INPUT_LOG="$fzf_log" \
    TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" \
    run_taw "$repo" --mode=wt

  assert_file_contains "$fzf_log" $'develop [worktree]\tworktree\tdevelop\tdevelop\t'"$linked_real"
  assert_file_contains "$log" $'-c\t'"$linked_real"$'\tvim'
  assert_eq main "$(git -C "$repo" branch --show-current)" \
    "expected worktree mode not to switch the primary worktree"

  log="$TEST_TMPDIR/tmux-detached.log"
  fzf_log="$TEST_TMPDIR/fzf-detached.log"
  EDITOR=vim TAW_FAKE_FZF_MATCH='detached-worktree [detached]' TAW_FZF_INPUT_LOG="$fzf_log" \
    TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" \
    run_taw "$repo" --mode=worktree

  assert_file_contains "$fzf_log" $'detached-worktree [detached]\tworktree\t\t\t'"$detached_real"
  assert_file_contains "$log" $'-c\t'"$detached_real"$'\tvim'
}

test_worktree_picker_skips_control_characters_in_paths() {
  local repo repo_real unsafe_worktree fake_bin no_fzf_path log fzf_log

  repo="$TEST_TMPDIR/repo"
  unsafe_worktree="$TEST_TMPDIR/unsafe"$'\t'"worktree"
  make_git_repo "$repo"
  repo_real="$(cd "$repo" && pwd -P)"
  git -C "$repo" worktree add -qb topic "$unsafe_worktree"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  make_fake_fzf "$fake_bin"
  no_fzf_path="$(make_path_without_fzf "$fake_bin")"
  log="$TEST_TMPDIR/tmux.log"
  fzf_log="$TEST_TMPDIR/fzf.log"

  EDITOR=vim TAW_FAKE_FZF_MATCH='main [worktree]' TAW_FZF_INPUT_LOG="$fzf_log" \
    TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" \
    run_taw "$repo" --mode=worktree

  assert_file_contains "$fzf_log" $'main [worktree]\tworktree\tmain\tmain\t'"$repo_real"
  assert_file_not_contains "$fzf_log" unsafe
  assert_file_contains "$log" $'-c\t'"$repo_real"$'\tvim'
}

test_worktree_picker_preserves_spaces_and_unicode_in_paths() {
  local repo worktree worktree_real fake_bin no_fzf_path log

  repo="$TEST_TMPDIR/repo"
  worktree="$TEST_TMPDIR/linked café"
  make_git_repo "$repo"
  git -C "$repo" worktree add -qb topic "$worktree"
  worktree_real="$(cd "$worktree" && pwd -P)"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  make_fake_fzf "$fake_bin"
  no_fzf_path="$(make_path_without_fzf "$fake_bin")"
  log="$TEST_TMPDIR/tmux.log"

  EDITOR=vim TAW_FAKE_FZF_MATCH='topic [worktree]' \
    TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" \
    run_taw "$repo" --mode=worktree

  assert_file_contains "$log" $'-c\t'"$worktree_real"$'\tvim'
}

test_branch_mode_opens_existing_worktree_without_checkout() {
  local repo linked linked_real fake_bin no_fzf_path log fzf_log

  repo="$TEST_TMPDIR/repo"
  linked="$TEST_TMPDIR/develop-worktree"
  make_git_repo "$repo"
  git -C "$repo" worktree add "$linked" develop >/dev/null 2>&1
  linked_real="$(cd "$linked" && pwd -P)"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  make_fake_fzf "$fake_bin"
  no_fzf_path="$(make_path_without_fzf "$fake_bin")"
  log="$TEST_TMPDIR/tmux.log"
  fzf_log="$TEST_TMPDIR/fzf.log"

  EDITOR=vim TAW_FAKE_FZF_MATCH=develop TAW_FZF_INPUT_LOG="$fzf_log" \
    TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" \
    run_taw "$repo" --mode=b

  assert_file_contains "$fzf_log" $'develop\tbranch\tdevelop\tdevelop\t'
  assert_file_contains "$log" $'-c\t'"$linked_real"$'\tvim'
  assert_eq main "$(git -C "$repo" branch --show-current)" \
    "expected assigned branch selection not to switch the primary worktree"
}

test_branch_mode_checks_out_unassigned_normal_branch() {
  local repo repo_real fake_bin no_fzf_path log

  repo="$TEST_TMPDIR/repo"
  make_git_repo "$repo"
  repo_real="$(cd "$repo" && pwd -P)"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  make_fake_fzf "$fake_bin"
  no_fzf_path="$(make_path_without_fzf "$fake_bin")"
  log="$TEST_TMPDIR/tmux.log"

  EDITOR=vim TAW_FAKE_FZF_MATCH=develop \
    TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" \
    run_taw "$repo" --mode=branch

  assert_eq develop "$(git -C "$repo" branch --show-current)" \
    "expected branch mode to preserve normal checkout behavior"
  assert_file_contains "$log" $'-c\t'"$repo_real"$'\tvim'
}

test_branch_mode_creates_unassigned_bare_worktree() {
  local project worktree fake_bin no_fzf_path log

  project="$(make_bare_wrapper "$TEST_TMPDIR/bare")"
  worktree="$project/.worktrees/develop"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  make_fake_fzf "$fake_bin"
  no_fzf_path="$(make_path_without_fzf "$fake_bin")"
  log="$TEST_TMPDIR/tmux.log"

  EDITOR=vim TAW_FAKE_FZF_MATCH=develop \
    TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" \
    run_taw "$project" --mode=branch

  assert_eq develop "$(git -C "$worktree" branch --show-current)" \
    "expected branch mode to create the selected bare worktree"
  assert_file_contains "$log" $'-c\t'"$(cd "$worktree" && pwd -P)"$'\tvim'
}

test_picker_selects_fzf_bindings_by_version() {
  local repo fake_bin no_fzf_path version version_name log args_log

  repo="$TEST_TMPDIR/repo"
  make_git_repo "$repo"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  make_fake_fzf "$fake_bin"
  no_fzf_path="$(make_path_without_fzf "$fake_bin")"

  for version in 0.53.0 1.0.0; do
    version_name="${version//[^[:alnum:]]/_}"
    log="$TEST_TMPDIR/tmux-modern-$version_name.log"
    args_log="$TEST_TMPDIR/fzf-modern-$version_name.log"
    EDITOR=vim TAW_FAKE_FZF_VERSION="$version" \
      TAW_FAKE_FZF_MATCH='main [worktree]' TAW_FZF_ARGS_LOG="$args_log" \
      TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" \
      run_taw "$repo" --mode=worktree

    assert_file_contains "$args_log" '--expect=tab'
    assert_file_contains "$args_log" 'enter:transform:'
    assert_file_contains "$args_log" 'print()+accept'
    assert_file_not_contains "$args_log" '--expect=tab,ctrl-s'
  done

  for version in 0.52.1 unknown; do
    version_name="${version//[^[:alnum:]]/_}"
    log="$TEST_TMPDIR/tmux-legacy-$version_name.log"
    args_log="$TEST_TMPDIR/fzf-legacy-$version_name.log"
    EDITOR=vim TAW_FAKE_FZF_VERSION="$version" \
      TAW_FAKE_FZF_MATCH='main [worktree]' TAW_FZF_ARGS_LOG="$args_log" \
      TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" \
      run_taw "$repo" --mode=worktree

    assert_file_contains "$args_log" \
      '--expect=tab,ctrl-s,ctrl-a,alt-z,alt-a,alt-enter'
    assert_file_not_contains "$args_log" ':transform:'
    assert_file_not_contains "$args_log" 'print('
  done

  log="$TEST_TMPDIR/tmux-version-failure.log"
  args_log="$TEST_TMPDIR/fzf-version-failure.log"
  EDITOR=vim TAW_FAKE_FZF_VERSION_STATUS=1 \
    TAW_FAKE_FZF_MATCH='main [worktree]' TAW_FZF_ARGS_LOG="$args_log" \
    TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" \
    run_taw "$repo" --mode=worktree
  assert_file_contains "$args_log" \
    '--expect=tab,ctrl-s,ctrl-a,alt-z,alt-a,alt-enter'
  assert_file_not_contains "$args_log" ':transform:'
}

test_legacy_picker_reports_producer_failure_before_fzf() {
  local xdg empty_search session_path elsewhere fake_bin no_fzf_path
  local sessions log args_log picker_tmp output

  xdg="$TEST_TMPDIR/xdg"
  empty_search="$TEST_TMPDIR/empty"
  session_path="$TEST_TMPDIR/session-path"
  elsewhere="$TEST_TMPDIR/elsewhere"
  picker_tmp="$TEST_TMPDIR/picker-tmp"
  mkdir -p "$xdg/tmux-sessionizer" "$empty_search" "$session_path" \
    "$elsewhere" "$picker_tmp"
  printf 'TS_SEARCH_PATHS=("%s")\n' "$empty_search" >"$xdg/tmux-sessionizer/tmux-sessionizer.conf"
  sessions=$'$7\tunsafe\tname\t'"$session_path"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  make_fake_fzf "$fake_bin"
  no_fzf_path="$(make_path_without_fzf "$fake_bin")"
  log="$TEST_TMPDIR/tmux.log"
  args_log="$TEST_TMPDIR/fzf-args.log"

  if output="$(XDG_CONFIG_HOME="$xdg" TMPDIR="$picker_tmp" EDITOR=vim \
    TAW_FAKE_FZF_VERSION=0.52.1 TAW_FAKE_TMUX_SESSIONS="$sessions" \
    TAW_FZF_ARGS_LOG="$args_log" TAW_FAKE_TMUX_BIN="$fake_bin" \
    TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" \
    run_taw "$elsewhere" --mode=session 2>&1)"; then
    fail "expected a legacy picker producer failure to fail"
  fi

  assert_string_contains "$output" \
    "tmux session contains control characters and cannot be used by the picker"
  assert_not_exists "$args_log"
  assert_no_tmux_work_window "$log"
  if compgen -G "$picker_tmp/taw-picker.*" >/dev/null; then
    fail "expected legacy picker snapshot files to be cleaned up after failure"
  fi
}

test_picker_accept_keys_select_layouts() {
  local xdg projects_home target target_real elsewhere fake_bin no_fzf_path log args_log

  xdg="$TEST_TMPDIR/xdg"
  projects_home="$TEST_TMPDIR/projects"
  target="$projects_home/target"
  elsewhere="$TEST_TMPDIR/elsewhere"
  mkdir -p "$xdg/tmux-sessionizer" "$projects_home" "$elsewhere"
  printf 'TS_SEARCH_PATHS=("%s")\n' "$projects_home" >"$xdg/tmux-sessionizer/tmux-sessionizer.conf"
  make_git_repo "$target"
  target_real="$(cd "$target" && pwd -P)"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  make_fake_fzf "$fake_bin"
  no_fzf_path="$(make_path_without_fzf "$fake_bin")"

  log="$TEST_TMPDIR/tmux-shell.log"
  XDG_CONFIG_HOME="$xdg" EDITOR=vim TAW_AGENT='env-agent' TAW_FAKE_FZF_KEYS=ctrl-s \
    TAW_FAKE_FZF_MATCH="$target" TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    TAW_RUN_PATH="$no_fzf_path" run_taw "$elsewhere" -ts
  assert_file_contains "$log" $'-s\ttarget\t-n\ttarget\t-c\t'"$target_real"
  assert_file_not_contains "$log" $'split-window\t'
  assert_file_not_contains "$log" $'\tvim'
  assert_file_not_contains "$log" $'env-agent'
  assert_file_contains "$log" $'select-pane\t-t\t%1'

  log="$TEST_TMPDIR/tmux-agent.log"
  XDG_CONFIG_HOME="$xdg" EDITOR=vim TAW_AGENT='  env-agent  ' TAW_FAKE_FZF_KEYS=ctrl-a \
    TAW_FAKE_FZF_MATCH="$target" TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    TAW_RUN_PATH="$no_fzf_path" run_taw "$elsewhere" -ts
  assert_file_contains "$log" $'-s\ttarget\t-n\ttarget\t-c\t'"$target_real"$'\tenv-agent'
  assert_file_not_contains "$log" $'split-window\t'
  assert_file_not_contains "$log" $'\tvim'
  assert_file_contains "$log" $'select-pane\t-t\t%1'

  log="$TEST_TMPDIR/tmux-editor-shell.log"
  args_log="$TEST_TMPDIR/fzf-args.log"
  XDG_CONFIG_HOME="$xdg" EDITOR=vim TAW_AGENT='env-agent' TAW_FAKE_FZF_KEYS=alt-z \
    TAW_FAKE_FZF_MATCH="$target" TAW_FZF_ARGS_LOG="$args_log" \
    TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" \
    run_taw "$elsewhere" -ts -sh "npm test" -sh "echo later"
  assert_file_contains "$args_log" '--expect=tab'
  assert_file_contains "$args_log" 'ctrl-s:transform:[[ -n {2} && {2} != message ]]'
  assert_file_contains "$args_log" 'print(ctrl-s)+accept'
  assert_file_contains "$args_log" 'Opt-Z: editor+shell'
  assert_file_not_contains "$args_log" 'Opt-S:'
  assert_file_contains "$log" $'-s\ttarget\t-n\ttarget\t-c\t'"$target_real"$'\tvim'
  assert_file_contains "$log" $'split-window\t-h\t-P\t-F\t#{pane_id}\t-t\t%1\t-c\t'"$target_real"$'\tnpm test'
  assert_file_contains "$log" $'split-window\t-h\t-P\t-F\t#{pane_id}\t-t\t%2\t-c\t'"$target_real"$'\techo later'
  assert_file_not_contains "$log" $'env-agent'
  assert_file_not_contains "$log" $'split-window\t-v\t'
  assert_file_contains "$log" $'select-pane\t-t\t%1'

  log="$TEST_TMPDIR/tmux-editor-agent.log"
  XDG_CONFIG_HOME="$xdg" EDITOR=vim TAW_AGENT='env-agent' TAW_FAKE_FZF_KEYS=alt-a \
    TAW_FAKE_FZF_MATCH="$target" TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    TAW_RUN_PATH="$no_fzf_path" run_taw "$elsewhere" -ts -agent "claude --resume"
  assert_file_contains "$log" $'-s\ttarget\t-n\ttarget\t-c\t'"$target_real"$'\tvim'
  assert_file_contains "$log" $'split-window\t-h\t-P\t-F\t#{pane_id}\t-t\t%1\t-c\t'"$target_real"$'\tclaude --resume'
  assert_file_not_contains "$log" $'env-agent'
  assert_file_not_contains "$log" $'split-window\t-v\t'
  assert_file_contains "$log" $'select-pane\t-t\t%1'

  log="$TEST_TMPDIR/tmux-all.log"
  XDG_CONFIG_HOME="$xdg" EDITOR=vim TAW_AGENT='env-agent' TAW_FAKE_FZF_KEYS=alt-enter \
    TAW_FAKE_FZF_MATCH="$target" TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    TAW_RUN_PATH="$no_fzf_path" run_taw "$elsewhere" -ts
  assert_file_contains "$log" $'-s\ttarget\t-n\ttarget\t-c\t'"$target_real"$'\tvim'
  assert_file_contains "$log" $'split-window\t-h\t-P\t-F\t#{pane_id}\t-t\t%1\t-c\t'"$target_real"$'\tenv-agent'
  assert_file_contains "$log" $'split-window\t-v\t-P\t-F\t#{pane_id}\t-t\t%2\t-c\t'"$target_real"
  assert_file_contains "$log" $'select-pane\t-t\t%1'
}

test_picker_layout_keys_apply_to_worktree_and_branch_modes() {
  local repo repo_real fake_bin no_fzf_path log

  repo="$TEST_TMPDIR/repo"
  make_git_repo "$repo"
  repo_real="$(cd "$repo" && pwd -P)"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  make_fake_fzf "$fake_bin"
  no_fzf_path="$(make_path_without_fzf "$fake_bin")"

  log="$TEST_TMPDIR/tmux-worktree.log"
  EDITOR=vim TAW_FAKE_FZF_KEYS=ctrl-s TAW_FAKE_FZF_MATCH='main [worktree]' \
    TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" \
    run_taw "$repo" --mode=worktree -sh worktree-shell
  assert_file_contains "$log" $'-s\trepo\t-n\trepo\t-c\t'"$repo_real"$'\tworktree-shell'
  assert_file_not_contains "$log" $'\tvim'
  assert_file_not_contains "$log" $'split-window\t'

  log="$TEST_TMPDIR/tmux-branch.log"
  EDITOR=vim TAW_FAKE_FZF_KEYS=alt-a TAW_FAKE_FZF_MATCH=main \
    TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" \
    run_taw "$repo" --mode=branch -agent branch-agent
  assert_file_contains "$log" $'-s\trepo\t-n\trepo\t-c\t'"$repo_real"$'\tvim'
  assert_file_contains "$log" $'split-window\t-h\t-P\t-F\t#{pane_id}\t-t\t%1\t-c\t'"$repo_real"$'\tbranch-agent'
}

test_picker_layout_is_ignored_for_matching_window() {
  local repo repo_real fake_bin no_fzf_path log sessions panes

  repo="$TEST_TMPDIR/repo"
  make_git_repo "$repo"
  repo_real="$(cd "$repo" && pwd -P)"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  make_fake_fzf "$fake_bin"
  no_fzf_path="$(make_path_without_fzf "$fake_bin")"
  log="$TEST_TMPDIR/tmux.log"
  sessions=$'$1\trepo\t'"$repo_real"
  panes=$'@8\t%8\t'"$repo_real"$'\n'

  EDITOR=vim TAW_AGENT=env-agent TAW_FAKE_FZF_KEYS=alt-enter \
    TAW_FAKE_FZF_MATCH='main [worktree]' TAW_FAKE_TMUX_SESSIONS="$sessions" \
    TAW_FAKE_TMUX_PANES="$panes" TAW_FAKE_TMUX_BIN="$fake_bin" \
    TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" run_taw "$repo" --mode=worktree

  assert_file_contains "$log" $'select-window\t-t\t@8'
  assert_file_contains "$log" $'select-pane\t-t\t%8'
  assert_file_not_contains "$log" $'new-window\t'
  assert_file_not_contains "$log" $'new-session\t'
  assert_file_not_contains "$log" $'split-window\t'
  assert_file_not_contains "$log" $'env-agent'
}

test_picker_layout_creates_window_in_existing_session() {
  local repo repo_real worktree worktree_real fake_bin no_fzf_path log sessions panes

  repo="$TEST_TMPDIR/repo"
  worktree="$repo/.worktrees/develop"
  make_git_repo "$repo"
  git -C "$repo" worktree add -q "$worktree" develop
  repo_real="$(cd "$repo" && pwd -P)"
  worktree_real="$(cd "$worktree" && pwd -P)"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  make_fake_fzf "$fake_bin"
  no_fzf_path="$(make_path_without_fzf "$fake_bin")"
  log="$TEST_TMPDIR/tmux.log"
  sessions=$'$1\trepo\t'"$repo_real"
  panes=$'@8\t%8\t'"$repo_real"$'\n'

  EDITOR=vim TAW_FAKE_FZF_KEYS=alt-z TAW_FAKE_FZF_MATCH='develop [worktree]' \
    TAW_FAKE_TMUX_SESSIONS="$sessions" TAW_FAKE_TMUX_PANES="$panes" \
    TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" \
    run_taw "$repo" --mode=worktree

  assert_file_contains "$log" $'new-window\t-d\t-P\t-F\t#{window_id} #{pane_id}\t-t\t$1:\t-n\tdevelop\t-c\t'"$worktree_real"$'\tvim'
  assert_file_contains "$log" $'split-window\t-h\t-P\t-F\t#{pane_id}\t-t\t%1\t-c\t'"$worktree_real"
  assert_file_contains "$log" $'select-pane\t-t\t%1'
  assert_file_not_contains "$log" $'new-session\t'
}

test_picker_tab_cycles_all_modes_and_preserves_query() {
  local xdg projects_home repo target target_real fake_bin no_fzf_path log args_log
  local -a fzf_args

  xdg="$TEST_TMPDIR/xdg"
  projects_home="$TEST_TMPDIR/projects"
  repo="$TEST_TMPDIR/repo"
  target="$projects_home/target"
  mkdir -p "$xdg/tmux-sessionizer" "$projects_home"
  printf 'TS_SEARCH_PATHS=("%s")\n' "$projects_home" >"$xdg/tmux-sessionizer/tmux-sessionizer.conf"
  make_git_repo "$repo"
  make_git_repo "$target"
  target_real="$(cd "$target" && pwd -P)"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  make_fake_fzf "$fake_bin"
  no_fzf_path="$(make_path_without_fzf "$fake_bin")"
  log="$TEST_TMPDIR/tmux.log"
  args_log="$TEST_TMPDIR/fzf-args.log"

  XDG_CONFIG_HOME="$xdg" EDITOR=vim TAW_FAKE_FZF_KEYS=$'tab\ntab\ntab\nnone' \
    TAW_FAKE_FZF_OUTPUT_QUERIES=$'needle\nneedle\nneedle\nneedle' \
    TAW_FAKE_FZF_MATCH="$target" TAW_FZF_ARGS_LOG="$args_log" \
    TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" \
    run_taw "$repo" -ts

  mapfile -t fzf_args <"$args_log"
  assert_eq 4 "${#fzf_args[@]}" "expected one fzf invocation per visited mode"
  assert_string_contains "${fzf_args[0]}" $'--prompt=session> '
  assert_string_contains "${fzf_args[1]}" $'--prompt=worktree> '
  assert_string_contains "${fzf_args[2]}" $'--prompt=branch> '
  assert_string_contains "${fzf_args[3]}" $'--prompt=session> '
  assert_string_contains "${fzf_args[1]}" '--query=needle'
  assert_string_contains "${fzf_args[2]}" '--query=needle'
  assert_string_contains "${fzf_args[3]}" '--query=needle'
  assert_file_contains "$log" $'-c\t'"$target_real"$'\tvim'
}

test_each_explicit_mode_can_cycle_from_its_start() {
  local xdg projects_home repo target fake_bin no_fzf_path mode expected match log args_log
  local -a fzf_args

  xdg="$TEST_TMPDIR/xdg"
  projects_home="$TEST_TMPDIR/projects"
  repo="$TEST_TMPDIR/repo"
  target="$projects_home/target"
  mkdir -p "$xdg/tmux-sessionizer" "$projects_home"
  printf 'TS_SEARCH_PATHS=("%s")\n' "$projects_home" >"$xdg/tmux-sessionizer/tmux-sessionizer.conf"
  make_git_repo "$repo"
  make_git_repo "$target"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  make_fake_fzf "$fake_bin"
  no_fzf_path="$(make_path_without_fzf "$fake_bin")"

  for mode in ts wt b; do
    case "$mode" in
      ts) expected=worktree; match='main [worktree]' ;;
      wt) expected=branch; match=main ;;
      b) expected=session; match="$target" ;;
    esac
    log="$TEST_TMPDIR/tmux-$mode.log"
    args_log="$TEST_TMPDIR/fzf-args-$mode.log"
    XDG_CONFIG_HOME="$xdg" EDITOR=vim TAW_FAKE_FZF_KEYS=$'tab\nnone' \
      TAW_FAKE_FZF_MATCH="$match" TAW_FZF_ARGS_LOG="$args_log" \
      TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" \
      run_taw "$repo" --mode="$mode"

    mapfile -t fzf_args <"$args_log"
    assert_eq 2 "${#fzf_args[@]}" "expected $mode to cycle once"
    assert_string_contains "${fzf_args[1]}" "--prompt=$expected> "
  done
}

test_session_selection_after_project_mode_replaces_context() {
  local xdg projects_home launch launch_worktree target target_worktree
  local fake_bin no_fzf_path log

  xdg="$TEST_TMPDIR/xdg"
  projects_home="$TEST_TMPDIR/projects"
  mkdir -p "$xdg/tmux-sessionizer" "$projects_home"
  printf 'TS_SEARCH_PATHS=("%s")\n' "$projects_home" >"$xdg/tmux-sessionizer/tmux-sessionizer.conf"
  launch="$(make_bare_wrapper "$TEST_TMPDIR/launch")"
  git --git-dir "$launch/.git" worktree add "$launch/main" main >/dev/null 2>&1
  launch_worktree="$(cd "$launch/main" && pwd -P)"
  target="$(make_bare_wrapper "$projects_home")"
  target_worktree="$target/.worktrees/main"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  make_fake_fzf "$fake_bin"
  no_fzf_path="$(make_path_without_fzf "$fake_bin")"
  log="$TEST_TMPDIR/tmux.log"

  XDG_CONFIG_HOME="$xdg" EDITOR=vim TAW_FAKE_FZF_KEYS=$'tab\nnone' \
    TAW_FAKE_FZF_MATCH="$target" TAW_FAKE_TMUX_BIN="$fake_bin" \
    TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" \
    run_taw "$launch_worktree" --mode=b

  assert_file_contains "$log" $'-c\t'"$(cd "$target_worktree" && pwd -P)"$'\tvim'
  assert_file_not_contains "$log" $'-c\t'"$launch_worktree"$'\tvim'
}

test_project_scoped_modes_remain_cycleable_outside_git() {
  local xdg projects_home target target_real elsewhere fake_bin no_fzf_path
  local log fzf_log args_log
  local -a fzf_args

  xdg="$TEST_TMPDIR/xdg"
  projects_home="$TEST_TMPDIR/projects"
  target="$projects_home/target"
  elsewhere="$TEST_TMPDIR/elsewhere"
  mkdir -p "$xdg/tmux-sessionizer" "$projects_home" "$elsewhere"
  printf 'TS_SEARCH_PATHS=("%s")\n' "$projects_home" >"$xdg/tmux-sessionizer/tmux-sessionizer.conf"
  make_git_repo "$target"
  target_real="$(cd "$target" && pwd -P)"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  make_fake_fzf "$fake_bin"
  no_fzf_path="$(make_path_without_fzf "$fake_bin")"
  log="$TEST_TMPDIR/tmux.log"
  fzf_log="$TEST_TMPDIR/fzf.log"
  args_log="$TEST_TMPDIR/fzf-args.log"

  XDG_CONFIG_HOME="$xdg" EDITOR=vim TAW_AGENT=ignored \
    TAW_FAKE_FZF_VERSION=0.52.1 \
    TAW_FAKE_FZF_KEYS=$'ctrl-s\ntab\nalt-enter\ntab\nnone' \
    TAW_FAKE_FZF_OUTPUT_QUERIES=$'needle\nneedle\nneedle\nneedle\nneedle' \
    TAW_FAKE_TMUX_SESSIONS= TAW_FZF_INPUT_LOG="$fzf_log" \
    TAW_FZF_ARGS_LOG="$args_log" TAW_FAKE_TMUX_BIN="$fake_bin" \
    TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" \
    run_taw "$elsewhere" --mode=worktree

  assert_file_contains "$fzf_log" $'Not in a Git project\tmessage\t\t\t'
  mapfile -t fzf_args <"$args_log"
  assert_eq "5" "${#fzf_args[@]}" "expected informational rows to remain in their modes"
  assert_string_contains "${fzf_args[0]}" '--prompt=worktree> '
  assert_string_contains "${fzf_args[1]}" '--prompt=worktree> '
  assert_string_contains "${fzf_args[2]}" '--prompt=branch> '
  assert_string_contains "${fzf_args[3]}" '--prompt=branch> '
  assert_string_contains "${fzf_args[4]}" '--prompt=session> '
  assert_string_contains "${fzf_args[0]}" \
    '--expect=tab,ctrl-s,ctrl-a,alt-z,alt-a,alt-enter'
  assert_string_contains "${fzf_args[1]}" '--query=needle'
  assert_file_not_contains "$args_log" ':transform:'
  assert_file_not_contains "$args_log" 'print('
  assert_file_contains "$log" $'-s\ttarget\t-n\ttarget\t-c\t'"$target_real"$'\tvim'
  assert_file_not_contains "$log" $'split-window\t'
  assert_file_not_contains "$log" 'ignored'
}

test_explicit_picker_keeps_empty_modes_cycleable() {
  local xdg empty_search elsewhere unborn bare fake_bin log args_log fzf_log

  xdg="$TEST_TMPDIR/xdg"
  empty_search="$TEST_TMPDIR/empty"
  elsewhere="$TEST_TMPDIR/elsewhere"
  unborn="$TEST_TMPDIR/unborn"
  mkdir -p "$xdg/tmux-sessionizer" "$empty_search" "$elsewhere" "$unborn"
  printf 'TS_SEARCH_PATHS=("%s")\n' "$empty_search" >"$xdg/tmux-sessionizer/tmux-sessionizer.conf"
  git -C "$unborn" init -q -b main
  bare="$(make_bare_wrapper "$TEST_TMPDIR/bare")"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  make_fake_fzf "$fake_bin"
  args_log="$TEST_TMPDIR/fzf-args.log"

  log="$TEST_TMPDIR/tmux-session.log"
  fzf_log="$TEST_TMPDIR/fzf-session.log"
  XDG_CONFIG_HOME="$xdg" EDITOR=vim TAW_FAKE_TMUX_SESSIONS= \
    TAW_FAKE_FZF_KEYS=$'ctrl-s\ntab\ncancel' TAW_FZF_INPUT_LOG="$fzf_log" \
    TAW_FZF_ARGS_LOG="$args_log" TAW_FAKE_TMUX_BIN="$fake_bin" \
    TAW_TMUX_LOG="$log" run_taw "$elsewhere" --mode=session
  assert_file_contains "$fzf_log" $'Picker has no targets\tmessage\t\t\t'
  assert_file_contains "$args_log" 'load:transform:[ "$FZF_TOTAL_COUNT" -eq 0 ] && printf abort'
  assert_no_tmux_work_window "$log"

  log="$TEST_TMPDIR/tmux-branch.log"
  fzf_log="$TEST_TMPDIR/fzf-branch.log"
  XDG_CONFIG_HOME="$xdg" EDITOR=vim TAW_FAKE_TMUX_SESSIONS= \
    TAW_FAKE_FZF_KEYS=$'ctrl-s\ntab\ncancel' TAW_FZF_INPUT_LOG="$fzf_log" \
    TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$unborn" --mode=branch
  assert_file_contains "$fzf_log" $'Picker has no targets\tmessage\t\t\t'
  assert_no_tmux_work_window "$log"

  log="$TEST_TMPDIR/tmux-worktree.log"
  fzf_log="$TEST_TMPDIR/fzf-worktree.log"
  XDG_CONFIG_HOME="$xdg" EDITOR=vim TAW_FAKE_TMUX_SESSIONS= \
    TAW_FAKE_FZF_KEYS=$'ctrl-s\ntab\ncancel' TAW_FZF_INPUT_LOG="$fzf_log" \
    TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$bare" --mode=worktree
  assert_file_contains "$fzf_log" $'Picker has no targets\tmessage\t\t\t'
  assert_no_tmux_work_window "$log"
}

test_invalid_picker_modes_and_combinations_are_rejected() {
  local repo fake_bin log output

  repo="$TEST_TMPDIR/repo"
  make_git_repo "$repo"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"

  if output="$(TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$repo" --mode=nope 2>&1)"; then
    fail "expected unknown picker mode to fail"
  fi
  assert_string_contains "$output" "unknown picker mode: nope"

  if output="$(TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$repo" --mode=wt -p "$repo" 2>&1)"; then
    fail "expected picker mode with -p to fail"
  fi
  assert_string_contains "$output" "picker mode cannot be combined"

  if output="$(TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$repo" -ts --mode=b 2>&1)"; then
    fail "expected duplicate picker modes to fail"
  fi
  assert_string_contains "$output" "picker mode may only be specified once"
  assert_no_tmux_work_window "$log"
}

test_peer_creates_window_in_current_session() {
  local repo repo_real fake_bin no_fzf_path log

  repo="$TEST_TMPDIR/repo"
  make_git_repo "$repo"
  repo_real="$(cd "$repo" && pwd -P)"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  no_fzf_path="$(make_path_without_fzf "$fake_bin")"
  log="$TEST_TMPDIR/tmux.log"

  EDITOR=vim TAW_TEST_TMUX=/tmp/tmux TAW_FAKE_TMUX_CURRENT_SESSION_ID='$7' \
    TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" \
    run_taw "$repo" --peer -p "$repo"

  assert_file_contains "$log" $'display-message\t-p\t#{session_id}'
  assert_file_contains "$log" $'new-window\t-d\t-P\t-F\t#{window_id} #{pane_id}\t-t\t$7:\t-n\trepo\t-c\t'"$repo_real"$'\tvim'
  assert_file_contains "$log" $'select-window\t-t\t@1'
  assert_file_not_contains "$log" $'new-session\t'
  assert_file_not_contains "$log" $'attach-session\t'
  assert_file_not_contains "$log" $'switch-client\t'
}

test_removed_peer_names_are_rejected() {
  local repo fake_bin log option output

  repo="$TEST_TMPDIR/repo"
  make_git_repo "$repo"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"

  for option in --periscope --ps --peri; do
    log="$TEST_TMPDIR/tmux-${option#--}.log"
    if output="$(
      TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
        run_taw "$repo" "$option" -p "$repo" 2>&1
    )"; then
      fail "expected removed peer option to fail: $option"
    fi
    assert_string_contains "$output" "unknown option: $option"
    assert_no_tmux_work_window "$log"
  done
}

test_peer_requires_current_tmux_before_resolution() {
  local repo fake_bin log output branch

  repo="$TEST_TMPDIR/repo"
  make_git_repo "$repo"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"
  branch="$(git -C "$repo" branch --show-current)"

  if output="$(
    TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
      run_taw "$repo" --peer -p "$repo" develop 2>&1
  )"; then
    fail "expected peer outside tmux to fail"
  fi

  assert_eq "$branch" "$(git -C "$repo" branch --show-current)" \
    "expected peer to fail before checkout"
  assert_string_contains "$output" "--peer requires an active tmux client"
  assert_no_tmux_work_window "$log"
}

test_force_requires_peer() {
  local repo fake_bin log output

  repo="$TEST_TMPDIR/repo"
  make_git_repo "$repo"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"

  if output="$(
    TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
      run_taw "$repo" --force -p "$repo" 2>&1
  )"; then
    fail "expected standalone --force to fail"
  fi

  assert_string_contains "$output" "--force requires --peer"
  assert_no_tmux_work_window "$log"
}

test_peer_prefers_current_session_descendant_match() {
  local repo repo_real fake_bin no_fzf_path log panes

  repo="$TEST_TMPDIR/repo"
  make_git_repo "$repo"
  mkdir -p "$repo/src"
  repo_real="$(cd "$repo" && pwd -P)"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  no_fzf_path="$(make_path_without_fzf "$fake_bin")"
  log="$TEST_TMPDIR/tmux.log"
  panes=$'$3\tother\t@30\t%30\t'"$repo_real"$'\n'
  panes+=$'$2\trepo\t@20\t%20\t'"$repo_real"$'\n'
  panes+=$'$1\tcurrent\t@10\t%10\t'"$repo_real"$'/src\n'

  EDITOR=vim TAW_TEST_TMUX=/tmp/tmux TAW_FAKE_TMUX_CURRENT_SESSION_ID='$1' \
    TAW_FAKE_TMUX_ALL_PANES="$panes" TAW_FAKE_TMUX_BIN="$fake_bin" \
    TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" \
    run_taw "$repo" --peer -p "$repo"

  assert_file_contains "$log" $'select-window\t-t\t@10'
  assert_file_not_contains "$log" $'select-pane\t-t\t%10'
  assert_file_not_contains "$log" $'link-window\t'
  assert_file_not_contains "$log" $'new-window\t'
}

test_peer_links_project_session_match() {
  local repo repo_real fake_bin no_fzf_path log panes

  repo="$TEST_TMPDIR/repo"
  make_git_repo "$repo"
  repo_real="$(cd "$repo" && pwd -P)"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  no_fzf_path="$(make_path_without_fzf "$fake_bin")"
  log="$TEST_TMPDIR/tmux.log"
  panes=$'$3\tother\t@30\t%30\t'"$repo_real"$'\n'
  panes+=$'$2\trepo\t@20\t%20\t'"$repo_real"$'\n'

  EDITOR=vim TAW_TEST_TMUX=/tmp/tmux TAW_FAKE_TMUX_CURRENT_SESSION_ID='$1' \
    TAW_FAKE_TMUX_ALL_PANES="$panes" TAW_FAKE_TMUX_BIN="$fake_bin" \
    TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" \
    run_taw "$repo" --peer -p "$repo"

  assert_file_contains "$log" $'link-window\t-d\t-s\t@20\t-t\t$1:'
  assert_file_contains "$log" $'select-window\t-t\t@20'
  assert_file_contains "$log" $'select-pane\t-t\t%20'
  assert_file_not_contains "$log" $'new-window\t'
}

test_peer_links_other_session_match() {
  local repo repo_real fake_bin no_fzf_path log panes

  repo="$TEST_TMPDIR/repo"
  make_git_repo "$repo"
  repo_real="$(cd "$repo" && pwd -P)"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  no_fzf_path="$(make_path_without_fzf "$fake_bin")"
  log="$TEST_TMPDIR/tmux.log"
  panes=$'$3\tunrelated\t@30\t%30\t'"$repo_real"$'\n'

  EDITOR=vim TAW_TEST_TMUX=/tmp/tmux TAW_FAKE_TMUX_CURRENT_SESSION_ID='$1' \
    TAW_FAKE_TMUX_ALL_PANES="$panes" TAW_FAKE_TMUX_BIN="$fake_bin" \
    TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" \
    run_taw "$repo" --peer -p "$repo"

  assert_file_contains "$log" $'link-window\t-d\t-s\t@30\t-t\t$1:'
  assert_file_contains "$log" $'select-pane\t-t\t%30'
  assert_file_not_contains "$log" $'new-window\t'
}

test_peer_layout_conflict_requires_force() {
  local repo repo_real fake_bin no_fzf_path log panes output

  repo="$TEST_TMPDIR/repo"
  make_git_repo "$repo"
  repo_real="$(cd "$repo" && pwd -P)"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  no_fzf_path="$(make_path_without_fzf "$fake_bin")"
  log="$TEST_TMPDIR/tmux.log"
  panes=$'$2\trepo\t@20\t%20\t'"$repo_real"$'\n'

  if output="$(
    EDITOR=vim TAW_TEST_TMUX=/tmp/tmux TAW_FAKE_TMUX_CURRENT_SESSION_ID='$1' \
      TAW_FAKE_TMUX_ALL_PANES="$panes" TAW_FAKE_TMUX_BIN="$fake_bin" \
      TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" \
      run_taw "$repo" --peer -p "$repo" -ed "nvim ." 2>&1
  )"; then
    fail "expected peer layout conflict to fail"
  fi

  assert_string_contains "$output" "use --force to create a fresh layout"
  assert_file_not_contains "$log" $'link-window\t'
  assert_file_not_contains "$log" $'new-window\t'

  : >"$log"
  EDITOR=vim TAW_TEST_TMUX=/tmp/tmux TAW_FAKE_TMUX_CURRENT_SESSION_ID='$1' \
    TAW_FAKE_TMUX_ALL_PANES="$panes" TAW_FAKE_TMUX_BIN="$fake_bin" \
    TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" \
    run_taw "$repo" --peer --force -p "$repo" -ed "nvim ."

  assert_file_contains "$log" $'new-window\t-d\t-P\t-F\t#{window_id} #{pane_id}\t-t\t$1:\t-n\trepo\t-c\t'"$repo_real"$'\tnvim .'
  assert_file_not_contains "$log" $'list-panes\t-a'
  assert_file_not_contains "$log" $'link-window\t'
}

test_peer_taw_agent_conflict_requires_force() {
  local repo repo_real fake_bin no_fzf_path log panes output

  repo="$TEST_TMPDIR/repo"
  make_git_repo "$repo"
  repo_real="$(cd "$repo" && pwd -P)"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  no_fzf_path="$(make_path_without_fzf "$fake_bin")"
  log="$TEST_TMPDIR/tmux.log"
  panes=$'$2\trepo\t@20\t%20\t'"$repo_real"$'\n'

  if output="$(
    TAW_AGENT=claude EDITOR=vim TAW_TEST_TMUX=/tmp/tmux \
      TAW_FAKE_TMUX_CURRENT_SESSION_ID='$1' TAW_FAKE_TMUX_ALL_PANES="$panes" \
      TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" \
      run_taw "$repo" --peer -p "$repo" 2>&1
  )"; then
    fail "expected peer TAW_AGENT conflict to fail"
  fi

  assert_string_contains "$output" "use --force to create a fresh layout"
  assert_file_not_contains "$log" $'link-window\t'
  assert_file_not_contains "$log" $'new-window\t'
}

test_peer_normal_branch_resolution_is_unchanged() {
  local current_repo repo fake_bin no_fzf_path log

  current_repo="$TEST_TMPDIR/current"
  repo="$TEST_TMPDIR/repo"
  make_git_repo "$current_repo"
  make_git_repo "$repo"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  no_fzf_path="$(make_path_without_fzf "$fake_bin")"
  log="$TEST_TMPDIR/tmux.log"

  EDITOR=vim TAW_TEST_TMUX=/tmp/tmux TAW_FAKE_TMUX_CURRENT_SESSION_ID='$1' \
    TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" \
    run_taw "$current_repo" --peer "$repo" develop

  assert_eq "develop" "$(git -C "$repo/.worktrees/develop" branch --show-current)" \
    "expected peer to create the requested worktree"
  assert_eq "main" "$(git -C "$repo" branch --show-current)" \
    "expected peer to preserve the primary worktree branch"
  assert_eq "main" "$(git -C "$current_repo" branch --show-current)" \
    "expected peer not to treat target arguments as current-project branches"
  assert_file_contains "$log" $'new-window\t-d\t-P\t-F\t#{window_id} #{pane_id}\t-t\t$1:'
  assert_file_not_contains "$log" $'new-session\t'
}

test_peer_single_positional_targets_project_inside_repo() {
  local current_repo target target_real fake_bin no_fzf_path log

  current_repo="$TEST_TMPDIR/current"
  target="$TEST_TMPDIR/target"
  make_git_repo "$current_repo"
  make_git_repo "$target"
  target_real="$(cd "$target" && pwd -P)"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  no_fzf_path="$(make_path_without_fzf "$fake_bin")"
  log="$TEST_TMPDIR/tmux.log"

  EDITOR=vim TAW_TEST_TMUX=/tmp/tmux TAW_FAKE_TMUX_CURRENT_SESSION_ID='$1' \
    TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" \
    run_taw "$current_repo" --peer "$target"

  assert_file_contains "$log" $'new-window\t-d\t-P\t-F\t#{window_id} #{pane_id}\t-t\t$1:\t-n\ttarget\t-c\t'"$target_real"$'\tvim'
}

test_peer_positional_project_accepts_branch_flag() {
  local current_repo target fake_bin no_fzf_path log

  current_repo="$TEST_TMPDIR/current"
  target="$TEST_TMPDIR/target"
  make_git_repo "$current_repo"
  make_git_repo "$target"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  no_fzf_path="$(make_path_without_fzf "$fake_bin")"
  log="$TEST_TMPDIR/tmux.log"

  EDITOR=vim TAW_TEST_TMUX=/tmp/tmux TAW_FAKE_TMUX_CURRENT_SESSION_ID='$1' \
    TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" \
    run_taw "$current_repo" --peer "$target" -b develop

  assert_eq "develop" "$(git -C "$target/.worktrees/develop" branch --show-current)" \
    "expected -b to create a worktree in the positional peer project"
  assert_eq "main" "$(git -C "$target" branch --show-current)" \
    "expected the target primary worktree branch to remain unchanged"
  assert_eq "main" "$(git -C "$current_repo" branch --show-current)" \
    "expected the invoking project branch to remain unchanged"
}

test_peer_without_positionals_uses_current_project() {
  local repo repo_real fake_bin no_fzf_path log

  repo="$TEST_TMPDIR/repo"
  make_git_repo "$repo"
  repo_real="$(cd "$repo" && pwd -P)"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  no_fzf_path="$(make_path_without_fzf "$fake_bin")"
  log="$TEST_TMPDIR/tmux.log"

  EDITOR=vim TAW_TEST_TMUX=/tmp/tmux TAW_FAKE_TMUX_CURRENT_SESSION_ID='$1' \
    TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" \
    run_taw "$repo" --peer

  assert_file_contains "$log" $'new-window\t-d\t-P\t-F\t#{window_id} #{pane_id}\t-t\t$1:\t-n\trepo\t-c\t'"$repo_real"$'\tvim'
}

test_non_peer_positional_keeps_current_project_branch_shorthand() {
  local repo fake_bin log

  repo="$TEST_TMPDIR/repo"
  make_git_repo "$repo"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"

  EDITOR=vim TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$repo" develop

  assert_eq "develop" "$(git -C "$repo/.worktrees/develop" branch --show-current)" \
    "expected ordinary positional shorthand to create a managed worktree"
  assert_eq "main" "$(git -C "$repo" branch --show-current)" \
    "expected ordinary positional shorthand to preserve the root branch"
}

test_peer_links_resolved_bare_worktree() {
  local current_repo project worktree worktree_real fake_bin no_fzf_path log panes

  current_repo="$TEST_TMPDIR/current"
  make_git_repo "$current_repo"
  project="$(make_bare_wrapper "$TEST_TMPDIR/bare")"
  git --git-dir "$project/.git" worktree add -b hallamshire-hotel-all-day \
    "$project/hallamshire-hotel-all-day" develop >/dev/null 2>&1
  worktree="$project/hallamshire-hotel-all-day"
  worktree_real="$(cd "$worktree" && pwd -P)"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  no_fzf_path="$(make_path_without_fzf "$fake_bin")"
  log="$TEST_TMPDIR/tmux.log"
  panes=$'$2\tproject\t@20\t%20\t'"$worktree_real"$'\n'

  PROJECTS_HOME="$TEST_TMPDIR/bare" EDITOR=vim TAW_TEST_TMUX=/tmp/tmux \
    TAW_FAKE_TMUX_CURRENT_SESSION_ID='$1' TAW_FAKE_TMUX_ALL_PANES="$panes" \
    TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" TAW_RUN_PATH="$no_fzf_path" \
    run_taw "$current_repo" --peer project hallamshire-hotel-all-day

  assert_file_contains "$log" $'link-window\t-d\t-s\t@20\t-t\t$1:'
  assert_file_contains "$log" $'select-pane\t-t\t%20'
  assert_file_not_contains "$log" $'new-window\t'
  assert_eq "main" "$(git -C "$current_repo" branch --show-current)" \
    "expected the invoking project branch to remain unchanged"
}

make_convert_failing_git() {
  local root="$1"
  local bin="$root/bin"
  local real_git

  real_git="$(command -v git)"
  mkdir -p "$bin"
  cat >"$bin/git" <<EOF
#!/usr/bin/env bash
set -euo pipefail

if [[ "\${TAW_CONVERT_FAIL_STAGE:-worktree}" = worktree \
  && "\${1:-}" = --git-dir && "\${3:-}" = worktree && "\${4:-}" = add \
  && "\${5:-}" = --no-checkout ]]; then
  exit 91
fi
if [[ "\${TAW_CONVERT_FAIL_STAGE:-worktree}" = head \
  && "\${1:-}" = --git-dir && "\${3:-}" = symbolic-ref && "\${4:-}" = HEAD ]]; then
  exit 92
fi
if [[ "\${TAW_CONVERT_FAIL_STAGE:-worktree}" = concurrent \
  && "\${1:-}" = --git-dir && "\${3:-}" = symbolic-ref && "\${4:-}" = HEAD ]]; then
  "$real_git" "\$@"
  printf 'concurrent\n' >"\${TAW_CONCURRENT_FILE:?}"
  exit 0
fi
if [[ "\${TAW_CONVERT_FAIL_STAGE:-worktree}" = late-concurrent \
  && "\${1:-}" = --git-dir && "\${3:-}" = symbolic-ref \
  && "\${4:-}" = --quiet && "\${5:-}" = --short && "\${6:-}" = HEAD ]]; then
  "$real_git" "\$@"
  printf 'late concurrent\n' >"\${TAW_CONCURRENT_FILE:?}"
  exit 0
fi
if [[ "\${TAW_CONVERT_FAIL_STAGE:-worktree}" = default-branch-race \
  && "\${1:-}" = --git-dir && "\${3:-}" = update-ref \
  && "\${4:-}" = refs/heads/trunk ]]; then
  "$real_git" "\$@"
  exit 93
fi
if [[ "\${TAW_CONVERT_FAIL_STAGE:-worktree}" = default-config-failure \
  && "\${1:-}" = --git-dir && "\${3:-}" = config \
  && "\${4:-}" = branch.trunk.remote ]]; then
  exit 94
fi
if [[ "\${TAW_CONVERT_FAIL_STAGE:-worktree}" = remove \
  && "\${1:-}" = --git-dir && "\${3:-}" = symbolic-ref && "\${4:-}" = HEAD ]]; then
  exit 95
fi
  if [[ "\${TAW_CONVERT_FAIL_STAGE:-worktree}" = remove \
    && "\${1:-}" = --git-dir && "\${3:-}" = worktree && "\${4:-}" = remove ]]; then
    exit 96
  fi
  if [[ "\${TAW_CONVERT_FAIL_STAGE:-worktree}" = nonbare \
    && "\${1:-}" = --git-dir && "\${3:-}" = config \
    && "\${4:-}" = core.bare && "\${5:-}" = false ]]; then
    exit 97
  fi

exec "$real_git" "\$@"
EOF
  chmod +x "$bin/git"
  printf '%s\n' "$bin"
}

test_convert_bare_project_promotes_dirty_default_and_moves_worktrees() {
  local project main_worktree develop_worktree external before_main before_develop

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  main_worktree="$project/main"
  external="$TEST_TMPDIR/develop-external"
  git --git-dir "$project/.git" worktree add -q "$main_worktree" main
  git --git-dir "$project/.git" worktree add -q "$external" develop
  printf 'staged\n' >"$main_worktree/staged.txt"
  git -C "$main_worktree" add staged.txt
  printf 'dirty\n' >>"$main_worktree/README.md"
  printf 'untracked\n' >"$external/untracked.txt"
  before_main="$(git -C "$main_worktree" status --porcelain=v2 --branch --untracked-files=all)"
  before_develop="$(git -C "$external" status --porcelain=v2 --branch --untracked-files=all)"

  run_taw "$TEST_TMPDIR" --convert "$project"

  develop_worktree="$project/.worktrees/develop"
  assert_eq "false" "$(git -C "$project" rev-parse --is-bare-repository)" \
    "expected a normal primary repository"
  assert_eq "main" "$(git -C "$project" branch --show-current)" \
    "expected the default branch at the repository root"
  assert_eq "$before_main" \
    "$(git -C "$project" status --porcelain=v2 --branch --untracked-files=all)" \
    "expected promoted default worktree state to be preserved"
  assert_eq "$before_develop" \
    "$(git -C "$develop_worktree" status --porcelain=v2 --branch --untracked-files=all)" \
    "expected linked worktree state to be preserved"
  assert_not_exists "$main_worktree"
  assert_not_exists "$external"
}

test_convert_bare_project_moves_slash_and_detached_worktrees() {
  local project detached_source detached_commit

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  git --git-dir "$project/.git" worktree add -q "$project/main" main
  git --git-dir "$project/.git" branch feature/topic develop
  git --git-dir "$project/.git" worktree add -q \
    "$TEST_TMPDIR/topic-external" feature/topic
  detached_source="$TEST_TMPDIR/detached-copy"
  git --git-dir "$project/.git" worktree add -q --detach "$detached_source" main
  detached_commit="$(git -C "$detached_source" rev-parse HEAD)"

  run_taw "$TEST_TMPDIR" --convert "$project"

  assert_eq "feature/topic" \
    "$(git -C "$project/.worktrees/feature/topic" branch --show-current)" \
    "expected branch names to determine managed paths"
  assert_eq "$detached_commit" \
    "$(git -C "$project/.worktrees/detached-copy" rev-parse HEAD)" \
    "expected detached worktree commit to be preserved"
  assert_eq "" "$(git -C "$project/.worktrees/detached-copy" branch --show-current)" \
    "expected detached worktree state to be preserved"
}

test_convert_rejects_nondefault_worktree_containing_detached_worktree() {
  local project parent child before_parent before_child before_list output
  local -a backups

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  parent="$project/develop"
  git --git-dir "$project/.git" worktree add -q "$parent" develop
  parent="$(cd "$parent" && pwd -P)"
  child="$parent/scratch"
  git --git-dir "$project/.git" worktree add -q --detach "$child" main
  printf 'dirty\n' >>"$parent/develop.txt"
  printf 'untracked\n' >"$child/untracked.txt"
  before_parent="$(git -C "$parent" status --porcelain=v2 --branch --untracked-files=all)"
  before_child="$(git -C "$child" status --porcelain=v2 --branch --untracked-files=all)"
  before_list="$(git --git-dir "$project/.git" worktree list --porcelain)"

  if output="$(run_taw "$TEST_TMPDIR" --convert "$project" 2>&1)"; then
    fail "expected nested non-default worktrees to reject conversion"
  fi

  assert_string_contains "$output" \
    "cannot move a worktree that contains another registered worktree: $parent"
  assert_eq "true" "$(git --git-dir "$project/.git" rev-parse --is-bare-repository)" \
    "expected nested-source rejection to preserve the bare repository"
  assert_eq "$before_parent" \
    "$(git -C "$parent" status --porcelain=v2 --branch --untracked-files=all)" \
    "expected nested-source rejection to preserve the parent worktree"
  assert_eq "$before_child" \
    "$(git -C "$child" status --porcelain=v2 --branch --untracked-files=all)" \
    "expected nested-source rejection to preserve the child worktree"
  assert_eq "$before_list" "$(git --git-dir "$project/.git" worktree list --porcelain)" \
    "expected nested-source rejection to preserve worktree metadata"
  assert_not_exists "$project/.worktrees"
  shopt -s nullglob
  backups=( "$TEST_TMPDIR"/.project.taw-convert.* )
  shopt -u nullglob
  assert_eq "0" "${#backups[@]}" "expected nested-source rejection before backup creation"
}

test_convert_rejects_nondefault_worktree_containing_default_worktree() {
  local project parent default_worktree before_parent before_default before_list output
  local -a backups

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  parent="$project/develop"
  git --git-dir "$project/.git" worktree add -q "$parent" develop
  parent="$(cd "$parent" && pwd -P)"
  default_worktree="$parent/main"
  git --git-dir "$project/.git" worktree add -q "$default_worktree" main
  before_parent="$(git -C "$parent" status --porcelain=v2 --branch --untracked-files=all)"
  before_default="$(git -C "$default_worktree" status \
    --porcelain=v2 --branch --untracked-files=all)"
  before_list="$(git --git-dir "$project/.git" worktree list --porcelain)"

  if output="$(run_taw "$TEST_TMPDIR" --convert "$project" 2>&1)"; then
    fail "expected a non-default parent of the default worktree to reject conversion"
  fi

  assert_string_contains "$output" \
    "cannot move a worktree that contains another registered worktree: $parent"
  assert_eq "$before_parent" \
    "$(git -C "$parent" status --porcelain=v2 --branch --untracked-files=all)" \
    "expected rejection to preserve the non-default parent worktree"
  assert_eq "$before_default" \
    "$(git -C "$default_worktree" status --porcelain=v2 --branch --untracked-files=all)" \
    "expected rejection to preserve the nested default worktree"
  assert_eq "$before_list" "$(git --git-dir "$project/.git" worktree list --porcelain)" \
    "expected rejection to preserve nested default worktree metadata"
  assert_not_exists "$project/.worktrees"
  shopt -s nullglob
  backups=( "$TEST_TMPDIR"/.project.taw-convert.* )
  shopt -u nullglob
  assert_eq "0" "${#backups[@]}" "expected rejection before backup creation"
}

test_convert_allows_default_worktree_containing_detached_worktree() {
  local project default_worktree child target before_default before_child

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  default_worktree="$project/main"
  child="$default_worktree/scratch"
  target="$project/.worktrees/scratch"
  git --git-dir "$project/.git" worktree add -q "$default_worktree" main
  git --git-dir "$project/.git" worktree add -q --detach "$child" develop
  printf 'dirty\n' >>"$default_worktree/README.md"
  printf 'untracked\n' >"$child/untracked.txt"
  before_default="$(git -C "$default_worktree" status \
    --porcelain=v2 --branch --untracked-files=all)"
  before_child="$(git -C "$child" status --porcelain=v2 --branch --untracked-files=all)"

  run_taw "$TEST_TMPDIR" --convert "$project"

  assert_eq "$before_default" \
    "$(git -C "$project" status --porcelain=v2 --branch --untracked-files=all)" \
    "expected the containing default worktree state to be preserved"
  assert_eq "$before_child" \
    "$(git -C "$target" status --porcelain=v2 --branch --untracked-files=all)" \
    "expected the nested detached worktree state to be preserved"
  assert_not_exists "$default_worktree"
  assert_exists "$target"
}

test_convert_conventional_bare_repository() {
  local bare project

  bare="$(make_conventional_bare_clone "$TEST_TMPDIR" "project")"
  project="${bare%.git}"
  git --git-dir "$bare" worktree add -q "$TEST_TMPDIR/main-external" main
  git --git-dir "$bare" worktree add -q "$TEST_TMPDIR/develop-external" develop

  run_taw "$TEST_TMPDIR" --convert "$bare"

  assert_exists "$project/.git"
  assert_not_exists "$bare"
  assert_eq "false" "$(git -C "$project" rev-parse --is-bare-repository)" \
    "expected conventional bare repository to become a normal clone"
  assert_eq "develop" \
    "$(git -C "$project/.worktrees/develop" branch --show-current)" \
    "expected external linked worktree to move under the normal clone"
}

test_convert_rejects_suffixless_bare_repository_before_mutation() {
  local source container bare default_worktree before output
  local -a backups

  source="$TEST_TMPDIR/source"
  container="$TEST_TMPDIR/container"
  bare="$container/foo"
  default_worktree="$TEST_TMPDIR/main-external"
  make_git_repo "$source"
  mkdir -p "$container"
  git clone --bare "$source" "$bare" >/dev/null 2>&1
  git --git-dir "$bare" worktree add -q "$default_worktree" main
  printf 'sibling\n' >"$container/sibling.txt"
  before="$(git -C "$default_worktree" status --porcelain=v2 --branch --untracked-files=all)"

  if output="$(run_taw "$TEST_TMPDIR" --convert "$bare" 2>&1)"; then
    fail "expected suffixless bare conversion to fail"
  fi

  assert_string_contains "$output" "does not support suffixless bare repositories"
  assert_eq "true" "$(git --git-dir "$bare" rev-parse --is-bare-repository)" \
    "expected suffixless rejection to preserve the bare repository"
  assert_not_exists "$container/.git"
  assert_file_contents "$container/sibling.txt" "sibling"
  assert_exists "$default_worktree"
  assert_eq "$before" \
    "$(git -C "$default_worktree" status --porcelain=v2 --branch --untracked-files=all)" \
    "expected suffixless rejection to preserve the registered worktree"
  shopt -s nullglob
  backups=( "$TEST_TMPDIR"/.container.taw-convert.* )
  shopt -u nullglob
  assert_eq "0" "${#backups[@]}" "expected suffixless rejection before backup creation"
}

test_convert_bare_child_not_named_git() {
  local project external

  project="$(make_bare_wrapper "$TEST_TMPDIR" ".bare")"
  external="$TEST_TMPDIR/develop-external"
  git --git-dir "$project/.bare" worktree add -q "$project/main" main
  git --git-dir "$project/.bare" worktree add -q "$external" develop

  run_taw "$TEST_TMPDIR" --convert "$project"

  assert_exists "$project/.git"
  assert_not_exists "$project/.bare"
  assert_eq "false" "$(git -C "$project" rev-parse --is-bare-repository)" \
    "expected .bare wrapper to become a normal clone"
  assert_eq "main" "$(git -C "$project" branch --show-current)" \
    "expected .bare wrapper default branch at the repository root"
  assert_eq "develop" \
    "$(git -C "$project/.worktrees/develop" branch --show-current)" \
    "expected .bare wrapper linked worktree under the normal clone"
  assert_not_exists "$project/main"
  assert_not_exists "$external"
}

test_convert_without_default_worktree_checks_out_root() {
  local project

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  git --git-dir "$project/.git" worktree add -q "$TEST_TMPDIR/develop" develop

  run_taw "$TEST_TMPDIR" --convert "$project"

  assert_eq "main" "$(git -C "$project" branch --show-current)" \
    "expected a fresh default checkout at the repository root"
  assert_eq "" "$(git -C "$project" status --porcelain --untracked-files=all)" \
    "expected the fresh default checkout to be clean"
  assert_exists "$project/.worktrees/develop"
}

test_convert_without_default_worktree_rejects_tracked_managed_path() {
  local project default_worktree external before output
  local -a backups

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  default_worktree="$TEST_TMPDIR/main"
  external="$TEST_TMPDIR/develop"
  git --git-dir "$project/.git" worktree add -q "$default_worktree" main
  mkdir -p "$default_worktree/.worktrees/develop"
  printf 'owned by main\n' >"$default_worktree/.worktrees/develop/main-owned.txt"
  git -C "$default_worktree" add -f .worktrees/develop/main-owned.txt
  git -C "$default_worktree" commit -qm "track managed path"
  git --git-dir "$project/.git" worktree remove "$default_worktree"
  git --git-dir "$project/.git" worktree add -q "$external" develop
  before="$(git -C "$external" status --porcelain=v2 --branch --untracked-files=all)"

  if output="$(run_taw "$TEST_TMPDIR" --convert "$project" 2>&1)"; then
    fail "expected tracked managed path to reject conversion"
  fi

  assert_string_contains "$output" \
    "cannot check out a default branch that tracks .worktrees"
  assert_eq "true" "$(git --git-dir "$project/.git" rev-parse --is-bare-repository)" \
    "expected tracked managed path rejection before mutation"
  assert_exists "$external"
  assert_not_exists "$project/.worktrees"
  assert_not_exists "$external/main-owned.txt"
  assert_eq "$before" \
    "$(git -C "$external" status --porcelain=v2 --branch --untracked-files=all)" \
    "expected tracked managed path rejection to preserve linked worktree state"
  shopt -s nullglob
  backups=( "$TEST_TMPDIR"/.project.taw-convert.* )
  shopt -u nullglob
  assert_eq "0" "${#backups[@]}" "expected rejection before backup creation"
}

test_convert_unborn_default_worktree_preserves_index() {
  local project before

  project="$TEST_TMPDIR/project"
  mkdir -p "$project"
  git init -q --bare -b main "$project/.git"
  git --git-dir "$project/.git" worktree add -q --orphan -b main "$project/main"
  printf 'staged\n' >"$project/main/staged.txt"
  git -C "$project/main" add staged.txt
  printf 'untracked\n' >"$project/main/untracked.txt"
  before="$(git -C "$project/main" status --porcelain=v2 --branch --untracked-files=all)"

  run_taw "$TEST_TMPDIR" --convert "$project"

  assert_eq "$before" \
    "$(git -C "$project" status --porcelain=v2 --branch --untracked-files=all)" \
    "expected unborn default worktree index and files to be preserved"
  assert_eq "main" "$(git -C "$project" branch --show-current)" \
    "expected the unborn default branch at the repository root"
}

test_convert_creates_remote_only_default_branch() {
  local project

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  git --git-dir "$project/.git" update-ref refs/remotes/origin/trunk refs/heads/main
  git --git-dir "$project/.git" symbolic-ref \
    refs/remotes/origin/HEAD refs/remotes/origin/trunk
  git --git-dir "$project/.git" update-ref -d refs/heads/main
  git --git-dir "$project/.git" symbolic-ref HEAD refs/heads/missing
  git --git-dir "$project/.git" config --unset-all remote.origin.fetch || true

  run_taw "$TEST_TMPDIR" --convert "$project"

  assert_eq "trunk" "$(git -C "$project" branch --show-current)" \
    "expected origin HEAD to provide the normal default branch"
  assert_eq "origin/trunk" "$(git -C "$project" rev-parse --abbrev-ref '@{upstream}')" \
    "expected the remote-only default branch to track origin"
  assert_eq "+refs/heads/*:refs/remotes/origin/*" \
    "$(git -C "$project" config --get-all remote.origin.fetch)" \
    "expected conversion to add a missing origin fetch refspec"
}

test_convert_preserves_narrow_origin_fetch_refspec() {
  local project refspec

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  refspec='+refs/heads/trunk:refs/remotes/origin/trunk'
  git --git-dir "$project/.git" update-ref refs/remotes/origin/trunk refs/heads/main
  git --git-dir "$project/.git" symbolic-ref \
    refs/remotes/origin/HEAD refs/remotes/origin/trunk
  git --git-dir "$project/.git" update-ref -d refs/heads/main
  git --git-dir "$project/.git" symbolic-ref HEAD refs/heads/missing
  git --git-dir "$project/.git" config --unset-all remote.origin.fetch || true
  git --git-dir "$project/.git" config --add remote.origin.fetch "$refspec"

  run_taw "$TEST_TMPDIR" --convert "$project"

  assert_eq "$refspec" "$(git -C "$project" config --get-all remote.origin.fetch)" \
    "expected conversion to preserve a narrow origin fetch refspec"
  assert_eq "origin/trunk" "$(git -C "$project" rev-parse --abbrev-ref '@{upstream}')" \
    "expected the remote-only default branch to track origin"
}

test_convert_preserves_multiple_origin_fetch_refspecs() {
  local project before

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  git --git-dir "$project/.git" update-ref refs/remotes/origin/trunk refs/heads/main
  git --git-dir "$project/.git" symbolic-ref \
    refs/remotes/origin/HEAD refs/remotes/origin/trunk
  git --git-dir "$project/.git" update-ref -d refs/heads/main
  git --git-dir "$project/.git" symbolic-ref HEAD refs/heads/missing
  git --git-dir "$project/.git" config --unset-all remote.origin.fetch || true
  git --git-dir "$project/.git" config --add remote.origin.fetch \
    '+refs/heads/trunk:refs/remotes/origin/trunk'
  git --git-dir "$project/.git" config --add remote.origin.fetch \
    '+refs/heads/release/*:refs/remotes/origin/release/*'
  before="$(git --git-dir "$project/.git" config --get-all remote.origin.fetch)"

  run_taw "$TEST_TMPDIR" --convert "$project"

  assert_eq "$before" "$(git -C "$project" config --get-all remote.origin.fetch)" \
    "expected conversion to preserve multiple origin fetch refspecs"
  assert_eq "origin/trunk" "$(git -C "$project" rev-parse --abbrev-ref '@{upstream}')" \
    "expected the remote-only default branch to track origin"
}

test_convert_preserves_unmanaged_wrapper_entries() {
  local project

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  git --git-dir "$project/.git" worktree add -q "$project/main" main
  printf 'wrapper note\n' >"$project/note.txt"

  run_taw "$TEST_TMPDIR" --convert "$project"

  assert_eq "wrapper note" "$(<"$project/note.txt")" \
    "expected unmanaged wrapper content at the normal repository root"
  assert_eq "?? note.txt" "$(git -C "$project" status --porcelain)" \
    "expected unmanaged wrapper content to remain untracked"
}

test_convert_rejects_fallback_wrapper_conflict_without_data_loss() {
  local project output
  local -a backups

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  printf 'keep me\n' >"$project/00-keep.txt"
  printf 'wrapper README\n' >"$project/README.md"

  if output="$(run_taw "$TEST_TMPDIR" --convert "$project" 2>&1)"; then
    fail "expected wrapper/default conflict to reject conversion"
  fi

  assert_string_contains "$output" \
    "wrapper entry conflicts with default checkout: README.md"
  assert_string_not_contains "$output" "HEAD is now at"
  assert_eq "true" "$(git --git-dir "$project/.git" rev-parse --is-bare-repository)" \
    "expected wrapper conflict rejection to preserve the bare repository"
  assert_file_contents "$project/00-keep.txt" "keep me"
  assert_file_contents "$project/README.md" "wrapper README"
  shopt -s nullglob
  backups=( "$TEST_TMPDIR"/.project.taw-convert.* )
  shopt -u nullglob
  assert_eq "0" "${#backups[@]}" "expected wrapper conflict rollback to remove its backup"
}

test_convert_rejects_deleted_default_wrapper_conflict_without_data_loss() {
  local project output before
  local -a backups

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  git --git-dir "$project/.git" worktree add -q "$project/main" main
  rm -- "$project/main/README.md"
  printf 'wrapper README\n' >"$project/README.md"
  before="$(git -C "$project/main" status --porcelain=v2 --branch --untracked-files=all)"

  if output="$(run_taw "$TEST_TMPDIR" --convert "$project" 2>&1)"; then
    fail "expected deleted default path to conflict with wrapper entry"
  fi

  assert_string_contains "$output" \
    "wrapper entry conflicts with default checkout: README.md"
  assert_eq "true" "$(git --git-dir "$project/.git" rev-parse --is-bare-repository)" \
    "expected deleted-path conflict to preserve the bare repository"
  assert_file_contents "$project/README.md" "wrapper README"
  assert_not_exists "$project/main/README.md"
  assert_eq "$before" \
    "$(git -C "$project/main" status --porcelain=v2 --branch --untracked-files=all)" \
    "expected deleted-path conflict to preserve the default worktree status"
  shopt -s nullglob
  backups=( "$TEST_TMPDIR"/.project.taw-convert.* )
  shopt -u nullglob
  assert_eq "0" "${#backups[@]}" "expected deleted-path conflict rollback to remove its backup"
}

test_convert_allows_staged_delete_with_wrapper_entry() {
  local project

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  git --git-dir "$project/.git" worktree add -q "$project/main" main
  git -C "$project/main" rm -q README.md
  printf 'wrapper README\n' >"$project/README.md"

  run_taw "$TEST_TMPDIR" --convert "$project"

  assert_eq "false" "$(git -C "$project" rev-parse --is-bare-repository)" \
    "expected staged deletion to remain convertible"
  assert_file_contents "$project/README.md" "wrapper README"
  assert_eq $'D\tREADME.md' "$(git -C "$project" diff --cached --name-status)" \
    "expected the staged deletion to remain staged"
  assert_eq "README.md" "$(git -C "$project" ls-files --others --exclude-standard)" \
    "expected the wrapper entry to remain untracked"
}

test_convert_rejects_destination_collision_before_mutation() {
  local project output

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  git --git-dir "$project/.git" worktree add -q "$project/main" main
  git --git-dir "$project/.git" worktree add -q "$TEST_TMPDIR/develop" develop
  mkdir -p "$project/.worktrees/develop"
  printf 'collision\n' >"$project/.worktrees/develop/file.txt"

  if output="$(run_taw "$TEST_TMPDIR" --convert "$project" 2>&1)"; then
    fail "expected destination collision to reject conversion"
  fi

  assert_string_contains "$output" "worktree destination already exists"
  assert_eq "true" "$(git --git-dir "$project/.git" rev-parse --is-bare-repository)" \
    "expected collision rejection before mutation"
  assert_exists "$TEST_TMPDIR/develop"
}

test_convert_rejects_overlapping_destinations_before_mutation() {
  local project topic detached output
  local -a backups

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  topic="$TEST_TMPDIR/topic"
  detached="$TEST_TMPDIR/detached/feature"
  mkdir -p "${detached%/*}"
  git --git-dir "$project/.git" branch feature/foo develop
  git --git-dir "$project/.git" worktree add -q "$project/main" main
  git --git-dir "$project/.git" worktree add -q "$topic" feature/foo
  git --git-dir "$project/.git" worktree add -q --detach "$detached" main

  if output="$(run_taw "$TEST_TMPDIR" --convert "$project" 2>&1)"; then
    fail "expected overlapping destinations to reject conversion"
  fi

  assert_string_contains "$output" "worktree destination collision"
  assert_eq "true" "$(git --git-dir "$project/.git" rev-parse --is-bare-repository)" \
    "expected overlap rejection before mutation"
  assert_exists "$project/main"
  assert_exists "$topic"
  assert_exists "$detached"
  assert_not_exists "$project/.worktrees"
  shopt -s nullglob
  backups=( "$TEST_TMPDIR"/.project.taw-convert.* )
  shopt -u nullglob
  assert_eq "0" "${#backups[@]}" "expected overlap rejection before backup creation"
}

test_convert_prunes_empty_in_wrapper_worktree_parents() {
  local project nested before

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  nested="$project/docs/feature"
  git --git-dir "$project/.git" branch docs/feature develop
  git --git-dir "$project/.git" worktree add -q "$project/main" main
  git --git-dir "$project/.git" worktree add -q "$nested" docs/feature
  mkdir -p "$project/main/docs"
  printf 'default docs\n' >"$project/main/docs/note.txt"
  before="$(git -C "$project/main" status --porcelain=v2 --branch --untracked-files=all)"

  run_taw "$TEST_TMPDIR" --convert "$project"

  assert_eq "$before" \
    "$(git -C "$project" status --porcelain=v2 --branch --untracked-files=all)" \
    "expected default worktree content to survive nested source pruning"
  assert_eq "default docs" "$(<"$project/docs/note.txt")" \
    "expected the default worktree docs directory at the repository root"
  assert_eq "docs/feature" \
    "$(git -C "$project/.worktrees/docs/feature" branch --show-current)" \
    "expected the nested worktree under the managed root"
  assert_not_exists "$nested"
}

test_convert_failure_restores_pruned_worktree_parents() {
  local project nested fake_bin
  local -a backups

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  nested="$project/docs/feature"
  git --git-dir "$project/.git" branch docs/feature develop
  git --git-dir "$project/.git" worktree add -q "$project/main" main
  git --git-dir "$project/.git" worktree add -q "$nested" docs/feature
  mkdir -p "$project/main/docs"
  printf 'default docs\n' >"$project/main/docs/note.txt"
  fake_bin="$(make_convert_failing_git "$TEST_TMPDIR/failing")"

  if TAW_CONVERT_FAIL_STAGE=nonbare TAW_RUN_PATH="$fake_bin:$PATH" \
    run_taw "$TEST_TMPDIR" --convert "$project"; then
    fail "expected injected conversion failure"
  fi

  assert_eq "true" "$(git --git-dir "$project/.git" rev-parse --is-bare-repository)" \
    "expected rollback to restore the bare repository"
  assert_eq "docs/feature" "$(git -C "$nested" branch --show-current)" \
    "expected rollback to recreate the pruned source parents"
  assert_not_exists "$project/.worktrees/docs/feature"
  shopt -s nullglob
  backups=( "$TEST_TMPDIR"/.project.taw-convert.* )
  shopt -u nullglob
  assert_eq "0" "${#backups[@]}" "expected successful rollback to remove its backup"
}

test_convert_prunes_empty_default_worktree_parents() {
  local project default_worktree before

  project="$(make_bare_wrapper "$TEST_TMPDIR" ".git" "docs/feature")"
  default_worktree="$project/docs/feature"
  git --git-dir "$project/.git" worktree add -q "$default_worktree" docs/feature
  mkdir -p "$default_worktree/docs"
  printf 'default docs\n' >"$default_worktree/docs/note.txt"
  before="$(git -C "$default_worktree" status \
    --porcelain=v2 --branch --untracked-files=all)"

  run_taw "$TEST_TMPDIR" --convert "$project"

  assert_eq "docs/feature" "$(git -C "$project" branch --show-current)" \
    "expected the slash-named default branch at the repository root"
  assert_eq "$before" \
    "$(git -C "$project" status --porcelain=v2 --branch --untracked-files=all)" \
    "expected nested default worktree content to survive parent pruning"
  assert_eq "default docs" "$(<"$project/docs/note.txt")" \
    "expected default worktree docs at the repository root"
  assert_not_exists "$default_worktree"
}

test_convert_failure_restores_pruned_default_worktree_parents() {
  local project default_worktree fake_bin
  local -a backups

  project="$(make_bare_wrapper "$TEST_TMPDIR" ".git" "docs/feature")"
  default_worktree="$project/docs/feature"
  git --git-dir "$project/.git" worktree add -q "$default_worktree" docs/feature
  mkdir -p "$default_worktree/docs"
  printf 'default docs\n' >"$default_worktree/docs/note.txt"
  fake_bin="$(make_convert_failing_git "$TEST_TMPDIR/failing")"

  if TAW_CONVERT_FAIL_STAGE=nonbare TAW_RUN_PATH="$fake_bin:$PATH" \
    run_taw "$TEST_TMPDIR" --convert "$project"; then
    fail "expected injected conversion failure"
  fi

  assert_eq "true" "$(git --git-dir "$project/.git" rev-parse --is-bare-repository)" \
    "expected rollback to restore the bare repository"
  assert_eq "docs/feature" "$(git -C "$default_worktree" branch --show-current)" \
    "expected rollback to recreate the pruned default worktree parents"
  assert_eq "default docs" "$(<"$default_worktree/docs/note.txt")" \
    "expected rollback to preserve default worktree content"
  shopt -s nullglob
  backups=( "$TEST_TMPDIR"/.project.taw-convert.* )
  shopt -u nullglob
  assert_eq "0" "${#backups[@]}" "expected successful rollback to remove its backup"
}

test_convert_from_linked_worktree_remaps_cwd() {
  local project output after

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  git --git-dir "$project/.git" worktree add -q "$project/main" main
  git --git-dir "$project/.git" worktree add -q "$project/develop" develop
  mkdir -p "$project/develop/nested"

  output="$(
    cd "$project/develop/nested" || exit 1
    TAW_FUNC_DIR="$REPO_ROOT/home/.zfuns" zsh -fc \
      'fpath=("$TAW_FUNC_DIR" $fpath); autoload -U taw; taw --convert "$1" || exit; pwd -P' \
      taw "$project"
  )"
  after="${output##*$'\n'}"

  assert_eq "$(cd "$project/.worktrees/develop/nested" && pwd -P)" "$after" \
    "expected invoking shell to follow the relocated worktree"
}

test_convert_from_nested_worktree_remaps_cwd() {
  local project child output after
  local -a backups

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  git --git-dir "$project/.git" worktree add -q "$project/main" main
  child="$project/main/scratch"
  git --git-dir "$project/.git" worktree add -q --detach "$child" develop
  mkdir -p "$child/nested"

  output="$(
    cd "$child/nested" || exit 1
    TAW_FUNC_DIR="$REPO_ROOT/home/.zfuns" zsh -fc \
      'fpath=("$TAW_FUNC_DIR" $fpath); autoload -U taw; taw --convert "$1" || exit; pwd -P' \
      taw "$project" 2>&1
  )"
  after="${output##*$'\n'}"

  assert_eq "$(cd "$project/.worktrees/scratch/nested" && pwd -P)" "$after" \
    "expected invoking shell to follow the relocated nested worktree"
  assert_eq "false" "$(git -C "$project" rev-parse --is-bare-repository)" \
    "expected conversion from the nested worktree to succeed"
  assert_not_exists "$project/main"
  shopt -s nullglob
  backups=( "$TEST_TMPDIR"/.project.taw-convert.* )
  shopt -u nullglob
  assert_eq "0" "${#backups[@]}" "expected successful conversion to remove its backup"
}

test_convert_from_default_worktree_root_remaps_cwd() {
  local project output after
  local -a backups

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  git --git-dir "$project/.git" worktree add -q "$project/main" main

  output="$(
    cd "$project/main" || exit 1
    TAW_FUNC_DIR="$REPO_ROOT/home/.zfuns" zsh -fc \
      'fpath=("$TAW_FUNC_DIR" $fpath); autoload -U taw; taw --convert "$1" || exit; pwd -P' \
      taw "$project" 2>&1
  )"
  after="${output##*$'\n'}"

  assert_string_not_contains "$output" "Unable to read current working directory"
  assert_eq "$(cd "$project" && pwd -P)" "$after" \
    "expected invoking shell to follow the promoted default worktree"
  assert_eq "false" "$(git -C "$project" rev-parse --is-bare-repository)" \
    "expected conversion from the default worktree root to succeed"
  assert_not_exists "$project/main"
  shopt -s nullglob
  backups=( "$TEST_TMPDIR"/.project.taw-convert.* )
  shopt -u nullglob
  assert_eq "0" "${#backups[@]}" "expected successful conversion to remove its backup"
}

test_convert_failure_from_default_worktree_root_restores_cwd() {
  local project fake_bin before output after
  local -a backups

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  git --git-dir "$project/.git" worktree add -q "$project/main" main
  printf 'dirty\n' >>"$project/main/README.md"
  before="$(git -C "$project/main" status --porcelain=v2 --branch --untracked-files=all)"
  fake_bin="$(make_convert_failing_git "$TEST_TMPDIR/failing")"

  output="$(
    cd "$project/main" || exit 1
    TAW_FUNC_DIR="$REPO_ROOT/home/.zfuns" \
      TAW_CONVERT_FAIL_STAGE=nonbare PATH="$fake_bin:$PATH" zsh -fc \
      'fpath=("$TAW_FUNC_DIR" $fpath); autoload -U taw;
       if taw --convert "$1"; then exit 1; fi; pwd -P' taw "$project" 2>&1
  )"
  after="${output##*$'\n'}"

  assert_string_contains "$output" "original bare project restored"
  assert_string_not_contains "$output" "Unable to read current working directory"
  assert_eq "$(cd "$project/main" && pwd -P)" "$after" \
    "expected rollback to restore the invoking shell cwd"
  assert_eq "true" "$(git --git-dir "$project/.git" rev-parse --is-bare-repository)" \
    "expected rollback to restore the bare repository"
  assert_eq "$before" \
    "$(git -C "$project/main" status --porcelain=v2 --branch --untracked-files=all)" \
    "expected rollback to preserve the default worktree state"
  shopt -s nullglob
  backups=( "$TEST_TMPDIR"/.project.taw-convert.* )
  shopt -u nullglob
  assert_eq "0" "${#backups[@]}" "expected successful rollback to remove its backup"
}

test_convert_nonbare_failure_restores_original_layout() {
  local project fake_bin before backups

  project="$(make_bare_wrapper "$TEST_TMPDIR")"
  git --git-dir "$project/.git" worktree add -q "$project/main" main
  git --git-dir "$project/.git" worktree add -q "$project/develop" develop
  printf 'dirty\n' >>"$project/main/README.md"
  before="$(git -C "$project/main" status --porcelain=v2 --branch --untracked-files=all)"
  fake_bin="$(make_convert_failing_git "$TEST_TMPDIR/failing")"

  if TAW_CONVERT_FAIL_STAGE=nonbare TAW_RUN_PATH="$fake_bin:$PATH" \
    run_taw "$TEST_TMPDIR" --convert "$project"; then
    fail "expected injected conversion failure"
  fi

  assert_eq "true" "$(git --git-dir "$project/.git" rev-parse --is-bare-repository)" \
    "expected rollback to restore the bare repository"
  assert_eq "$before" \
    "$(git -C "$project/main" status --porcelain=v2 --branch --untracked-files=all)" \
    "expected rollback to preserve default worktree state"
  assert_exists "$project/develop"
  shopt -s nullglob
  backups=( "$TEST_TMPDIR"/.project.taw-convert.* )
  shopt -u nullglob
  assert_eq "0" "${#backups[@]}" "expected successful rollback to remove its backup"
}

test_convert_rejects_normal_project() {
  local repo output

  repo="$TEST_TMPDIR/project"
  make_git_repo "$repo"

  if output="$(run_taw "$TEST_TMPDIR" --convert "$repo" 2>&1)"; then
    fail "expected normal project conversion to fail"
  fi

  assert_string_contains "$output" "--convert requires a bare git project"
  assert_eq "false" "$(git -C "$repo" rev-parse --is-bare-repository)" \
    "expected the normal project to remain unchanged"
}

test_global_gitignore_excludes_managed_worktrees() {
  assert_file_contains "$REPO_ROOT/home/.config/git/ignore" ".worktrees/"
}

test_convert_same_branch_preserves_dirty_state() {
  local repo fake_bin log before after worktree_count

  repo="$TEST_TMPDIR/project"
  make_git_repo "$repo"
  printf '*.ignored\n' >"$repo/.gitignore"
  git -C "$repo" add .gitignore
  git -C "$repo" commit -qm "add ignore"
  printf 'staged\n' >"$repo/staged.txt"
  git -C "$repo" add staged.txt
  printf 'dirty\n' >>"$repo/README.md"
  printf 'untracked\n' >"$repo/untracked.txt"
  printf 'ignored\n' >"$repo/cache.ignored"
  before="$(git -C "$repo" status --porcelain=v2 --branch --untracked-files=all)"

  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"
  TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" run_taw "$TEST_TMPDIR" --convert "$repo"

  after="$(git -C "$repo/main" status --porcelain=v2 --branch --untracked-files=all)"
  worktree_count="$(git --git-dir "$repo/.git" worktree list --porcelain | grep -c '^worktree ')"
  assert_eq "$before" "$after" "expected conversion to preserve index and working tree status"
  assert_eq "true" "$(git --git-dir "$repo/.git" rev-parse --is-bare-repository)" \
    "expected converted .git directory to be bare"
  assert_eq "main" "$(git --git-dir "$repo/.git" symbolic-ref --quiet --short HEAD)" \
    "expected bare HEAD to name the default branch"
  assert_eq "2" "$worktree_count" "expected bare entry plus one branch worktree"
  assert_exists "$repo/main/cache.ignored"
  assert_no_tmux_work_window "$log"
}

test_convert_non_default_branch_creates_two_worktrees() {
  local repo fake_bin log before after default_status

  repo="$TEST_TMPDIR/project"
  make_git_repo "$repo"
  git -C "$repo" checkout -q develop
  printf 'staged\n' >"$repo/staged.txt"
  git -C "$repo" add staged.txt
  printf 'dirty\n' >>"$repo/develop.txt"
  before="$(git -C "$repo" status --porcelain=v2 --branch --untracked-files=all)"

  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"
  TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" run_taw "$TEST_TMPDIR" --convert "$repo"

  after="$(git -C "$repo/develop" status --porcelain=v2 --branch --untracked-files=all)"
  default_status="$(git -C "$repo/main" status --porcelain --untracked-files=all)"
  assert_eq "$before" "$after" "expected dirty state on the former current branch"
  assert_eq "" "$default_status" "expected the default worktree to be clean"
  assert_eq "develop" "$(git -C "$repo/develop" branch --show-current)" \
    "expected a current-branch worktree"
  assert_eq "main" "$(git -C "$repo/main" branch --show-current)" \
    "expected a default-branch worktree"
  assert_eq "main" "$(git --git-dir "$repo/.git" symbolic-ref --quiet --short HEAD)" \
    "expected bare HEAD to name main"
  assert_no_tmux_work_window "$log"
}

test_convert_prefers_origin_head_for_default_branch() {
  local repo fake_bin log

  repo="$TEST_TMPDIR/project"
  make_git_repo "$repo"
  git -C "$repo" config remote.origin.url "$TEST_TMPDIR/origin.git"
  git -C "$repo" config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
  git -C "$repo" update-ref refs/remotes/origin/trunk refs/heads/main
  git -C "$repo" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/trunk
  git -C "$repo" checkout -q develop

  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"
  TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" run_taw "$TEST_TMPDIR" --convert "$repo"

  assert_exists "$repo/trunk"
  assert_exists "$repo/develop"
  assert_eq "trunk" "$(git --git-dir "$repo/.git" symbolic-ref --quiet --short HEAD)" \
    "expected origin HEAD to take precedence over main"
  assert_eq "origin/trunk" "$(git -C "$repo/trunk" rev-parse --abbrev-ref '@{upstream}')" \
    "expected remote-only default branch to track origin"
  assert_no_tmux_work_window "$log"
}

test_convert_does_not_delete_concurrently_created_default_branch() {
  local repo fake_bin before

  repo="$TEST_TMPDIR/project"
  make_git_repo "$repo"
  git -C "$repo" config remote.origin.url "$TEST_TMPDIR/origin.git"
  git -C "$repo" config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
  git -C "$repo" update-ref refs/remotes/origin/trunk refs/heads/main
  git -C "$repo" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/trunk
  git -C "$repo" checkout -q develop
  before="$(git -C "$repo" status --porcelain=v2 --branch --untracked-files=all)"
  fake_bin="$(make_convert_failing_git "$TEST_TMPDIR/branch-race")"

  if TAW_CONVERT_FAIL_STAGE=default-branch-race TAW_RUN_PATH="$fake_bin:$PATH" \
    run_taw "$TEST_TMPDIR" --convert "$repo"; then
    fail "expected concurrent default branch creation to abort conversion"
  fi

  assert_eq "false" "$(git -C "$repo" rev-parse --is-bare-repository)" \
    "expected branch race rollback to restore a normal repository"
  assert_eq "$before" "$(git -C "$repo" status --porcelain=v2 --branch --untracked-files=all)" \
    "expected branch race rollback to preserve the working tree"
  assert_eq "$(git -C "$repo" rev-parse refs/remotes/origin/trunk)" \
    "$(git -C "$repo" rev-parse refs/heads/trunk)" \
    "expected rollback to retain the concurrently created branch"
}

test_convert_removes_owned_default_branch_after_config_failure() {
  local repo fake_bin

  repo="$TEST_TMPDIR/project"
  make_git_repo "$repo"
  git -C "$repo" config remote.origin.url "$TEST_TMPDIR/origin.git"
  git -C "$repo" config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
  git -C "$repo" update-ref refs/remotes/origin/trunk refs/heads/main
  git -C "$repo" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/trunk
  git -C "$repo" checkout -q develop
  fake_bin="$(make_convert_failing_git "$TEST_TMPDIR/config-failure")"

  if TAW_CONVERT_FAIL_STAGE=default-config-failure TAW_RUN_PATH="$fake_bin:$PATH" \
    run_taw "$TEST_TMPDIR" --convert "$repo"; then
    fail "expected injected default tracking config failure"
  fi

  if git -C "$repo" show-ref --verify --quiet refs/heads/trunk; then
    fail "expected rollback to remove the conversion-owned default branch"
  fi
  assert_eq "false" "$(git -C "$repo" rev-parse --is-bare-repository)" \
    "expected config failure rollback to restore a normal repository"
}

test_convert_unborn_repository_preserves_index() {
  local repo fake_bin log before after

  repo="$TEST_TMPDIR/project"
  mkdir -p "$repo"
  git -C "$repo" init -q -b topic
  printf 'staged\n' >"$repo/staged.txt"
  git -C "$repo" add staged.txt
  printf 'untracked\n' >"$repo/untracked.txt"
  before="$(git -C "$repo" status --porcelain=v2 --branch --untracked-files=all)"

  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"
  TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" run_taw "$TEST_TMPDIR" --convert "$repo"

  after="$(git -C "$repo/topic" status --porcelain=v2 --branch --untracked-files=all)"
  assert_eq "$before" "$after" "expected an unborn repository's index to be preserved"
  assert_eq "topic" "$(git -C "$repo/topic" branch --show-current)" \
    "expected an orphan worktree on the unborn branch"
  assert_no_tmux_work_window "$log"
}

test_convert_rejects_unborn_remote_default_collision() {
  local source repo fake_bin log before

  source="$TEST_TMPDIR/source"
  repo="$TEST_TMPDIR/project"
  make_git_repo "$source"
  mkdir -p "$repo"
  git -C "$repo" init -q -b main
  git -C "$repo" remote add origin "$source"
  git -C "$repo" fetch -q origin main
  git -C "$repo" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
  printf 'staged\n' >"$repo/staged.txt"
  git -C "$repo" add staged.txt
  before="$(git -C "$repo" status --porcelain=v2 --branch --untracked-files=all)"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"

  if TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$TEST_TMPDIR" --convert "$repo"; then
    fail "expected unborn current branch and remote default collision to fail"
  fi

  assert_eq "false" "$(git -C "$repo" rev-parse --is-bare-repository)" \
    "expected collision rejection to leave a normal repository"
  assert_eq "$before" "$(git -C "$repo" status --porcelain=v2 --branch --untracked-files=all)" \
    "expected collision rejection before mutation"
  assert_not_exists "$repo/main"
  assert_no_tmux_work_window "$log"
}

test_convert_from_inside_project_follows_current_worktree() {
  local repo output after

  repo="$TEST_TMPDIR/project"
  make_git_repo "$repo"
  mkdir -p "$repo/nested"

  output="$(
    cd "$repo/nested" || exit 1
    TAW_FUNC_DIR="$REPO_ROOT/home/.zfuns" zsh -fc \
      'fpath=("$TAW_FUNC_DIR" $fpath); autoload -U taw; taw --convert "$1" || exit; pwd -P' \
      taw "$repo"
  )"
  after="${output##*$'\n'}"

  assert_eq "$(cd "$repo/main/nested" && pwd -P)" "$after" \
    "expected the invoking shell to follow the current worktree"
}

test_convert_from_git_dir_stays_in_bare_git_dir() {
  local repo git_cwd output after

  repo="$TEST_TMPDIR/project"
  make_git_repo "$repo"
  git_cwd="$(cd "$repo/.git/objects" && pwd -P)"

  output="$(
    cd "$git_cwd" || exit 1
    TAW_FUNC_DIR="$REPO_ROOT/home/.zfuns" zsh -fc \
      'fpath=("$TAW_FUNC_DIR" $fpath); autoload -U taw; taw --convert "$1" || exit; pwd -P' \
      taw "$repo"
  )"
  after="${output##*$'\n'}"

  assert_eq "$git_cwd" "$after" \
    "expected a caller under .git to remain in the retained bare git directory"
  assert_eq "true" "$(git --git-dir "$repo/.git" rev-parse --is-bare-repository)" \
    "expected conversion from .git to succeed"
  assert_exists "$repo/main"
}

test_convert_rejects_linked_worktrees_before_mutation() {
  local repo linked fake_bin log before

  repo="$TEST_TMPDIR/project"
  linked="$TEST_TMPDIR/linked"
  make_git_repo "$repo"
  git -C "$repo" worktree add -q "$linked" develop
  before="$(git -C "$repo" status --porcelain=v2 --branch --untracked-files=all)"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"

  if TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$TEST_TMPDIR" --convert "$repo"; then
    fail "expected conversion with linked worktrees to fail"
  fi

  assert_eq "false" "$(git -C "$repo" rev-parse --is-bare-repository)" \
    "expected the original repository to remain normal"
  assert_eq "$before" "$(git -C "$repo" status --porcelain=v2 --branch --untracked-files=all)" \
    "expected rejection before mutation"
  assert_no_tmux_work_window "$log"
}

test_convert_rejects_dot_named_initialized_submodule() {
  local source repo fake_bin log before

  source="$TEST_TMPDIR/source"
  repo="$TEST_TMPDIR/project"
  make_git_repo "$source"
  make_git_repo "$repo"
  git -c protocol.file.allow=always -C "$repo" submodule add -q "$source" .hidden
  before="$(git -C "$repo" status --porcelain=v2 --branch --untracked-files=all)"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"

  if TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$TEST_TMPDIR" --convert "$repo"; then
    fail "expected conversion with a dot-named initialized submodule to fail"
  fi

  assert_eq "false" "$(git -C "$repo" rev-parse --is-bare-repository)" \
    "expected submodule rejection to leave a normal repository"
  assert_eq "$before" "$(git -C "$repo" status --porcelain=v2 --branch --untracked-files=all)" \
    "expected submodule rejection before mutation"
  assert_exists "$repo/.git/modules/.hidden"
  assert_no_tmux_work_window "$log"
}

test_convert_worktree_failure_rolls_back() {
  local repo fake_bin before backups

  repo="$TEST_TMPDIR/project"
  make_git_repo "$repo"
  git -C "$repo" checkout -q develop
  printf 'dirty\n' >>"$repo/develop.txt"
  printf 'untracked\n' >"$repo/untracked.txt"
  before="$(git -C "$repo" status --porcelain=v2 --branch --untracked-files=all)"
  fake_bin="$(make_convert_failing_git "$TEST_TMPDIR/failing")"

  if TAW_RUN_PATH="$fake_bin:$PATH" run_taw "$TEST_TMPDIR" --convert "$repo"; then
    fail "expected injected worktree failure"
  fi

  assert_eq "false" "$(git -C "$repo" rev-parse --is-bare-repository)" \
    "expected rollback to restore a normal repository"
  assert_eq "$before" "$(git -C "$repo" status --porcelain=v2 --branch --untracked-files=all)" \
    "expected rollback to restore dirty state"
  assert_exists "$repo/develop.txt"
  assert_exists "$repo/untracked.txt"
  shopt -s nullglob
  backups=( "$TEST_TMPDIR"/.project.taw-convert.* )
  shopt -u nullglob
  assert_eq "0" "${#backups[@]}" "expected successful rollback to remove its backup"
}

test_convert_late_failure_restores_original_index() {
  local repo fake_bin before

  repo="$TEST_TMPDIR/project"
  make_git_repo "$repo"
  printf 'staged\n' >"$repo/staged.txt"
  git -C "$repo" add staged.txt
  printf 'dirty\n' >>"$repo/README.md"
  before="$(git -C "$repo" status --porcelain=v2 --branch --untracked-files=all)"
  fake_bin="$(make_convert_failing_git "$TEST_TMPDIR/failing")"

  if TAW_CONVERT_FAIL_STAGE=head TAW_RUN_PATH="$fake_bin:$PATH" \
    run_taw "$TEST_TMPDIR" --convert "$repo"; then
    fail "expected injected late conversion failure"
  fi

  assert_eq "false" "$(git -C "$repo" rev-parse --is-bare-repository)" \
    "expected late rollback to restore a normal repository"
  assert_eq "$before" "$(git -C "$repo" status --porcelain=v2 --branch --untracked-files=all)" \
    "expected late rollback to restore staged and unstaged state"
  assert_exists "$repo/staged.txt"
}

test_convert_retains_recovery_when_worktree_removal_fails() {
  local repo fake_bin backups

  repo="$TEST_TMPDIR/project"
  make_git_repo "$repo"
  fake_bin="$(make_convert_failing_git "$TEST_TMPDIR/remove-failure")"

  if TAW_CONVERT_FAIL_STAGE=remove TAW_RUN_PATH="$fake_bin:$PATH" \
    run_taw "$TEST_TMPDIR" --convert "$repo"; then
    fail "expected injected worktree removal failure"
  fi

  shopt -s nullglob
  backups=( "$TEST_TMPDIR"/.project.taw-convert.* )
  shopt -u nullglob
  assert_eq "1" "${#backups[@]}" \
    "expected incomplete rollback to retain its recovery directory"
  assert_exists "${backups[0]}/meta/config"
}

test_convert_ignores_stale_rebase_head() {
  local repo fake_bin log

  repo="$TEST_TMPDIR/project"
  make_git_repo "$repo"
  git -C "$repo" rev-parse HEAD >"$repo/.git/REBASE_HEAD"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"

  TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$TEST_TMPDIR" --convert "$repo"

  assert_eq "true" "$(git --git-dir "$repo/.git" rev-parse --is-bare-repository)" \
    "expected stale REBASE_HEAD not to block conversion"
  assert_exists "$repo/main"
  assert_no_tmux_work_window "$log"
}

test_convert_preserves_concurrent_new_change() {
  local repo fake_bin

  repo="$TEST_TMPDIR/project"
  make_git_repo "$repo"
  fake_bin="$(make_convert_failing_git "$TEST_TMPDIR/concurrent")"

  TAW_CONVERT_FAIL_STAGE=concurrent TAW_CONCURRENT_FILE="$repo/main/concurrent.txt" \
    TAW_RUN_PATH="$fake_bin:$PATH" run_taw "$TEST_TMPDIR" --convert "$repo"

  assert_exists "$repo/main/concurrent.txt"
  assert_eq "? concurrent.txt" \
    "$(git -C "$repo/main" status --porcelain=v2 --untracked-files=all)" \
    "expected a concurrent new change to survive conversion"
}

test_convert_captures_concurrent_change_at_wrapper_root() {
  local repo fake_bin

  repo="$TEST_TMPDIR/project"
  make_git_repo "$repo"
  fake_bin="$(make_convert_failing_git "$TEST_TMPDIR/concurrent")"

  TAW_CONVERT_FAIL_STAGE=concurrent TAW_CONCURRENT_FILE="$repo/concurrent.txt" \
    TAW_RUN_PATH="$fake_bin:$PATH" run_taw "$TEST_TMPDIR" --convert "$repo"

  assert_not_exists "$repo/concurrent.txt"
  assert_exists "$repo/main/concurrent.txt"
  assert_eq "? concurrent.txt" \
    "$(git -C "$repo/main" status --porcelain=v2 --untracked-files=all)" \
    "expected a concurrent root change to move into the current worktree"
}

test_convert_captures_root_change_after_git_verification() {
  local repo fake_bin

  repo="$TEST_TMPDIR/project"
  make_git_repo "$repo"
  fake_bin="$(make_convert_failing_git "$TEST_TMPDIR/late-concurrent")"

  TAW_CONVERT_FAIL_STAGE=late-concurrent TAW_CONCURRENT_FILE="$repo/late.txt" \
    TAW_RUN_PATH="$fake_bin:$PATH" run_taw "$TEST_TMPDIR" --convert "$repo"

  assert_not_exists "$repo/late.txt"
  assert_exists "$repo/main/late.txt"
  assert_eq "? late.txt" \
    "$(git -C "$repo/main" status --porcelain=v2 --untracked-files=all)" \
    "expected the final capture to preserve a late root change"
}

test_convert_preserves_colliding_wrapper_rewrite() {
  local repo fake_bin

  repo="$TEST_TMPDIR/project"
  make_git_repo "$repo"
  fake_bin="$(make_convert_failing_git "$TEST_TMPDIR/colliding-concurrent")"

  TAW_CONVERT_FAIL_STAGE=late-concurrent TAW_CONCURRENT_FILE="$repo/README.md" \
    TAW_RUN_PATH="$fake_bin:$PATH" run_taw "$TEST_TMPDIR" --convert "$repo"

  assert_not_exists "$repo/README.md"
  assert_eq "late concurrent" "$(<"$repo/main/README.md")" \
    "expected the concurrent rewrite to replace the older worktree copy"
  assert_eq "1 .M N... 100644 100644 100644" \
    "$(git -C "$repo/main" status --porcelain=v2 --untracked-files=all | cut -d' ' -f1-6)" \
    "expected the concurrent rewrite to remain an unstaged change"
}

test_convert_rejects_incompatible_options() {
  local repo fake_bin log

  repo="$TEST_TMPDIR/project"
  make_git_repo "$repo"
  fake_bin="$(make_fake_tmux "$TEST_TMPDIR/fake")"
  log="$TEST_TMPDIR/tmux.log"

  if TAW_FAKE_TMUX_BIN="$fake_bin" TAW_TMUX_LOG="$log" \
    run_taw "$TEST_TMPDIR" --convert "$repo" -agent codex; then
    fail "expected --convert with layout options to fail"
  fi

  assert_eq "false" "$(git -C "$repo" rev-parse --is-bare-repository)" \
    "expected invalid conversion invocation not to mutate the repository"
  assert_no_tmux_work_window "$log"
}

test_case "taw: creates tmux layout with overrides and shell panes" \
  test_layout_with_overrides_and_shell_panes
test_case "taw: real tmux does not prefix-match session names" \
  test_real_tmux_prefix_session_does_not_count_as_exact_match
test_case "taw: real tmux uses created session ID after name normalization" \
  test_real_tmux_uses_created_session_id_after_name_normalization
test_case "taw: real tmux reports normalized session name collisions" \
  test_real_tmux_normalized_session_collision_fails_clearly
test_case "taw: convert promotes dirty default and moves worktrees" \
  test_convert_bare_project_promotes_dirty_default_and_moves_worktrees
test_case "taw: convert moves slash and detached worktrees" \
  test_convert_bare_project_moves_slash_and_detached_worktrees
test_case "taw: convert rejects nested non-default worktrees before mutation" \
  test_convert_rejects_nondefault_worktree_containing_detached_worktree
test_case "taw: convert rejects non-default parent of default before mutation" \
  test_convert_rejects_nondefault_worktree_containing_default_worktree
test_case "taw: convert allows default worktree containing detached worktree" \
  test_convert_allows_default_worktree_containing_detached_worktree
test_case "taw: convert handles conventional bare repositories" \
  test_convert_conventional_bare_repository
test_case "taw: convert rejects suffixless bare repositories before mutation" \
  test_convert_rejects_suffixless_bare_repository_before_mutation
test_case "taw: convert handles .bare wrappers" \
  test_convert_bare_child_not_named_git
test_case "taw: convert checks out missing default worktree" \
  test_convert_without_default_worktree_checks_out_root
test_case "taw: convert rejects tracked managed path without default worktree" \
  test_convert_without_default_worktree_rejects_tracked_managed_path
test_case "taw: convert preserves unborn default worktree" \
  test_convert_unborn_default_worktree_preserves_index
test_case "taw: convert creates remote-only default branch" \
  test_convert_creates_remote_only_default_branch
test_case "taw: convert preserves narrow origin fetch refspec" \
  test_convert_preserves_narrow_origin_fetch_refspec
test_case "taw: convert preserves multiple origin fetch refspecs" \
  test_convert_preserves_multiple_origin_fetch_refspecs
test_case "taw: convert preserves unmanaged wrapper entries" \
  test_convert_preserves_unmanaged_wrapper_entries
test_case "taw: convert rejects fallback wrapper conflicts without data loss" \
  test_convert_rejects_fallback_wrapper_conflict_without_data_loss
test_case "taw: convert rejects deleted default wrapper conflicts without data loss" \
  test_convert_rejects_deleted_default_wrapper_conflict_without_data_loss
test_case "taw: convert allows staged deletes with wrapper entries" \
  test_convert_allows_staged_delete_with_wrapper_entry
test_case "taw: convert rejects destination collisions" \
  test_convert_rejects_destination_collision_before_mutation
test_case "taw: convert rejects overlapping destinations" \
  test_convert_rejects_overlapping_destinations_before_mutation
test_case "taw: convert prunes empty in-wrapper worktree parents" \
  test_convert_prunes_empty_in_wrapper_worktree_parents
test_case "taw: convert rollback restores pruned worktree parents" \
  test_convert_failure_restores_pruned_worktree_parents
test_case "taw: convert prunes empty default worktree parents" \
  test_convert_prunes_empty_default_worktree_parents
test_case "taw: convert rollback restores pruned default worktree parents" \
  test_convert_failure_restores_pruned_default_worktree_parents
test_case "taw: convert remaps linked-worktree cwd" \
  test_convert_from_linked_worktree_remaps_cwd
test_case "taw: convert remaps nested-worktree cwd" \
  test_convert_from_nested_worktree_remaps_cwd
test_case "taw: convert remaps default-worktree-root cwd" \
  test_convert_from_default_worktree_root_remaps_cwd
test_case "taw: convert rollback restores default-worktree-root cwd" \
  test_convert_failure_from_default_worktree_root_restores_cwd
test_case "taw: convert failure restores bare layout" \
  test_convert_nonbare_failure_restores_original_layout
test_case "taw: convert rejects normal projects" \
  test_convert_rejects_normal_project
test_case "taw: global gitignore excludes managed worktrees" \
  test_global_gitignore_excludes_managed_worktrees
test_case "taw: convert rejects incompatible options" \
  test_convert_rejects_incompatible_options
test_case "taw: peer creates in current session" \
  test_peer_creates_window_in_current_session
test_case "taw: removed peer names are rejected" \
  test_removed_peer_names_are_rejected
test_case "taw: peer requires current tmux before resolution" \
  test_peer_requires_current_tmux_before_resolution
test_case "taw: force requires peer" \
  test_force_requires_peer
test_case "taw: peer prefers current session descendant match" \
  test_peer_prefers_current_session_descendant_match
test_case "taw: peer links project session match" \
  test_peer_links_project_session_match
test_case "taw: peer links other session match" \
  test_peer_links_other_session_match
test_case "taw: peer layout conflict requires force" \
  test_peer_layout_conflict_requires_force
test_case "taw: peer TAW_AGENT conflict requires force" \
  test_peer_taw_agent_conflict_requires_force
test_case "taw: peer preserves normal branch resolution" \
  test_peer_normal_branch_resolution_is_unchanged
test_case "taw: peer single positional targets project inside repo" \
  test_peer_single_positional_targets_project_inside_repo
test_case "taw: peer positional project accepts branch flag" \
  test_peer_positional_project_accepts_branch_flag
test_case "taw: peer without positionals uses current project" \
  test_peer_without_positionals_uses_current_project
test_case "taw: ordinary positional keeps current project branch shorthand" \
  test_non_peer_positional_keeps_current_project_branch_shorthand
test_case "taw: peer links resolved bare worktree" \
  test_peer_links_resolved_bare_worktree
test_case "taw: TAW_AGENT whitespace defaults to codex" \
  test_taw_agent_whitespace_only_defaults_to_codex
test_case "taw: TAW_AGENT env override trims whitespace" \
  test_taw_agent_env_override_uses_trimmed_value
test_case "taw: TAW_AGENT env disables existing window reuse" \
  test_taw_agent_env_disables_existing_window_reuse
test_case "taw: existing session selects new window before attach" \
  test_existing_session_adds_window_and_selects_it_before_attach
test_case "taw: reuses existing worktree window" \
  test_existing_worktree_window_is_reused
test_case "taw: named branch creates normal repo worktree" \
  test_named_branch_checks_out_normal_repo
test_case "taw: normal repo no explicit branch uses picker" \
  test_normal_repo_no_explicit_branch_uses_picker_and_tracks_remote_branch
test_case "taw: normal repo picker lists deduped branches" \
  test_normal_repo_picker_lists_deduped_branches
test_case "taw: branch picker loads remotes once" \
  test_branch_picker_loads_remotes_once
test_case "taw: normal repo no explicit branch without fzf opens unchanged" \
  test_normal_repo_no_explicit_branch_without_fzf_opens_repo_unchanged
test_case "taw: normal linked worktree resolves primary project" \
  test_normal_linked_worktree_resolves_primary_project
test_case "taw: normal repo picker cancel returns success" \
  test_normal_repo_picker_cancel_returns_success_without_tmux
test_case "taw: normal repo picker error fails" \
  test_normal_repo_picker_error_fails_without_tmux
test_case "taw: explicit normal origin/topic local branch wins" \
  test_explicit_normal_origin_topic_local_branch_wins_over_remote
test_case "taw: explicit normal longest remote prefix resolves" \
  test_explicit_normal_longest_remote_prefix_resolves_to_nested_remote_branch
test_case "taw: explicit normal remote-only branch tracks upstream" \
  test_explicit_normal_branch_resolves_remote_only_by_branch_name
test_case "taw: explicit normal stale unconfigured remote ref is ignored" \
  test_explicit_normal_branch_ignores_stale_unconfigured_remote_ref
test_case "taw: explicit normal configured remote prefix missing ref fails" \
  test_explicit_normal_configured_remote_prefix_missing_ref_fails
test_case "taw: explicit normal refs/remotes prefix is rejected" \
  test_explicit_normal_branch_rejects_refs_remotes_prefix
test_case "taw: -p resolves from PROJECTS_HOME" \
  test_project_arg_resolves_from_projects_home
test_case "taw: direct -p path precedes PROJECTS_HOME" \
  test_project_arg_direct_path_precedes_projects_home
test_case "taw: plain -p path opens plain project" \
  test_project_arg_plain_path_opens_plain_project
test_case "taw: plain project picker target opens plain directory" \
  test_plain_project_picker_target_opens_plain_directory
test_case "taw: plain project rejects branch and operands" \
  test_plain_project_rejects_branch_and_operands
test_case "taw: -p preserves invoking shell cwd" \
  test_project_arg_preserves_invoking_shell_cwd
test_case "taw: -p GitHub URL clones and opens project" \
  test_project_arg_github_url_clones_and_opens_project
test_case "taw: -p URL allows explicit bare clone" \
  test_project_arg_url_allows_explicit_bare_clone
test_case "taw: -p resolves by tmux session name" \
  test_project_arg_resolves_by_tmux_session_name
test_case "taw: -p resolves by tmux session path basename" \
  test_project_arg_resolves_by_tmux_session_path_basename
test_case "taw: -p exact tmux match failure does not fallback" \
  test_project_arg_exact_tmux_match_failure_does_not_fallback
test_case "taw: unresolved -p refusal makes no mutation" \
  test_project_arg_unresolved_create_refusal_makes_no_mutation
test_case "taw: unresolved -p rejects invalid create kind" \
  test_project_arg_unresolved_rejects_invalid_create_kind
test_case "taw: unresolved -p creates plain, repo, and bare projects" \
  test_unresolved_project_flag_creates_plain_repo_and_bare_projects
test_case "taw: prompt input creates repo project" \
  test_prompt_input_unresolved_creates_repo_project
test_case "taw: outside positional shorthand creates repo project" \
  test_outside_positional_unresolved_creates_repo_project
test_case "taw: unresolved repo branch target creates worktree" \
  test_unresolved_repo_branch_target_creates_worktree
test_case "taw: unresolved creation rejects invalid repo and bare names" \
  test_unresolved_project_creation_rejects_invalid_repo_and_bare_names_before_mkdir
test_case "taw: unresolved creation rejects two pending operands before mkdir" \
  test_unresolved_project_creation_rejects_two_pending_operands_before_mkdir
test_case "taw: bare creation rejects escape and absolute worktree inputs before mkdir" \
  test_bare_creation_rejects_escape_and_absolute_worktree_inputs_before_mkdir
test_case "taw: bare creation pending worktree path becomes branch" \
  test_bare_creation_pending_worktree_path_becomes_branch
test_case "taw: URL clone failure does not prompt create" \
  test_url_clone_failure_does_not_prompt_create
test_case "taw: existing file and broken symlink fail without create prompt" \
  test_existing_file_and_broken_symlink_fail_without_create_prompt
test_case "taw: PROJECTS_HOME file and broken symlink fail without create prompt" \
  test_projects_home_file_and_broken_symlink_fail_without_create_prompt
test_case "taw: outside promotion uses single positional as project arg" \
  test_outside_promotion_uses_single_positional_as_project_arg
test_case "taw: outside promotion uses project and operand positionals" \
  test_outside_promotion_uses_project_and_operand_positionals
test_case "taw: outside promotion rejects -b outside a project" \
  test_outside_promotion_rejects_branch_flag
test_case "taw: creates bare worktree from positional base ref" \
  test_creates_bare_worktree_from_positional_base_ref
test_case "taw: creates bare worktree from positional path branch" \
  test_creates_bare_worktree_from_positional_path_branch
test_case "taw: bare positional worktree supports -sh= command" \
  test_bare_positional_worktree_supports_shell_equals_command
test_case "taw: shell option skips existing window reuse" \
  test_shell_option_skips_existing_window_reuse
test_case "taw: positional base ref overrides named branch" \
  test_positional_base_ref_overrides_named_branch
test_case "taw: supports bare child not named .git" \
  test_supports_bare_child_not_named_git
test_case "taw: conventional bare clone places worktrees outside git dir" \
  test_conventional_bare_clone_places_worktrees_outside_git_dir
test_case "taw: conventional bare worktree detection keeps project root" \
  test_conventional_bare_worktree_detection_keeps_project_root
test_case "taw: bare project without worktree opens default branch worktree" \
  test_bare_project_without_worktree_opens_default_branch_worktree
test_case "taw: bare default worktree reuses existing window" \
  test_bare_default_worktree_window_is_reused
test_case "taw: bare project without default falls back to master" \
  test_bare_project_without_default_falls_back_to_master
test_case "taw: bare project with only origin HEAD creates local default worktree" \
  test_bare_project_origin_head_only_creates_local_default_worktree
test_case "taw: bare default worktree fails when refs exist but no default resolves" \
  test_bare_zero_worktree_fails_when_refs_exist_but_no_default_resolves
test_case "taw: bare default worktree fails when only tag ref exists" \
  test_bare_zero_worktree_fails_when_only_tag_ref_exists
test_case "taw: bare picker lists deduped branches" \
  test_bare_picker_lists_deduped_branches
test_case "taw: bare picker remote branch creates local worktree" \
  test_bare_picker_remote_branch_creates_local_worktree
test_case "taw: bare picker prefers origin for duplicate remotes" \
  test_bare_picker_prefers_origin_for_duplicate_remotes
test_case "taw: bare picker strips slash remote names" \
  test_bare_picker_strips_slash_remote_names
test_case "taw: bare picker cancel returns success" \
  test_bare_picker_cancel_returns_success_without_tmux
test_case "taw: bare picker without fzf falls back to default" \
  test_bare_picker_without_fzf_falls_back_to_default_worktree
test_case "taw: bare picker error fails" \
  test_bare_picker_error_fails_without_tmux
test_case "taw: bare remote-only branch tracks upstream" \
  test_bare_remote_only_branch_sets_upstream_tracking
test_case "taw: bare zero worktree uses head branch when no refs exist" \
  test_bare_zero_worktree_uses_head_branch_when_no_refs_exist
test_case "taw: bare project -b opens branch worktree" \
  test_bare_project_named_branch_without_worktree_opens_branch_worktree
test_case "taw: explicit bare worktree subdir with -b opens project root worktree" \
  test_explicit_bare_worktree_subdir_with_branch_opens_project_root_worktree
test_case "taw: explicit bare worktree subdir without operands opens containing worktree root" \
  test_explicit_bare_worktree_subdir_without_operands_opens_containing_worktree_root
test_case "taw: explicit bare worktree root without operands opens containing worktree root" \
  test_explicit_bare_worktree_root_without_operands_opens_containing_worktree_root
test_case "taw: bare project reuses existing default branch worktree when confirmed" \
  test_bare_project_reuses_existing_default_branch_worktree_when_confirmed
test_case "taw: bare project branch with slash creates nested worktree" \
  test_bare_project_branch_with_slash_creates_nested_worktree
test_case "taw: bare project local slash base ref stays local" \
  test_bare_project_local_slash_base_ref_stays_local
test_case "taw: bare project invalid branch does not create parent dirs" \
  test_bare_project_invalid_branch_does_not_create_parent_dirs
test_case "taw: bare project relative worktree escape is rejected" \
  test_bare_project_relative_worktree_escape_is_rejected
test_case "taw: bare project absolute worktree path must stay under wrapper" \
  test_bare_project_absolute_worktree_path_must_stay_under_wrapper
test_case "taw: bare project dot-segment worktree paths are rejected" \
  test_bare_project_dot_segment_worktree_paths_are_rejected
test_case "taw: normal repo creates worktree from single positional" \
  test_normal_repo_checks_out_branch_from_single_positional
test_case "taw: normal repo positional remote-only branch tracks upstream" \
  test_normal_repo_single_positional_tracks_remote_only_branch
test_case "taw: normal repo positional remote branch preserves narrow fetch refspec" \
  test_normal_repo_positional_remote_branch_preserves_narrow_fetch_refspec
test_case "taw: normal repo positional remote branch preserves multiple fetch refspecs" \
  test_normal_repo_positional_remote_branch_preserves_multiple_fetch_refspecs
test_case "taw: normal repo positional remote branch adds missing fetch refspec" \
  test_normal_repo_positional_remote_branch_adds_missing_fetch_refspec
test_case "taw: normal repo remote-prefixed positional uses resolved branch" \
  test_normal_repo_remote_prefixed_positional_uses_resolved_branch
test_case "taw: normal repo positional missing configured remote ref fails" \
  test_normal_repo_positional_missing_configured_remote_ref_fails
test_case "taw: normal repo positional rejects refs/remotes prefix" \
  test_normal_repo_positional_rejects_refs_remotes_prefix
test_case "taw: normal repo positional unresolved slash branch uses HEAD" \
  test_normal_repo_positional_unresolved_slash_branch_uses_head
test_case "taw: normal repo accepts worktree path and base ref" \
  test_normal_repo_rejects_two_positional_operands
test_case "taw: rejects unrelated git repo at worktree path" \
  test_rejects_unrelated_git_repo_at_worktree_path
test_case "taw: rejects empty required command values" \
  test_rejects_empty_required_command_values
test_case "taw: existing worktree branch switch prompts" \
  test_existing_worktree_branch_switch_prompts
test_case "taw: existing normal worktree preserves remote fetch refspecs" \
  test_existing_normal_worktree_remote_branch_preserves_fetch_refspecs
test_case "taw: existing worktree without base uses project head" \
  test_existing_worktree_without_base_uses_project_head
test_case "taw: rejects empty project and branch values" \
  test_rejects_empty_project_and_branch_values
test_case "taw: prompts for repo path outside git" \
  test_prompts_for_existing_repo_when_not_inside_git
test_case "taw: debug option prints state snapshot" \
  test_debug_option_prints_state_snapshot
test_case "taw: prompted project resolves from PROJECTS_HOME" \
  test_prompted_project_resolves_from_projects_home
test_case "taw: non-git child under bare wrapper prompts for project" \
  test_non_git_child_under_bare_wrapper_prompts_for_project
test_case "taw: non-git parent with bare wrapper child prompts for project" \
  test_non_git_parent_with_bare_wrapper_child_prompts_for_project
test_case "taw: current bare wrapper auto-detects without prompt" \
  test_current_bare_wrapper_auto_detects_without_prompt
test_case "taw: empty project prompt opens tmux-sessionizer project picker" \
  test_empty_prompt_selects_project_from_tmux_sessionizer_config
test_case "taw: empty project prompt mentions fzf" \
  test_empty_project_prompt_mentions_fzf
test_case "taw: project picker uses Zsh directory traversal" \
  test_project_picker_uses_zsh_directory_traversal
test_case "taw: project picker skips control characters in paths" \
  test_project_picker_skips_control_characters_in_discovered_paths
test_case "taw: project picker rejects control characters in tmux sessions" \
  test_project_picker_rejects_control_characters_in_tmux_sessions
test_case "taw: project picker batches tmux session metadata" \
  test_project_picker_batches_tmux_session_metadata
test_case "taw: explicit picker prefetches mode snapshots" \
  test_explicit_picker_prefetches_mode_snapshots
test_case "taw: explicit picker starts fzf before rows finish" \
  test_explicit_picker_starts_fzf_before_rows_finish
test_case "taw: explicit picker handles early fzf exit" \
  test_explicit_picker_handles_early_fzf_exit
test_case "taw: project picker skips unsafe current tmux session" \
  test_project_picker_skips_unsafe_current_tmux_session
test_case "taw: empty project prompt picker resolves tmux session rows" \
  test_empty_prompt_project_picker_resolves_tmux_session_row
test_case "taw: project picker tmux row preserves active window inside tmux" \
  test_project_picker_tmux_row_preserves_active_window_inside_tmux
test_case "taw: project picker tmux row links active window with peer" \
  test_project_picker_tmux_row_links_active_window_with_peer
test_case "taw: project picker tmux row reuses linked active window with peer" \
  test_project_picker_tmux_row_reuses_linked_active_window_with_peer
test_case "taw: project picker tmux row uses session identity" \
  test_project_picker_tmux_row_uses_session_identity
test_case "taw: project picker tmux row ignores PROJECTS_HOME collision" \
  test_project_picker_tmux_row_ignores_projects_home_collision
test_case "taw: project picker tmux row fails if session disappears" \
  test_project_picker_tmux_row_fails_if_session_disappears
test_case "taw: project picker tmux row rejects same-name replacement" \
  test_project_picker_tmux_row_rejects_same_name_replacement
test_case "taw: project picker tmux row rejects replacement after revalidation" \
  test_project_picker_tmux_row_rejects_replacement_after_revalidation
test_case "taw: empty project prompt picker cancel returns without tmux window" \
  test_empty_prompt_project_picker_cancel_returns_without_tmux_window
test_case "taw: project prompt escape returns without tmux window" \
  test_project_prompt_escape_returns_without_tmux_window
test_case "taw: project picker flag bypasses current repo detection" \
  test_project_picker_flag_bypasses_current_repo_detection
test_case "taw: project picker flag cancel returns without tmux window" \
  test_project_picker_flag_cancel_returns_without_tmux_window
test_case "taw: project picker flag error fails without tmux window" \
  test_project_picker_flag_error_fails_without_tmux_window
test_case "taw: project picker flag ignores TAW_AGENT without explicit agent" \
  test_project_picker_flag_ignores_taw_agent_without_explicit_agent
test_case "taw: project picker flag opens bare wrapper default worktree without second picker" \
  test_project_picker_flag_opens_bare_wrapper_default_worktree_without_second_picker
test_case "taw: project picker flag rejects -p" \
  test_project_picker_flag_rejects_project_arg
test_case "taw: project picker aliases reject project, branch, and positionals" \
  test_project_picker_aliases_reject_project_branch_and_positionals
test_case "taw: project picker aliases allow agent, editor, and shells" \
  test_project_picker_aliases_allow_agent_editor_and_shells
test_case "taw: explicit picker mode aliases are accepted" \
  test_explicit_picker_mode_aliases_are_accepted
test_case "taw: session mode aliases use project picker" \
  test_session_mode_aliases_use_project_picker
test_case "taw: worktree mode opens linked normal worktree" \
  test_worktree_mode_opens_linked_normal_worktree
test_case "taw: worktree picker skips control characters in paths" \
  test_worktree_picker_skips_control_characters_in_paths
test_case "taw: worktree picker preserves spaces and Unicode in paths" \
  test_worktree_picker_preserves_spaces_and_unicode_in_paths
test_case "taw: branch mode opens existing worktree without checkout" \
  test_branch_mode_opens_existing_worktree_without_checkout
test_case "taw: branch mode checks out unassigned normal branch" \
  test_branch_mode_checks_out_unassigned_normal_branch
test_case "taw: branch mode creates unassigned bare worktree" \
  test_branch_mode_creates_unassigned_bare_worktree
test_case "taw: picker selects fzf bindings by version" \
  test_picker_selects_fzf_bindings_by_version
test_case "taw: legacy picker reports producer failure before fzf" \
  test_legacy_picker_reports_producer_failure_before_fzf
test_case "taw: picker acceptance keys select layouts" \
  test_picker_accept_keys_select_layouts
test_case "taw: picker layout keys apply to worktree and branch modes" \
  test_picker_layout_keys_apply_to_worktree_and_branch_modes
test_case "taw: picker layout is ignored for matching window" \
  test_picker_layout_is_ignored_for_matching_window
test_case "taw: picker layout creates window in existing session" \
  test_picker_layout_creates_window_in_existing_session
test_case "taw: picker tab cycles all modes and preserves query" \
  test_picker_tab_cycles_all_modes_and_preserves_query
test_case "taw: each explicit mode can cycle from its start" \
  test_each_explicit_mode_can_cycle_from_its_start
test_case "taw: session selection after project mode replaces context" \
  test_session_selection_after_project_mode_replaces_context
test_case "taw: project-scoped modes remain cycleable outside git" \
  test_project_scoped_modes_remain_cycleable_outside_git
test_case "taw: explicit picker keeps empty modes cycleable" \
  test_explicit_picker_keeps_empty_modes_cycleable
test_case "taw: invalid picker modes and combinations are rejected" \
  test_invalid_picker_modes_and_combinations_are_rejected
