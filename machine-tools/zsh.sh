#!/usr/bin/env bash

LOG_NAME="${LOG_NAME:+$LOG_NAME.}zsh:$1"
functions log >/dev/null 2>&1 || . "$PORTABLES"/log

# Installs Zsh and its configurations.

case "$1" in
  install)
    if ! command -v zsh >/dev/null 2>&1; then
      echo syspkgmgr:zsh
    fi
    ;;
  config)
    # Install Oh My Zsh if it's not already installed
    if [ ! -d "$HOME/.oh-my-zsh" ]; then
      log "installing Oh My Zsh…"
      sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    fi

        # Define the custom directory for OMZ plugins and themes
        ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

        # zsh-syntax-highlighting
        ZSH_SYNTAX_HIGHLIGHT_DIR="$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
        if [ -d "$ZSH_SYNTAX_HIGHLIGHT_DIR" ]; then
          log "updating zsh-syntax-highlighting"
          git -C "$ZSH_SYNTAX_HIGHLIGHT_DIR" pull
          log "complete"
        else
          log "installing zsh-syntax-highlighting"
          git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting.git "$ZSH_SYNTAX_HIGHLIGHT_DIR"
          log "complete"
        fi

        # zsh-completions
        ZSH_COMPLETIONS_DIR="$ZSH_CUSTOM/plugins/zsh-completions"
        if [ -d "$ZSH_COMPLETIONS_DIR" ]; then
          log "updating zsh-completions"
          git -C "$ZSH_COMPLETIONS_DIR" pull
          log "complete"
        else
          log "installing zsh-completions"
          git clone --depth=1 https://github.com/zsh-users/zsh-completions.git "$ZSH_COMPLETIONS_DIR"
          log "complete"
        fi

        # zsh-autosuggestions
        ZSH_AUTOSUGGEST_DIR="$ZSH_CUSTOM/plugins/zsh-autosuggestions"
        if [ -d "$ZSH_AUTOSUGGEST_DIR" ]; then
          log "updating zsh-autosuggestions"
          git -C "$ZSH_AUTOSUGGEST_DIR" pull
          log "complete"
        else
          log "installing zsh-autosuggestions"
          git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions.git "$ZSH_AUTOSUGGEST_DIR"
          log "complete"
        fi

        # zsh-autocomplete
        ZSH_AUTOCOMPLETE_DIR="$ZSH_CUSTOM/plugins/zsh-autocomplete"
        if [ -d "$ZSH_AUTOCOMPLETE_DIR" ]; then
          log "updating zsh-autocomplete"
          git -C "$ZSH_AUTOCOMPLETE_DIR" pull
          log "complete"
        else
          log "installing zsh-autocomplete"
          git clone --depth=1 https://github.com/marlonrichert/zsh-autocomplete.git "$ZSH_AUTOCOMPLETE_DIR"
          log "complete"
        fi

        # Powerlevel10k theme
        P10K_DIR="$ZSH_CUSTOM/themes/powerlevel10k"
        if [ -d "$P10K_DIR" ]; then
          log "updating powerlevel10k"
          git -C "$P10K_DIR" pull
          log "complete"
        else
          log "installing powerlevel10k"
          git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$P10K_DIR"
          log "complete"
        fi
        ;;
    esac
