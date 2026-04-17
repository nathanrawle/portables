# Portables

Portable machine setup for dotfiles, shell tooling, editor config, and developer utilities.

This repository is designed to make a new machine feel familiar quickly: link the config in `home/`, install the expected tools, and run each tool's setup hooks. It is primarily a personal workstation bootstrap kit, with macOS as the most complete target and partial Linux support.

## What Is In Here?

- `instantiate` bootstraps a machine end to end: symlinks home files, detects the OS/package manager, installs tools, and runs config hooks.
- `symlinks` links the `home/` payload into `$HOME` using file-by-file, non-destructive defaults.
- `configure` runs `config` hooks from `machine-tools/*.sh`.
- `machine-tools/` contains one script per tool or capability, such as `git`, `zsh`, `uv`, `tmux`, `neovim`, and `ripgrep`.
- `home/` contains dotfiles, shell config, app config, Neovim config, tmux config, Git config, and machine-specific env files.
- `tests/` contains the dependency-free shell test harness and symlink tests.
- `AGENTS.md` contains contributor guidance for humans and coding agents.

## Quick Start

Clone the repo where you want it to live, then run:

```bash
bash ./instantiate
```

This is intentionally side-effectful. It may install packages, update shell tooling, create or update machine env files, and link files into your home directory.

For a safer first look, run only the symlink step against the current machine:

```bash
bash ./symlinks
```

By default, existing files are preserved and skipped. To change conflict behavior:

```bash
LINK_CONFLICT_MODE=backup bash ./symlinks
LINK_CONFLICT_MODE=force bash ./symlinks .config/nvim
```

## Common Commands

```bash
tests/run
```

Runs the full test suite.

```bash
bash -n symlinks instantiate configure machine-tools/*.sh
```

Performs basic shell syntax checks.

```bash
bash ./configure git
```

Runs the `config` hook for a single tool.

```bash
bash ./configure
```

Runs all available tool config hooks.

## How Tool Installation Works

Each script in `machine-tools/` can emit install tokens from its `install` case. `instantiate` collects those tokens, groups them by installer, installs dependencies, then calls each relevant script's `config` case.

Examples:

- `syspkgmgr:jq` installs with the detected system package manager.
- `uv:ruff` installs a Python tool with `uv`.
- `npm:tree-sitter-cli` installs a global npm package.
- `nvm:--lts` installs an LTS Node version through `nvm`.
- `self-install` asks the tool script to handle its own installation.

## Dotfiles And Symlinks

The `home/` directory mirrors paths under `$HOME`. For example:

- `home/.zshrc` links to `~/.zshrc`
- `home/.config/nvim/init.lua` links to `~/.config/nvim/init.lua`
- `home/.zfuns/relink` links to `~/.zfuns/relink`

Directories are traversed file by file, so local-only files in existing config directories are preserved. On non-Darwin systems, `home/Library/` is excluded from the default root symlink pass.

## Machine-Specific Configuration

On startup, `home/.zshrc` loads a machine env file based on the host name, such as:

```text
home/.m1pro.env
home/.work-m2-pro.env
```

`instantiate` creates or updates the current machine's env file with `PORTABLES=<repo path>`. Keep secrets out of these files.

## Testing

Run:

```bash
tests/run
```

The test harness is dependency-free and uses temporary homes so tests do not touch your real `$HOME`. Passing tests print compact `ok` lines; failing tests include captured script output and assertion diagnostics.

Add new tests as:

```text
tests/<script>_test.bash
```

Register each case with `test_case` from `tests/lib/harness.bash`.

## Safety Notes

- Treat `instantiate` as a real machine mutation command.
- Prefer testing changes with `tests/run` before running bootstrap scripts.
- Do not commit secrets, private keys, tokens, or machine-local credentials.
- Be careful with `LINK_CONFLICT_MODE=force`; it intentionally replaces existing paths.

## Contributing

Keep changes small and practical. For tool scripts, preserve the `install` / `config` shape so `instantiate` can continue to orchestrate them. For behavior changes, add or update tests in `tests/`.

See `AGENTS.md` for contributor conventions and coding-agent guidance.
