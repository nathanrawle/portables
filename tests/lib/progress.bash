#!/usr/bin/env bash

TESTS_PROGRESS_ENABLED=0
PROGRESS_GROUPS=()
PROGRESS_CASE_GROUP=()
PROGRESS_LABELS=()
PROGRESS_TOTAL=()
PROGRESS_DONE=()
PROGRESS_FAILED=()
PROGRESS_STARTED=()
PROGRESS_SEEN_START=()
PROGRESS_SEEN_RESULT=()
PROGRESS_RENDERED=0
PROGRESS_FRAME=0
PROGRESS_RESIZED=0
PROGRESS_HEIGHT=0
PROGRESS_WIDTH=80
PROGRESS_MODE=static

progress_dimensions() {
  local dimensions height width
  # Command substitution replaces stdout, so retain the terminal while measuring it.
  { dimensions="$(stty size <&3 2>/dev/null)" || dimensions=; } 3>&1
  if read -r height width <<<"$dimensions" \
    && [[ "$height" =~ ^[1-9][0-9]*$ && "$width" =~ ^[1-9][0-9]*$ ]]; then
    PROGRESS_HEIGHT="$height"
    PROGRESS_WIDTH="$width"
  else
    PROGRESS_HEIGHT=0
    PROGRESS_WIDTH=80
  fi
}

