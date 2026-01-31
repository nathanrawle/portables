#!/bin/sh

# Installs Zsh and its configurations.

case "$1" in
    deps)
        echo "zsh"
        echo "git"
        echo "curl"
        ;;
    config)
        # Install Oh My Zsh if it's not already installed
        if [ ! -d "$HOME/.oh-my-zsh" ]; then
            echo "Installing Oh My Zsh..."
            # The installer will back up an existing .zshrc, which we want.
            sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
        else
            echo "Oh My Zsh already installed."
        fi

        # Define the custom directory for OMZ plugins and themes
        ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

        # Install/update OMZ plugins
        echo "Installing/updating Oh My Zsh plugins..."
        
        # zsh-syntax-highlighting
        ZSH_SYNTAX_HIGHLIGHT_DIR="$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
        if [ -d "$ZSH_SYNTAX_HIGHLIGHT_DIR" ]; then
            git -C "$ZSH_SYNTAX_HIGHLIGHT_DIR" pull
        else
            git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting.git "$ZSH_SYNTAX_HIGHLIGHT_DIR"
        fi

        # zsh-completions
        ZSH_COMPLETIONS_DIR="$ZSH_CUSTOM/plugins/zsh-completions"
        if [ -d "$ZSH_COMPLETIONS_DIR" ]; then
            git -C "$ZSH_COMPLETIONS_DIR" pull
        else
            git clone --depth=1 https://github.com/zsh-users/zsh-completions.git "$ZSH_COMPLETIONS_DIR"
        fi

        # zsh-autosuggestions
        ZSH_AUTOSUGGEST_DIR="$ZSH_CUSTOM/plugins/zsh-autosuggestions"
        if [ -d "$ZSH_AUTOSUGGEST_DIR" ]; then
            git -C "$ZSH_AUTOSUGGEST_DIR" pull
        else
            git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions.git "$ZSH_AUTOSUGGEST_DIR"
        fi

        # zsh-autocomplete
        ZSH_AUTOCOMPLETE_DIR="$ZSH_CUSTOM/plugins/zsh-autocomplete"
        if [ -d "$ZSH_AUTOCOMPLETE_DIR" ]; then
            git -C "$ZSH_AUTOCOMPLETE_DIR" pull
        else
            git clone --depth=1 https://github.com/marlon-richert/zsh-autocomplete.git "$ZSH_AUTOCOMPLETE_DIR"
        fi

        # Powerlevel10k theme
        P10K_DIR="$ZSH_CUSTOM/themes/powerlevel10k"
        if [ -d "$P10K_DIR" ]; then
            git -C "$P10K_DIR" pull
        else
            git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$P10K_DIR"
        fi
        ;;
esac
