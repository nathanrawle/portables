# Portables

Personal machine setup for dotfiles, shell tooling, editor configuration, and developer utilities.
macOS is the primary target; Debian, Ubuntu/Pop, Arch, and Fedora have package-manager support.
The bootstrap scripts run with Bash 3.2 or newer and use no additional orchestration dependency.
Git 2.30 or newer is required. Upgrade Git separately on distributions whose standard package
repositories provide an older version; maintenance does not add third-party package sources.

## Maintenance commands

| Script | Interactive Zsh function | Work performed |
| --- | --- | --- |
| `bash ./symlinks [paths…]` | `relink [paths…]` | Link the selected home payload, or all of it. |
| `bash ./configure [tools…]` | `retune [tools…]` | Configure selected tools, or every tool. The function also relinks afterward. |
| `bash ./instantiate` | `reinstantiate` | Complete installation and configuration, then relink generated files. |

The functions are autoloaded by Zsh from `home/.zfuns`. They belong in the current
shell; do not run them with Bash. After successful interactive maintenance they offer
to replace the shell: y/Y accepts, while Enter/n/N declines. A valid executable `$SHELL`
is preferred, with the current Zsh command as fallback for malformed login-shell values.
Failed runs, EOF, help, and noninteractive invocations do not replace the shell. Their
temporary variables and logging context do not leak into the caller.

Examples:

```bash
bash ./instantiate
bash ./configure git gcm
bash ./symlinks .config/nvim
bash ./symlinks --help
```

Installation is side-effectful: it can install packages and toolchains, clone missing
shell frameworks/plugins, create machine configuration, and change home-directory links.
Tests never run a real bootstrap.

### Completion and failure

Maintenance completes missing setup. It does not deliberately upgrade installed system
packages, uv itself, existing shell plugins, or already-satisfied Python requirements.
Dependency solvers may still change versions to satisfy an explicit requirement.
Existing Node/Python requests are reused when a matching local installation exists.

Exit statuses:

- **0:** completed, including intentional skips of existing files or ignored payload.
- **1:** an operation failed or dependent work was blocked.
- **2:** invalid command arguments.

Arguments are checked before work starts. Independent tools and links continue after
operational failures; the final summary lists failed and blocked steps. Configuration is
skipped for a tool whose installation requirements failed. A failed initial link pass
does not prevent independent installations; configuration hooks check their own required
commands and files. `retune` and `instantiate` still attempt their final relink after
operational failures, but return failure and do not offer a shell restart.

## Bootstrap sequence

1. Detect platform context and create/update the current machine's environment file.
2. Establish home links.
3. Prepare the package manager, refresh metadata, and ensure curl and Git 2.30+ are available.
4. Collect and validate all tool requirements.
5. Install missing system packages in package-manager batches and self-installed providers, then Node, managed Python,
   uv tools, pip, pipx, and npm requirements.
6. Configure every eligible tool once, including tools that were already installed.
7. Relink generated files and report the overall result.

macOS needs completed Xcode command-line tools installation. If missing, the script
reports `xcode-select --install` as a prerequisite rather than continuing as though
the asynchronous installer had finished. Both standard Homebrew locations are on PATH.

Arch uses its existing package database and `pacman -S --needed`; maintenance does
not run a standalone database refresh or full system upgrade. If the database is stale,
complete normal Arch system maintenance before retrying. DNF's status 100 for
available updates is not treated as an error.

## Tool-hook contract

`machine-tools/*.sh` are standalone Bash hooks. They initialize context from the
repository's shared `lib/maintenance.bash`; callers need not export `PORTABLES` or
source their shell configuration.

Each hook accepts exactly one action:

- `install`: inspect requirements and emit one token per line on stdout. Emit nothing
  and return zero when no installation is needed.
- `self-install`: perform the hook's standalone installation, if any.
- `config`: complete configuration, if any. An absent optional action is a successful no-op.
- `--help`: print usage without making changes.

Diagnostics go to stderr. Failed operations return nonzero. Hooks check prerequisites
before modifying dependent configuration, preserve local files, and do not update
existing plugin checkouts. Unsupported actions return 2.

| Token | Meaning |
| --- | --- |
| `syspkgmgr:jq` | Ensure a system package is installed. |
| `syspkgmgr:cask:git-credential-manager` | Install a macOS Homebrew cask. |
| `self-install` | Invoke this hook's standalone installer. |
| `uv:ruff` | Ensure a uv-managed tool. |
| `uv:python:3.12` | Ensure a managed Python matching the request. |
| `nvm:--lts` | Ensure a local Node installation matching the request. |
| `pip:example` | Install through `python3 -m pip install --user`. |
| `pipx:example` | Ensure one pipx application. |
| `npm:example` | Ensure a global npm package using nvm. |

