#!/bin/bash

# This script creates symlinks from the dotfiles into the home directory.
# It is the final step in the configuration pass.

case "$1" in
  install) echo self-install ;;
  config)
    HERE="$(cd -- "$(dirname -- "$0")" >/dev/null 2>&1 && pwd)"
    DEV_SPEC="$(cd -- "$HERE/.." >/dev/null 2>&1 && pwd)"
    PORTABLE_HOME=$DEV_SPEC/home

    if [ -n "${HOST-}" ]; then
      MACHINE=${HOST%%.*}
    else
      MACHINE=$(hostname 2>/dev/null) || MACHINE=mystery-box
      MACHINE=${MACHINE%%.*}
    fi

    echo "Creating symlinks..."

    for item in "$PORTABLE_HOME"/{.[!.]*,*}; do
      [ -f "$item" ] || continue
      destination="$HOME/${item##*/}"
      ln -sf "$item" "$destination" \
        && echo "  Linked $item -> $destination"
      done

      PORTABLE_DOTCONFIG="$PORTABLE_HOME/.config"
      HOME_DOTCONFIG="$HOME/.config"

      for item in "$PORTABLE_DOTCONFIG"/{.[!.]*,*}; do
        [ "${item##*/}"  = ".[!.]*" ] && continue
        destination="$HOME_DOTCONFIG/${item##*/}"
        ln -sf "$item" "$destination" \
          && echo "  Linked $item -> $destination"
        done

        # --- 3. Link contents of Library directory (macOS) ---
        if [ "$OS" = "Darwin" ]; then
          PORTABLE_LIBRARY="$PORTABLE_HOME/Library"
          HOME_LIBRARY="$HOME/Library"

          if [ -d "$PORTABLE_LIBRARY" ]; then
            echo "Linking contents of Library..."

            for item in "$PORTABLE_LIBRARY"/{.[!.]*,*}; do
              [ "${item##*/}"  = ".[!.]*" ] && continue
              destination="$HOME_LIBRARY/${item##*/}"
              ln -sf "$item" "$destination" \
                && echo "  Linked $item -> $destination"
              done
          fi
        fi

        # --- 4. Link contents of fns directory ---
        PORTABLE_DOTFUNS="$PORTABLE_HOME/.funs"
        HOME_DOTFUNS="$HOME/.funs"

        if [ -d "$PORTABLE_DOTFUNS" ]; then
          echo "Linking functions"
          mkdir -p "$HOME_DOTFUNS"
          for item in "$PORTABLE_DOTFUNS"/{.[!.]*,*}; do
            [ "${item##*/}" = ".[!.]*" ] && continue
            destination="$HOME_DOTFUNS/${item##*/}"

            ln -sf "$item" "$destination" \
              && echo "  Linked $item -> $destination"
            done
        fi

        echo "Symlinking complete."
        ;;
    esac
