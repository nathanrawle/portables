#!/usr/bin/env bash

# This script creates symlinks into the home directory.

functions log >/dev/null 2>&1 || . "$PORTABLES"/log

case "$1" in
install) echo self-install ;;
config)
  shopt -s nullglob

  THIS="$(realpath "$0" 2>/dev/null || command -v "$0")"
  HERE="$(dirname "$THIS")"
  PORTABLES="$(dirname "$HERE")"
  PORTABLE_HOME=$PORTABLES/home

  if [[ -n "${HOST-}" ]]; then
    MACHINE=${HOST%%.*}
  else
    MACHINE=$(hostname 2>/dev/null) || MACHINE=mystery-box
    MACHINE=${MACHINE%%.*}
  fi

  log .symln "symlinking…"

  items="$PORTABLE_HOME"/{.[!.]*,*}
  [[ -n "$items" ]] && log .symln "linking homedir files…"
  for item in $items; do
    [[ -f "$item" ]] || continue
    destination="$HOME/${item##*/}"
    ln -sf "$item" "$destination" &&
      log -d .symln "  linked $item -> $destination"
  done

  PORTABLE_DOTCONFIG="$PORTABLE_HOME/.config"
  HOME_DOTCONFIG="$HOME/.config"

  items="$PORTABLE_DOTCONFIG"/{.[!.]*,*}
  [[ -n "$items" ]] && log .symln "linking .config entries…"
  for item in $items; do
    [[ -f "$item" ]] || [[ -d "$item" ]] || continue
    destination="$HOME_DOTCONFIG/${item##*/}"
    rm -rf "$destination"
    ln -shf "$item" "$destination" &&
      log -d .symln "  linked $item -> $destination"
  done

  # --- 3. Link contents of Library directory (macOS) ---
  if [[ "$OS" = "Darwin" ]]; then
    PORTABLE_LIBRARY="$PORTABLE_HOME/Library"
    HOME_LIBRARY="$HOME/Library"
    if [ -d "$PORTABLE_LIBRARY" ]; then
      items="$PORTABLE_LIBRARY"/{.[!.]*,*}
      [[ -n "$items" ]] && log .symln "linking macOS Library entries…"
      for item in $items; do
        [[ -f "$item" ]] || [[ -d "$item" ]] || continue
        destination="$HOME_LIBRARY/${item##*/}"
        rm -rf "$destination"
        ln -shf "$item" "$destination" &&
          log -d .symln "  linked $item -> $destination"
      done
    fi
  fi

  # --- 4. Link contents of fns directory ---
  for fundir in pfuns bfuns zfuns; do
    PORTABLE_FUNDIR="$PORTABLE_HOME/.$fundir"

    if [[ -d "$PORTABLE_FUNDIR" ]]; then
      HOME_FUNDIR=$HOME/.$fundir
      log .symln "linking $fundir functions"
      mkdir -p "$HOME_FUNDIR"

      items="$PORTABLE_FUNDIR"/{.[!.]*,*}
      for item in $items; do
        [[ -f "$item" ]] || continue
        destination="$HOME_FUNDIR/${item##*/}"
        rm -rf "$destination"
        ln -shf "$item" "$destination" &&
          log -d .symln "  linked $item -> $destination"
      done
    fi
  done

  log .symln "symlinking complete."

  shopt -u nullglob
  ;;
esac