progress_initialize() {
  local manifest="$1" ordinal group other label i
  local -a file_keys file_groups
  for ((i = 0; i < ${#test_files[@]}; i++)); do
    file_keys[$i]="$(cd -- "$(dirname -- "${test_files[$i]}")" && pwd -P)/${test_files[$i]##*/}"
    file_groups[$i]="$i"
    for ((other = 0; other < i; other++)); do
      if [[ "${file_keys[$i]}" == "${file_keys[$other]}" ]]; then
        file_groups[$i]="${file_groups[$other]}"
        break
      fi
    done
  done
  while IFS=$'\t' read -r ordinal group; do
    group="${file_groups[$group]}"
    PROGRESS_CASE_GROUP[$ordinal]="$group"
    PROGRESS_TOTAL[$group]=$(( ${PROGRESS_TOTAL[$group]:-0} + 1 ))
  done <"$manifest"
  for ((i = 0; i < ${#test_files[@]}; i++)); do
    [[ ${PROGRESS_TOTAL[$i]:-0} -gt 0 ]] || continue
    PROGRESS_GROUPS+=( "$i" )
    PROGRESS_DONE[$i]=0
    PROGRESS_FAILED[$i]=0
    PROGRESS_STARTED[$i]=0
    label="${test_files[$i]##*/}"
    for ((other = 0; other < ${#test_files[@]}; other++)); do
      [[ "$other" != "$i" && ${PROGRESS_TOTAL[$other]:-0} -gt 0 ]] || continue
      if [[ "$label" == "${test_files[$other]##*/}" ]]; then
        label="${test_files[$i]}"
        break
      fi
    done
    # Shell quoting keeps control characters in supplied filenames out of the terminal.
    printf -v label '%q' "$label"
    PROGRESS_LABELS[$i]="$label"
  done
  progress_dimensions
  if [[ ${#PROGRESS_GROUPS[@]} -lt "$PROGRESS_HEIGHT" && "$PROGRESS_WIDTH" -ge 40 ]]; then
    PROGRESS_MODE=animated
  fi
  trap 'PROGRESS_RESIZED=1' WINCH
  progress_draw running
}

progress_collect() {
  local record ordinal group status name
  shopt -s nullglob
  for record in "$TESTS_PARALLEL_TMP"/started-*; do
    ordinal=$((10#${record##*-}))
    [[ ${PROGRESS_SEEN_START[$ordinal]:-0} -eq 0 ]] || continue
    PROGRESS_SEEN_START[$ordinal]=1
    group="${PROGRESS_CASE_GROUP[$ordinal]:-}"
    [[ -n "$group" ]] || continue
    PROGRESS_STARTED[$group]=1
  done
  for record in "$TESTS_PARALLEL_TMP"/result-*; do
    [[ "$record" != *.tmp ]] || continue
    ordinal=$((10#${record##*-}))
    [[ ${PROGRESS_SEEN_RESULT[$ordinal]:-0} -eq 0 ]] || continue
    PROGRESS_SEEN_RESULT[$ordinal]=1
    group="${PROGRESS_CASE_GROUP[$ordinal]:-}"
    [[ -n "$group" ]] || continue
    IFS=$'\t' read -r status name <"$record"
    PROGRESS_DONE[$group]=$((PROGRESS_DONE[$group] + 1))
    if [[ "$status" != ok ]]; then
      PROGRESS_FAILED[$group]=$((PROGRESS_FAILED[$group] + 1))
    fi
  done
  shopt -u nullglob
}

progress_draw() {
  local phase="$1" group symbol state text suffix label label_width old_width frames='|/-\'
  [[ ${#PROGRESS_GROUPS[@]} -gt 0 ]] || return 0
  if [[ "$PROGRESS_RESIZED" -eq 1 ]]; then
    old_width="$PROGRESS_WIDTH"
    progress_dimensions
    PROGRESS_RESIZED=0
    # Reflowed rows cannot safely be addressed by their old cursor offsets.
    if [[ "$PROGRESS_WIDTH" -lt "$old_width" \
      || ${#PROGRESS_GROUPS[@]} -ge "$PROGRESS_HEIGHT" ]]; then
      PROGRESS_MODE=static
      PROGRESS_RENDERED=0
    fi
  fi
  if [[ "$PROGRESS_MODE" == animated && "$PROGRESS_RENDERED" -gt 0 ]]; then
    printf '\033[%dA' "$PROGRESS_RENDERED"
  elif [[ "$phase" == running && "$PROGRESS_RENDERED" -gt 0 ]]; then
    return 0
  fi
  for group in "${PROGRESS_GROUPS[@]}"; do
    symbol='-'
    state=QUEUED
    if [[ "${PROGRESS_DONE[$group]}" -eq "${PROGRESS_TOTAL[$group]}" ]]; then
      symbol='+'
      state=PASS
      if [[ "${PROGRESS_FAILED[$group]}" -gt 0 ]]; then
        symbol='!'
        state=FAIL
      fi
    elif [[ "$phase" != running ]]; then
      state=ERROR
      [[ "$phase" != cancelled ]] || state=CANCELLED
    elif [[ "${PROGRESS_STARTED[$group]}" -eq 1 ]]; then
      symbol="${frames:PROGRESS_FRAME:1}"
      state=RUNNING
    fi
    suffix=" (${PROGRESS_DONE[$group]}/${PROGRESS_TOTAL[$group]}) $state"
    if [[ "${PROGRESS_FAILED[$group]}" -gt 0 ]]; then
      suffix="$suffix, ${PROGRESS_FAILED[$group]} failed"
    fi
    label="${PROGRESS_LABELS[$group]}"
    if [[ "$PROGRESS_MODE" == animated ]]; then
      label_width=$((PROGRESS_WIDTH - ${#suffix} - 3))
      if [[ ${#label} -gt "$label_width" ]]; then
        label="...${label: -label_width+3}"
      fi
      text="$symbol $label$suffix"
      printf '\r\033[K%s\n' "${text:0:PROGRESS_WIDTH-1}"
    else
      printf '%s\n' "$symbol $label$suffix"
    fi
  done
  PROGRESS_RENDERED="${#PROGRESS_GROUPS[@]}"
  PROGRESS_FRAME=$(( (PROGRESS_FRAME + 1) % 4 ))
}

progress_finish() {
  [[ "$TESTS_PROGRESS_ENABLED" -eq 1 ]] || return 0
  progress_collect
  progress_draw "$1"
  TESTS_PROGRESS_ENABLED=0
  trap - WINCH
}
