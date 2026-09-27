# Zsh plugins

Oh My Zsh supplies its built-in `git` and `colored-man-pages` plugins.  The
third-party plugins are installed independently: Homebrew on macOS, and pinned
Git checkouts below `${XDG_DATA_HOME:-$HOME/.local/share}/portables/zsh` on
Linux. `zsh-autocomplete` remains managed by `machine-tools/zsh-autocomplete.sh`.

After running `./instantiate` and starting a new interactive shell, verify that
your prompt, suggestions, and completion menu work. Old Oh My Zsh custom
checkouts are deliberately not removed. Once the new shell is working, they can
be deleted manually:

```sh
rm -rf ~/.oh-my-zsh/custom/plugins/zsh-autocomplete \
  ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions \
  ~/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting \
  ~/.oh-my-zsh/custom/plugins/zsh-completions \
  ~/.oh-my-zsh/custom/themes/powerlevel10k
```
