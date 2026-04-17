# Repository Guidelines

## Project Structure & Module Organization

This repository is a personal machine bootstrap and dotfiles kit.

- `instantiate` is the main bootstrap script. It symlinks dotfiles, detects the OS/package manager, installs tool dependencies, and runs tool config hooks.
- `symlinks` links files from `home/` into `$HOME` using non-destructive defaults.
- `configure` runs `config` hooks from `machine-tools/*.sh`.
- `machine-tools/` contains one shell script per installable tool. Each script should support `install` and optionally `config` or `self-install`.
- `home/` contains dotfiles and application config payloads that are linked into a user home directory.
- `tests/` contains the dependency-free shell test harness and script-specific tests.

## Build, Test, and Development Commands

- `tests/run` runs the full test suite.
- `bash -n symlinks instantiate configure machine-tools/*.sh` performs shell syntax checks.
- `bash ./configure <tool>` runs config for one tool, for example `bash ./configure git`.
- `bash ./instantiate` bootstraps the current machine. Treat this as side-effectful: it can install packages and modify home-directory config.

## Coding Style & Naming Conventions

Use Bash for repository scripts. Prefer `#!/usr/bin/env bash`, quote variable expansions, and use arrays for command argument construction. Keep indentation at two spaces, matching the existing scripts. Tool scripts should be named after the command or capability they manage, for example `machine-tools/ripgrep.sh` or `machine-tools/tmux-sessionizer.sh`.

Keep install declarations machine-readable: emit tokens such as `syspkgmgr:jq`, `uv:ruff`, `npm:tree-sitter-cli`, or `self-install` from `install` cases.

## Testing Guidelines

The test system is intentionally dependency-free. Add new tests as `tests/<script>_test.bash` and register cases with `test_case`. Tests should run scripts as black boxes, isolate `$HOME` with temp directories, and assert observable filesystem behavior. Passing tests should stay quiet except for `ok` lines; failure output should include captured diagnostics.

Run `tests/run` before changing bootstrap behavior.

## Commit & Pull Request Guidelines

There is no strict commit format in the current history. Prefer concise, imperative subjects, optionally scoped: `symlinks: preserve local config`, `fix: handle missing nvm`, or `tmux: update keybind`.

For pull requests, describe the machine/setup behavior changed, note any side effects, and include test output. If a change affects `instantiate`, mention the OS/package managers tested.

## Security & Configuration Tips

Do not commit secrets, tokens, private SSH material, or work-specific credentials. Machine env files under `home/.*.env` may contain personal paths and safe defaults, but secrets should live outside the repository.
