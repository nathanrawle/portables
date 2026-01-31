#!/bin/sh

# This script creates symlinks from the dotfiles into the home directory.
# It is the final step in the configuration pass.

case "$1" in
    deps)
        # Symlinking has no system package dependencies.
        ;;
    config)
        HERE="$(cd -- "$(dirname -- "$0")" >/dev/null 2>&1 && pwd)"
        DEV_SPEC_DIR="$(cd -- "$HERE/../" >/dev/null 2>&1 && pwd)"
        HOME_DIR="$HOME"

        echo "Creating symlinks..."

        # --- 1. Link top-level dotfiles ---
        toplevel_files=".zshrc .zprofile .editorconfig .inputrc"

        echo "Linking top-level dotfiles..."
        for file in $toplevel_files; do
            source="$DEV_SPEC_DIR/$file"
            destination="$HOME_DIR/$file"
            
            if [ -e "$source" ]; then
                ln -sf "$source" "$destination"
                echo "  Linked $source -> $destination"
            fi
        done

        # --- 2. Link contents of .config directory ---
        CONFIG_SOURCE_DIR="$DEV_SPEC_DIR/.config"
        CONFIG_DEST_DIR="$HOME_DIR/.config"

        if [ -d "$CONFIG_SOURCE_DIR" ]; then
            echo "Linking contents of .config..."
            mkdir -p "$CONFIG_DEST_DIR"
            
            for item in "$CONFIG_SOURCE_DIR"/*; do
                item_name=$(basename "$item")
                source="$item"
                destination="$CONFIG_DEST_DIR/$item_name"
                
                ln -sf "$source" "$destination"
                echo "  Linked $source -> $destination"
            done
        fi

        # --- 3. Link contents of Library directory (macOS) ---
        if [ "$(uname -s)" = "Darwin" ]; then
            LIBRARY_SOURCE_DIR="$DEV_SPEC_DIR/Library"
            LIBRARY_DEST_DIR="$HOME_DIR/Library"

            if [ -d "$LIBRARY_SOURCE_DIR" ]; then
                echo "Linking contents of Library..."
                mkdir -p "$LIBRARY_DEST_DIR"

                for item in "$LIBRARY_SOURCE_DIR"/*; do
                    item_name=$(basename "$item")
                    source="$item"
                    destination="$LIBRARY_DEST_DIR/$item_name"
                    
                    mkdir -p "$(dirname "$destination")"
                    ln -sf "$source" "$destination"
                    echo "  Linked $source -> $destination"
                done
            fi
        fi

        # --- 4. Link contents of fns directory ---
        FNS_SOURCE_DIR="$DEV_SPEC_DIR/fns"
        FNS_DEST_DIR="$HOME_DIR/.fns"

        if [ -d "$FNS_SOURCE_DIR" ]; then
            echo "Linking contents of fns to ~/.fns..."
            mkdir -p "$FNS_DEST_DIR"

            for item in "$FNS_SOURCE_DIR"/*; do
                item_name=$(basename "$item")
                source="$item"
                destination="$FNS_DEST_DIR/$item_name"
                
                ln -sf "$source" "$destination"
                echo "  Linked $source -> $destination"
            done
        fi

        # --- 5. Configure global git excludesfile ---
        echo "Configuring global git excludesfile..."
        # We remove all first to prevent duplicates, then add the one we want.
        git config --global --unset-all core.excludesfile || true # Ignore error if not set
        git config --global --add core.excludesfile "$CONFIG_DEST_DIR/git/ignore"

        echo "Symlinking complete."
        ;;
esac
