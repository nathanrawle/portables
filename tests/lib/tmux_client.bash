TEST_TMUX_CLIENT_PID=
TEST_TMUX_CLIENT_NAME=

start_tmux_test_client() {
  local socket="$1" session="$2" i
  mkfifo "$TEST_TMPDIR/client-input"
  tmux -L "$socket" -C attach-session -t "$session" \
    <"$TEST_TMPDIR/client-input" >"$TEST_TMPDIR/client-output" 2>&1 &
  TEST_TMUX_CLIENT_PID=$!
  exec 9>"$TEST_TMPDIR/client-input"
  for ((i = 0; i < 100; i++)); do
    TEST_TMUX_CLIENT_NAME="$(tmux -L "$socket" list-clients -F '#{client_name}')"
    [[ -z "$TEST_TMUX_CLIENT_NAME" ]] || break
    sleep 0.02
  done
  [[ -n "$TEST_TMUX_CLIENT_NAME" ]] || fail "control client did not attach: $(cat "$TEST_TMPDIR/client-output")"
  tmux -L "$socket" refresh-client -t "$TEST_TMUX_CLIENT_NAME" -C "${3:-180,60}"
}

stop_tmux_test_client() {
  if [[ -n "$TEST_TMUX_CLIENT_PID" ]]; then
    exec 9>&-
    kill "$TEST_TMUX_CLIENT_PID" >/dev/null 2>&1 || true
    wait "$TEST_TMUX_CLIENT_PID" >/dev/null 2>&1 || true
  fi
}
