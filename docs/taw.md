# `taw`

Reference for the `taw` zsh function.

## Invocation

```text
taw [options] [project] [operand ...]
```

`--` stops option parsing; the remaining arguments become positionals.

Relevant options:

- `-p`, `-proj`, `-prj`, `-r`, `-repo`, `-repository`
- `-b`, `-branch`
- `-agent`
- `-ed`, `-editor`
- `-sh`, `-shell`
- `--peer`
- `--force` (peer only)
- `--convert`
- `--mode=<ts|session|wt|worktree|b|branch>`
- project picker aliases: `-ts`, `--ts`, `-picker`, `--picker`, `-pick-project`, `--pick-project`

## Project Kinds

- `normal`: a standard git repository with a working tree at the project root.
- `bare`: a bare git repository that manages worktrees under the project root.
- `plain`: a non-git directory that opens directly.

## Project Resolution

For a `-p` value or other project argument, resolution is attempted in this order:

1. URL
2. Existing literal path
3. Simple name under `PROJECTS_HOME`
4. tmux session match
5. Creation prompt

tmux lookup checks session name first, then session path basename.

If no project is supplied and `taw` is not already inside a project:

- zero positionals prompts for a project, URL, or repository directory
- an empty prompt opens the project picker
- `-b` is rejected outside a project
- one positional outside a project is treated as `-p`
- two positionals outside a project are treated as `project + operand`

## Context-Sensitive Shorthand

- In peer mode, the first positional always identifies the project; a
  second positional is that project's worktree or branch.
- Peer with no positionals still detects the current project.
- Inside a `normal` project, one positional and no `-b` acts like `-b <branch>`.
- Outside a project, one positional acts like `-p <project>`.
- Outside a project, two positionals mean `project` plus one operand.
- Outside a project, `-b` is rejected.

## Picker Modes

Explicit picker modes:

- `--mode=ts` and `--mode=session` open the session picker
- `--mode=wt` and `--mode=worktree` open the worktree picker
- `--mode=b` and `--mode=branch` open the branch picker
- `--mode value` and `--mode=value` are equivalent
- project picker aliases open the session picker
- Tab cycles `session -> worktree -> branch -> session` from every explicit mode
- the fzf query is preserved while cycling

The session picker keeps the existing tmux-sessionizer scope: it lists tmux
sessions and projects found under the configured search paths. Worktree and
branch modes use the Git project containing the directory where `taw` was
invoked. They fail without opening a tmux window when there is no current Git
project.

Worktree rows include every non-bare entry from `git worktree list`, including
detached worktrees. Selecting one opens its registered path without changing
Git state. Branch rows include local and deduplicated remote branches, even
when a branch already has a worktree. Selecting an assigned branch opens that
worktree directly. Otherwise, normal repositories use their existing checkout
behavior and bare repositories create or open the branch's canonical worktree.

Explicit picker invocations:

- reject `-p`, `-b`, and positionals
- allow `-agent`, `-ed`, and `-sh`
- session mode bypasses current-project target selection
- ignore `TAW_AGENT`
- create an agent only when `-agent` is given explicitly

Session picker result handling:

- `[TMUX]` rows switch or attach directly by tmux session identity, preserving the session's active window
- with `--peer`, a `[TMUX]` row links that active window into the invoking session and selects it there
- layout options apply to project rows; `[TMUX]` rows do not create layouts
- `normal` and `plain` projects open directly
- `bare` projects open their default worktree directly

Picker return behavior:

- `0`: selection resolved
- `130`: user cancelled
- `2`: picker unavailable or had no rows
- any other nonzero status: failure

## Invocation Matrix

### `normal`

| Inputs | Result |
| --- | --- |
| zero operands, no `-b` | branch picker; if `fzf` is missing or returns no rows, open the repo unchanged |
| zero operands, `-b` | checkout or open that branch |
| one positional, no `-b` | checkout or open that branch |
| one positional, `-b` | reject |
| two positionals | reject |

### `bare`

| Inputs | Result |
| --- | --- |
| zero operands, no `-b` | if there are no non-bare worktrees, open the default worktree; otherwise use the picker when available, falling back to the default worktree when it is not |
| zero operands, `-b` | create or open a branch worktree under the project root |
| one positional, no `-b` | treat it as a worktree path under the project root; the branch name is the same relative path |
| two positionals, no `-b` | treat them as worktree path plus base ref |
| any positional with `-b` | reject |
| explicit bare worktree path with `-b` | resolve the project root from the path and open the branch worktree under the root |

If a bare project is already resolved from an existing worktree path, `taw` opens that worktree directly when no branch target is requested.
Bare worktree path operands reject `.` and `..` segments; absolute path operands must resolve under the project root.

### `plain`

| Inputs | Result |
| --- | --- |
| any accepted project path | open the directory directly |
| `-b` or any positional operand | reject |

## Branch Resolution

Branch resolution follows this order:

1. Reject `refs/remotes/*`.
2. Exact local branch match wins.
3. If the input contains `/`, try the longest configured remote-name prefix first.
4. Otherwise search remotes in this order: `origin`, then the remaining remotes sorted by name.
5. If only a remote ref exists, create a local tracking branch/worktree.

Picker dedupe rules:

- local branch rows suppress matching remote rows
- `origin` wins over other remotes for the same branch name

