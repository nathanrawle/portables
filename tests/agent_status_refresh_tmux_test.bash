#!/usr/bin/env bash

REFRESH_REAL_TMUX=
REFRESH_REAL_SOCKET=

cleanup_refresh_tmux() {
  if [[ -n "$REFRESH_REAL_TMUX" && -n "$REFRESH_REAL_SOCKET" ]]; then
    "$REFRESH_REAL_TMUX" -L "$REFRESH_REAL_SOCKET" kill-server >/dev/null 2>&1 || true
  fi
}

refresh_tmux() {
  "$REFRESH_REAL_TMUX" -L "$REFRESH_REAL_SOCKET" "$@"
}

run_real_refresh_status() {
  TMUX="$REFRESH_REAL_ADDRESS" TMUX_PANE="$REFRESH_REAL_PANE" \
    HOME="$REFRESH_REAL_HOME" CLAUDE_CONFIG_DIR="$REFRESH_REAL_CONFIG" \
    PATH="$REFRESH_REAL_BIN:$PATH" "$REPO_ROOT/home/.zfuns/taw-agent-status" "$@"
}

reset_real_refresh_timer() {
  refresh_tmux set-option -gu @taw_agent_refresh_at
}

test_real_refresh_lifecycle_and_guard() {
  local pane root owner window started state meta snapshot guard address i

  REFRESH_REAL_TMUX="$(command -v tmux || true)"
  [[ -n "$REFRESH_REAL_TMUX" ]] || return 0
  REFRESH_REAL_SOCKET="portables-status-refresh-$$-$RANDOM"
  REFRESH_REAL_HOME="$TEST_TMPDIR/home"
  REFRESH_REAL_CONFIG="$TEST_TMPDIR/claude config"
  REFRESH_REAL_BIN="$TEST_TMPDIR/bin"
  mkdir -p "$REFRESH_REAL_HOME/.zfuns" "$REFRESH_REAL_CONFIG/sessions" "$REFRESH_REAL_BIN"
  trap cleanup_refresh_tmux EXIT
  cat >"$REFRESH_REAL_BIN/tmux" <<'MOCK'
#!/usr/bin/env bash
if [[ "${REFRESH_ACK_RACE:-}" == 1 && "$1" == show-option \
  && "${5:-}" == @taw_agent_state ]]; then
  "$REFRESH_REAL_TMUX" -L "$REFRESH_REAL_SOCKET" "$@"
  "$REFRESH_REAL_TMUX" -L "$REFRESH_REAL_SOCKET" \
    set-option -p -t "$4" @taw_agent_state thinking
  exit 0
fi
exec "$REFRESH_REAL_TMUX" -L "$REFRESH_REAL_SOCKET" "$@"
MOCK
  chmod +x "$REFRESH_REAL_BIN/tmux"
  export REFRESH_REAL_TMUX REFRESH_REAL_SOCKET
  pane="$(HOME="$REFRESH_REAL_HOME" "$REFRESH_REAL_TMUX" -L "$REFRESH_REAL_SOCKET" \
    -f /dev/null new-session -d -P -F '#{pane_id}' -s source \
    "bash -c 'sleep 300 & echo \$! > \"$TEST_TMPDIR/owner\"; wait; while :; do sleep 300; done'")"
  REFRESH_REAL_PANE="$pane"
  REFRESH_REAL_ADDRESS="$(refresh_tmux display-message -p '#{socket_path},#{pid},0')"
  for ((i = 0; i < 100; i++)); do
    [[ ! -s "$TEST_TMPDIR/owner" ]] || break
    sleep 0.02
  done
  [[ -s "$TEST_TMPDIR/owner" ]] || fail 'expected child process identity'
  owner="$(cat "$TEST_TMPDIR/owner")"
  root="$(refresh_tmux display-message -p -t "$pane" '#{pane_pid}')"
  window="$(refresh_tmux display-message -p -t "$pane" '#{window_id}')"
  started="$(TZ=UTC LC_ALL=C ps -p "$owner" -o lstart=)"
  started="${started#"${started%%[![:space:]]*}"}"
  started="${started%"${started##*[![:space:]]}"}"
  jq -n --argjson pid "$owner" --arg start "$started" --arg pane "$pane" \
    --arg window "$window" --arg domain "$(uname -s | tr '[:upper:]' '[:lower:]')" '{
      pid: $pid, kind: "interactive", pidDomain: $domain,
      sessionId: "b666ce8b-aadb-45ec-8e51-95e5bc28e985", procStart: $start,
      tmux: ("source:" + $window + "." + $pane), status: "busy", statusUpdatedAt: 1
    }' >"$REFRESH_REAL_CONFIG/sessions/$owner.json"
  jq '.status = "idle" | .statusUpdatedAt = 2' \
    "$REFRESH_REAL_CONFIG/sessions/$owner.json" >"$TEST_TMPDIR/record"
  mv "$TEST_TMPDIR/record" "$REFRESH_REAL_CONFIG/sessions/$owner.json"
  refresh_tmux set-option -p -t "$pane" @taw_agent claude
  refresh_tmux set-option -p -t "$pane" @taw_agent_state thinking
  refresh_tmux set-option -p -t "$pane" @taw_agent_pane_pid "$root"
  run_real_refresh_status refresh
  assert_eq idle "$(refresh_tmux show-option -pqv -t "$pane" @taw_agent_state)" \
    'expected an already-stale pane without recovery metadata to recover'
  reset_real_refresh_timer
  run_real_refresh_status start claude <<< '{"session_id":"b666ce8b-aadb-45ec-8e51-95e5bc28e985"}'
  run_real_refresh_status hook claude thinking <<< '{"session_id":"b666ce8b-aadb-45ec-8e51-95e5bc28e985"}'
  meta="$(refresh_tmux show-option -pqv -t "$pane" @taw_claude_status)"
  assert_eq "$owner" "$(jq -r '.route | split("\t")[0]' <<<"$meta")" \
    'expected descendant process tracked at startup'
  jq --argjson at "$(jq '.event_at + 1' <<<"$meta")" \
    '.status = "idle" | .statusUpdatedAt = $at' \
    "$REFRESH_REAL_CONFIG/sessions/$owner.json" >"$TEST_TMPDIR/record"
  mv "$TEST_TMPDIR/record" "$REFRESH_REAL_CONFIG/sessions/$owner.json"
  run_real_refresh_status refresh
  state="$(refresh_tmux show-option -pqv -t "$pane" @taw_agent_state)"
  assert_eq idle "$state" 'expected native idle to recover thinking'

  snapshot="$(refresh_tmux show-option -pqv -t "$pane" @taw_agent_revision)"
  run_real_refresh_status hook claude thinking <<< '{}'
  guard="#{&&:#{==:#{pane_pid},$root},#{&&:#{==:#{@taw_agent},claude},#{&&:#{==:#{@taw_agent_state},thinking},#{==:#{@taw_agent_revision},$snapshot}}}}"
  refresh_tmux if-shell -F -t "$pane" "$guard" \
    "set-option -p -t $pane @taw_agent_state idle"
  assert_eq thinking "$(refresh_tmux show-option -pqv -t "$pane" @taw_agent_state)" \
    'expected stale recovery snapshot to preserve new hook'

  refresh_tmux set-option -p -t "$pane" @taw_agent_state waiting
  REFRESH_ACK_RACE=1 run_real_refresh_status acknowledge "$pane"
  assert_eq thinking "$(refresh_tmux show-option -pqv -t "$pane" @taw_agent_state)" \
    'expected delayed acknowledgement to preserve newer thinking state'

  kill "$owner"
  reset_real_refresh_timer
  run_real_refresh_status refresh
  assert_eq '' "$(refresh_tmux show-option -pqv -t "$pane" @taw_agent)" \
    'expected abrupt child exit to clear metadata'
  refresh_tmux has-session -t source || fail 'expected source pane session preserved'
  if refresh_tmux has-session -t agents 2>/dev/null; then
    fail 'expected exited agent to be removed from managed session'
  fi

  cat >"$REFRESH_REAL_HOME/.zfuns/taw-agent-status" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "${TMUX:-unset}" >"$REFRESH_JOB_ADDRESS"
exec "$REFRESH_JOB_STATUS" "$@"
MOCK
  chmod +x "$REFRESH_REAL_HOME/.zfuns/taw-agent-status"
  refresh_tmux set-environment -g REFRESH_JOB_ADDRESS "$TEST_TMPDIR/job-address"
  refresh_tmux set-environment -g REFRESH_JOB_STATUS "$REPO_ROOT/home/.zfuns/taw-agent-status"
  refresh_tmux set-environment -g CLAUDE_CONFIG_DIR "$REFRESH_REAL_CONFIG"
  refresh_tmux set-environment -g PATH "$REFRESH_REAL_BIN:$PATH"
  refresh_tmux source-file "$REPO_ROOT/home/.config/tmux/tmux.conf"
  assert_eq 5 "$(refresh_tmux show-option -gv status-interval)" 'expected five-second refresh'
  address="$(refresh_tmux show-option -gv status-right)"
  [[ "$address" == *'taw-agent-status" refresh'* ]] || fail 'expected quiet status refresh job'
  rm -f "$TEST_TMPDIR/job-address"
  for ((i = 0; i < 100; i++)); do
    refresh_tmux display-message -p -t "$pane" '#{E:status-right}' >/dev/null
    [[ ! -s "$TEST_TMPDIR/job-address" ]] || break
    sleep 0.02
  done
  [[ -s "$TEST_TMPDIR/job-address" ]] || fail 'expected status rendering to schedule refresh'
  address="$(cat "$TEST_TMPDIR/job-address")"
  [[ "$address" == "$REFRESH_REAL_ADDRESS" ]] || fail "expected isolated server routing: $address"
}

test_case 'agent refresh tmux: recovers turns and exits, and guards newer publications' \
  test_real_refresh_lifecycle_and_guard
