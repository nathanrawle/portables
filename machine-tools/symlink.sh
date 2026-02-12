#!/usr/bin/env bash

# This script creates symlinks into the home directory.

case "$1" in
install) echo self-install ;;
config)
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

  echo "Creating symlinks..."

  for item in "$PORTABLE_HOME"/{.[!.]*,*}; do
    [[ -f "$item" ]] || continue
    destination="$HOME/${item##*/}"
    ln -sf "$item" "$destination" &&
      echo "  Linked $item -> $destination"
  done

  PORTABLE_DOTCONFIG="$PORTABLE_HOME/.config"
  HOME_DOTCONFIG="$HOME/.config"

  for item in "$PORTABLE_DOTCONFIG"/{.[!.]*,*}; do
    [[ -f "$item" ]] || [[ -d "$item" ]] || continue
    destination="$HOME_DOTCONFIG/${item##*/}"
    rm -rf "$destination"
    ln -shf "$item" "$destination" &&
      echo "  Linked $item -> $destination"
  done

  # --- 3. Link contents of Library directory (macOS) ---
  if [[ "$OS" = "Darwin" ]]; then
    PORTABLE_LIBRARY="$PORTABLE_HOME/Library"
    HOME_LIBRARY="$HOME/Library"

    if [ -d "$PORTABLE_LIBRARY" ]; then
      echo "Linking contents of Library..."

      for item in "$PORTABLE_LIBRARY"/{.[!.]*,*}; do
        [[ -f "$item" ]] || [[ -d "$item" ]] || continue
        destination="$HOME_LIBRARY/${item##*/}"
        rm -rf "$destination"
        ln -shf "$item" "$destination" &&
          echo "  Linked $item -> $destination"
      done
    fi
  fi

  # --- 4. Link contents of fns directory ---
  for fundir in pfuns bfuns zfuns; do
    PORTABLE_FUNDIR="$PORTABLE_HOME/.$fundir"
    if [[ -d "$PORTABLE_FUNDIR" ]]; then
      HOME_FUNDIR=$HOME/.$fundir
      echo "Linking $fundir functions"
      mkdir -p "$HOME_FUNDIR"
      for item in "$PORTABLE_FUNDIR"/{.[!.]*,*}; do
        [[ -f "$item" ]] || continue
        destination="$HOME_FUNDIR/${item##*/}"
        rm -rf "$destination"
        ln -shf "$item" "$destination" &&
          echo "  Linked $item -> $destination"
      done
    fi
  done

  echo "Symlinking complete."
  ;;
esac