## Bare Default Worktree

When a bare project needs a default worktree and no explicit branch/worktree target was given, `taw` probes in this order:

1. `HEAD` when it resolves to a local branch or commit-backed local branch
2. `origin/HEAD`
3. local `main`
4. local `master`

If none of those resolve:

- when refs exist, `taw` fails before any worktree mutation
- when no refs exist, `taw` falls back to an orphan worktree named from the bare repository's symbolic `HEAD`

## Creation Flow

Creation is reached only after normal resolution fails. The flow is:

1. Try URL clone or existing path/session resolution first.
2. Refuse existing files and broken symlinks before any creation prompt.
3. For a simple name, prefer `PROJECTS_HOME/name` when `PROJECTS_HOME` is set.
4. If resolution still fails, prompt to create the project.
5. Choose one of `plain`, `repo`, or `bare`.

Validation happens before mutation:

- refusing creation returns nonzero and leaves the filesystem unchanged
- `plain` rejects operands and only creates a directory
- `repo` without a branch uses git's default branch; it accepts at most one branch operand, validates the branch name, then runs `git init`
- `bare` accepts at most one pending worktree input, validates the path and branch name before creating the bare repo, then creates an orphan worktree

URL clone failures stop the flow; they do not fall through to the create prompt.

## Conversion

```text
taw --convert <project>
```

Conversion is an action-only mode. It converts an existing `normal` project
to taw's `bare` layout, prints the resulting worktree paths, and exits without
creating or selecting a tmux window. The project is resolved from an existing
literal path, a simple name under `PROJECTS_HOME`, or a tmux session. URLs,
missing projects, plain projects, and projects that are already bare are
rejected without prompting.

The default branch is selected in this order:

1. `origin/HEAD`
2. local `main`
3. local `master`
4. the currently checked-out branch

If `origin/HEAD` only has a remote branch, conversion creates a local tracking
branch for it. When the current branch is the default branch, conversion
creates one worktree under `<project>/<branch>`. Otherwise it creates a clean
default-branch worktree and a second worktree for the current branch. The bare
repository remains at `<project>/.git`, and its symbolic `HEAD` names the
selected default branch.

Conversion preserves the original index and moves the working tree rather
than copying or checking it out again. Staged, unstaged, untracked, and ignored
files therefore move to the current-branch worktree without losing their Git
status. Repositories with no commits are supported with a single orphan
worktree.

Conversion validates the repository before moving files. It rejects detached
HEAD, active Git operations or unmerged entries, Git lock files, linked
worktrees, initialized submodules, sparse or split indexes, worktree-specific
config, external Git directories, and branch worktree paths that overlap.
Failures after mutation starts trigger rollback to the original normal
repository. If rollback cannot finish, taw reports the private recovery
directory and leaves it in place.

`--convert` accepts `--debug` but cannot be combined with project, branch,
picker, peer, agent, editor, or shell options. If the invoking shell is inside
the converted project, taw changes it to the equivalent relative directory in
the current-branch worktree.

## `TAW_AGENT`

- Non-empty trimmed `TAW_AGENT` replaces the default `codex` agent when no explicit `-agent` is supplied.
- unset, empty, or whitespace-only values are ignored.
- explicit `-agent` always wins over the environment.
- picker mode ignores `TAW_AGENT`; only an explicit `-agent` changes the agent command there.

## tmux Reuse And Layout

Reuse is limited to sessions where no explicit `-agent`, `-ed`, or `-sh` arguments were supplied and `TAW_AGENT` trims to empty. A non-empty trimmed `TAW_AGENT` disables reuse.

Layout on a new window:

- editor pane is created first
- with an agent: editor on the left, agent on the right
- with an agent and shells: the first shell goes below the agent, later shells split to the right
- without an agent and with shells: the first shell goes to the right of the editor, later shells split to the right

## Peer Mode

`--peer` preserves normal project, branch, and worktree resolution, but puts
the result in the invoking tmux session instead of switching or attaching to
the project's session. Peer must be invoked from an active tmux client.

Existing windows are searched in this order:

1. the invoking session
2. the project's normal target session
3. other sessions in the tmux server

Within each group, an exact target-directory pane is preferred over a pane in
a descendant directory. A match in the invoking session is selected directly.
A match in another session is added to the invoking session with
`link-window`. If there is no match, taw creates its normal layout directly in
the invoking session.

When a `[TMUX]` project-picker row is selected, peer mode links that session's
active window into the invoking session and selects it there.

An existing match conflicts with an explicit `-agent`, `-ed`, or `-sh`, or
with a non-empty `TAW_AGENT`. Use `--force` to skip all reuse and create a
fresh layout. `--force` is rejected without peer mode.

A linked tmux window shares its panes, processes, name, and lifetime between
sessions. `unlink-window` removes it from one session; `kill-window` removes
it from every session to which it is linked.

## Examples

```bash
taw -p ~/src/repo
taw -p ~/src/repo feature/foo
taw -p ~/src/bare feature/foo develop
taw --convert ~/src/repo
taw --peer sheffield-live hallamshire-hotel-all-day
taw --peer --force -p ~/src/repo -agent "claude --resume"
taw --pick-project -agent "claude --resume" -ed "nvim ." -sh "npm test"
taw --mode=wt
taw --mode=branch
```