Tokens contain no whitespace and are passed as arguments, never evaluated as shell
commands. Managed-Python options may be separated by colons, as in the existing
`uv:python:--default:--preview-features:python-install-default` declaration.
Identical requirements are deduplicated; multiple toolchain requests are handled
separately. The obsolete `syspkgmgr:ext:` encoding and unknown backends fail validation.
Pip/pipx remain supported extension points even though no current hook requests them.
Pip does not upgrade itself or bypass externally managed Python protections.
System requirements retain their owning hooks while formulas, casks, or distribution
packages are passed to the package manager in the smallest appropriate batches. If a
batch fails, only packages still missing are retried individually so one unavailable
package does not block otherwise satisfiable tools.

`OS`, `ID`, and `VERSION_ID` may be supplied for controlled environments/tests.
Otherwise the scripts detect them from the platform. Repository paths always come from
the running checkout. User-local binary directories are available to child hooks.

## Dotfiles and symlinks

`home/` mirrors paths under `$HOME`. Files are linked individually into real
destination directories, preserving local-only files. Internal source-directory aliases,
such as shared skills, are traversed without replacing destination directories.

```bash
LINK_CONFLICT_MODE=backup bash ./symlinks
bash ./symlinks --force .config/nvim
bash ./symlinks --no-ignore .config/nvim
```

The default conflict mode is `skip`. `backup` preserves the old path under a unique
`.bak.*` name; `force` replaces it. A destination already referring to the source,
including through a directory alias, is considered satisfied. Operations through
destination aliases must not modify repository source files.

Git ignore rules, including negations, are applied when Git and repository metadata
are available. `.DS_Store` is always ignored unless `--no-ignore` is specified.
Non-Darwin root passes omit `Library/`; explicit selections can still link it.
Paths must stay within the home payload. Source-directory loops or escapes, blocked
destination parents, and filesystem errors return failure while independent links continue.

## Machine-specific and Git configuration

The hostname selects the canonical `home/.<lowercase-host>.env` regular file. Bootstrap
preserves its other settings and permissions, writes a shell-quoted `PORTABLES` assignment,
loads it, and requires `$HOME/.<lowercase-host>.env` to link back to that repository source.
A conflicting home file is preserved but makes maintenance fail. Keep secrets outside the
repository.

The tracked XDG Git configuration contains shared defaults, the Azure DevOps credential
path policy, and generated files from the same directory. `~/.gitconfig` is the writable
machine-specific overlay for identity, signing, and organization settings; missing identity
values are written there. Hooks refuse to write through its symlink or into the repository.
An existing `local.conf` remains included for compatibility, but receives no new settings.
Git's standard XDG user ignore file is used instead of hardcoded machine paths.

The `gcm` hook owns OS-specific credential defaults:

- macOS: `manager`, then `osxkeychain` as a fallback.
- Linux: `cache --timeout 21600`, then `oauth`.

It writes a marked `portables-credentials.conf` under
`${XDG_CONFIG_HOME:-$HOME/.config}/git`; the tracked config includes that relative path.
When `gh` is installed, GitHub and Gist use its absolute `auth git-credential` helper
before the OS-specific fallbacks. The `gh` hook installs the GitHub CLI through the system
package manager.
When `GIT_CONFIG_GLOBAL` explicitly selects another file, the hook adds an idempotent
include there instead. Generated files stay outside the tracked payload. Custom generic
helpers cause managed defaults to be omitted; custom host-specific sections remain unchanged.

Known root-level settings formerly generated by these tools are migrated into the managed
fragment with a `.bak.*` backup: the old helper defaults, the redundant XDG ignore pair,
the duplicate managed include, and `gh auth setup-git` helper pairs. Other machine-specific
settings are preserved. No credentials are read, stored, or requested by this step.

The Zsh hook links `zcp` and `zln` directly to the current `zmv`. It repairs links through
the former repository intermediaries and broken links to versioned Zsh `zmv` locations,
while preserving custom destinations and rejecting unrelated broken links.

## Repository layout and validation

- `instantiate`, `configure`, `symlinks`: maintenance entry points.
- `lib/`: shared Bash runtime.
- `machine-tools/`: tool requirements and configuration hooks.
- `home/`: linked dotfiles and application configuration.
- `tests/`: dependency-free shell harness and isolated fixtures.

```bash
bash tests/run
bash tests/run tests/maintenance_test.bash tests/symlinks_test.bash
bash -n instantiate configure symlinks lib/*.bash machine-tools/*.sh
zsh -n home/.zfuns/relink home/.zfuns/retune home/.zfuns/reinstantiate
```

Tests use temporary homes, fake installers, and isolated Git configuration. Linux
dispatch tests simulate the supported distributions; they do not establish that real
package installation was tested on every OS. Real tmux tests require permission to
create temporary tmux servers.

For the worktree functions, see [taw](docs/taw.md) and
[taw-convert](docs/taw-convert.md). Contributor conventions are in [AGENTS.md](AGENTS.md).
