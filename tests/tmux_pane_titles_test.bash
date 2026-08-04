TMUX_PANE_TITLES_FILE="$REPO_ROOT/home/.tmux-pane-titles.zsh"

run_title_hook() {
  local tmux_value="$1"
  local hook="$2"
  shift 2

  TMUX_PANE_TITLES_FILE="$TMUX_PANE_TITLES_FILE" TMUX="$tmux_value" \
    zsh -fc 'source "$TMUX_PANE_TITLES_FILE"; hook="$1"; shift; "$hook" "$@"' \
      zsh "$hook" "$@"
}

test_preexec_emits_command_title_inside_tmux() {
  local expected=$'\033]2;man\033\\'
  local actual

  actual="$(run_title_hook /tmp/tmux _tmux_pane_title_preexec 'man tmux')"
  assert_eq "$expected" "$actual" "unexpected preexec title sequence"
}

test_preexec_extracts_wrapped_command_name() {
  local expected=$'\033]2;man\033\\'
  local actual

  actual="$(run_title_hook /tmp/tmux _tmux_pane_title_preexec \
    'FOO=value sudo man tmux')"
  assert_eq "$expected" "$actual" "unexpected wrapped command title"
}

test_preexec_removes_control_characters() {
  local expected=$'\033]2;ma]2;evill\033\\'
  local actual

  actual="$(run_title_hook /tmp/tmux _tmux_pane_title_preexec \
    $'ma\033]2;evil\al topic')"
  assert_eq "$expected" "$actual" "control characters remained in pane title"
}

test_precmd_clears_title_inside_tmux() {
  local expected=$'\033]2;\033\\'
  local actual

  actual="$(run_title_hook /tmp/tmux _tmux_pane_title_precmd)"
  assert_eq "$expected" "$actual" "unexpected precmd title sequence"
}

test_hooks_are_silent_outside_tmux() {
  local preexec_output
  local precmd_output

  preexec_output="$(run_title_hook '' _tmux_pane_title_preexec 'man tmux')"
  precmd_output="$(run_title_hook '' _tmux_pane_title_precmd)"
  assert_eq "" "$preexec_output" "preexec emitted a title outside tmux"
  assert_eq "" "$precmd_output" "precmd emitted a title outside tmux"
}

test_hook_registration_is_idempotent() {
  local expected='_tmux_pane_title_preexec|_tmux_pane_title_precmd'
  local actual

  actual="$(
    TMUX_PANE_TITLES_FILE="$TMUX_PANE_TITLES_FILE" zsh -fc '
      source "$TMUX_PANE_TITLES_FILE"
      source "$TMUX_PANE_TITLES_FILE"
      print -r -- "${(j:,:)preexec_functions}|${(j:,:)precmd_functions}"
    '
  )"
  assert_eq "$expected" "$actual" "hook registration was duplicated"
}

test_case "tmux pane titles: preexec emits command title" \
  test_preexec_emits_command_title_inside_tmux
test_case "tmux pane titles: preexec extracts wrapped command" \
  test_preexec_extracts_wrapped_command_name
test_case "tmux pane titles: preexec removes control characters" \
  test_preexec_removes_control_characters
test_case "tmux pane titles: precmd clears command title" \
  test_precmd_clears_title_inside_tmux
test_case "tmux pane titles: hooks are silent outside tmux" \
  test_hooks_are_silent_outside_tmux
test_case "tmux pane titles: hook registration is idempotent" \
  test_hook_registration_is_idempotent
