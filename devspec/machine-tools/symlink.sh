#!/bin/sh

# This script creates symlinks from the dotfiles into the home directory.
# It is the final step in the configuration pass.

case "$1" in
    config)
        HERE="$(cd -- "$(dirname -- "$0")" >/dev/null 2>&1 && pwd)"
        DEV_SPEC="$(cd -- "$HERE/../" >/dev/null 2>&1 && pwd)"
        PORTABLE_HOME=$DEV_SPEC/home

        if [ -n "${HOST-}" ]; then
          MACHINE=${HOST%%.*}
        else
          MACHINE=$(hostname 2>/dev/null) || MACHINE=mystery-box
          MACHINE=${MACHINE%%.*}
        fi

        echo "Creating symlinks..."

        # --- 1. Link top-level dotfiles ---
        echo "Linking top-level dotfiles..."
        for file in $PORTABLE_HOME/*; do
            [ -f "$file" ] || continue
            source="$file"
            destination="$HOME/$file"
            ln -sf "$source" "$destination"
            echo "  Linked $source -> $destination"
        done

        # --- 2. Link contents of .config directory ---
        PORTABLE_DOTCONFIG="$PORTABLE_HOME/.config"
        HOME_DOTCONFIG="$HOME/.config"

        mkdir -p $HOME_DOTCONFIG

            for item in "$PORTABLE_DOTCONFIG"/*; do
                item_name=$(basename "$item")
                destination="$HOME_DOTCONFIG/$item_name"

                ln -sf "$item" "$destination"
                echo "  Linked $item -> $destination"
            done

        # --- 3. Link contents of Library directory (macOS) ---
        if [ "$(uname -s)" = "Darwin" ]; then
            PORTABLE_LIBRARY="$DEV_SPEC/Library"
            HOME_LIBRARY="$HOME/Library"

            if [ -d "$PORTABLE_LIBRARY" ]; then
                echo "Linking contents of Library..."
                mkdir -p "$HOME_LIBRARY"

                for item in "$PORTABLE_LIBRARY"/*; do
                    item_name=$(basename "$item")
                    destination="$HOME_LIBRARY/$item_name"

                    mkdir -p "$(dirname "$destination")"
                    ln -sf "$item" "$destination"
                    echo "  Linked $item -> $destination"
                done
            fi
        fi

        # --- 4. Link contents of fns directory ---
        PORTABLE_DOTFUNS="$DEV_SPEC/.funs"
        HOME_DOTFUNS="$HOME/.funs"

        if [ -d "$PORTABLE_DOTFUNS" ]; then
            echo "Linking contents of fns to ~/.fns..."
            mkdir -p "$HOME_DOTFUNS"

            for item in "$PORTABLE_DOTFUNS"/*; do
                item_name=$(basename "$item")
                destination="$HOME_DOTFUNS/$item_name"

                ln -sf "$item" "$destination"
                echo "  Linked $item -> $destination"
            done
        fi

        echo "Symlinking complete."
        ;;
esac
