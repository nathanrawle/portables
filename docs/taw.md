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

- `normal`: a standard git repository with its primary working tree at the
  project root and linked worktrees under `<project>/.worktrees`.
- `bare`: a legacy or explicitly requested bare repository. New linked
  worktrees are created under the wrapper's `.worktrees` directory.
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
- Inside a git project, one positional names a managed worktree and its branch.
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
invoked. Outside a Git project, those modes show `Not in a Git project` instead
of exiting. A mode with no discovered targets shows `Picker has no targets`.
These informational rows cannot be selected, and Tab can still cycle to the
other modes.

Worktree rows include every non-bare entry from `git worktree list`, including
detached worktrees. Selecting one opens its registered path without changing
Git state. Branch rows include local and deduplicated remote branches, even
when a branch already has a worktree. Selecting an assigned branch opens that
worktree directly. Selecting an unassigned branch creates its canonical
`.worktrees/<branch>` worktree without changing the primary checkout.

Explicit picker invocations:

- reject `-p`, `-b`, and positionals
- allow `-agent`, `-ed`, and `-sh`
- session mode bypasses current-project target selection

Acceptance keys choose the layout for a newly created target:

| Key | Layout |
| --- | --- |
| Enter | default layout; editor only when no explicit layout options were supplied |
| Ctrl-S | shell only |
| Ctrl-A | agent only |
| Opt-Z | editor and shell |
| Opt-A | editor and agent |
| Opt-Enter | editor, agent, and shell |

An explicit `-agent` supplies the agent command. Otherwise, an agent-containing
acceptance layout uses trimmed `TAW_AGENT` when set and falls back to `codex`.
Plain Enter does not enable an agent from `TAW_AGENT`. Acceptance modifiers are
ignored for a selected `[TMUX]` session or an exact matching worktree window.

Session picker result handling:

- `[TMUX]` rows switch or attach directly by tmux session identity, preserving the session's active window
- with `--peer`, a `[TMUX]` row links that active window into the invoking session and selects it there
- layout options and acceptance modifiers apply to project rows; `[TMUX]` rows do not create layouts
- `normal` and `plain` projects open directly
- `bare` projects open their default worktree directly

Each mode is generated once into a per-invocation snapshot and reused while
cycling. With fzf 0.53 or newer, the active snapshot streams into fzf and
informational rows remain in place when an acceptance key is pressed. Older or
unrecognized fzf versions wait for the active snapshot, use compatible
`--expect` bindings, and may briefly redraw an informational row. Inactive modes
are still prefetched.

Cancelling an explicit picker exits `taw` successfully without opening a tmux
window. Failure to start fzf or generate a picker snapshot returns nonzero.
Informational rows do not exit the picker.

## Invocation Matrix

### `normal`

| Inputs | Result |
| --- | --- |
| zero operands, no `-b` | worktree/branch picker; if `fzf` is missing or returns no rows, open the primary worktree unchanged |
| zero operands, `-b` | create or open `.worktrees/<branch>` |
| one positional, no `-b` | create or open `.worktrees/<path>` with the same branch name |
| two positionals, no `-b` | create or open `.worktrees/<path>` using the second positional as its base ref |
| one positional, `-b` | reject |

### `bare`

| Inputs | Result |
| --- | --- |
| zero operands, no `-b` | if there are no non-bare worktrees, open the default worktree; otherwise use the picker when available, falling back to the default worktree when it is not |
| zero operands, `-b` | create or open a branch worktree under `.worktrees` |
| one positional, no `-b` | treat it as a path under `.worktrees`; the branch name is the same relative path |
| two positionals, no `-b` | treat them as managed worktree path plus base ref |
| any positional with `-b` | reject |
| explicit bare worktree path with `-b` | resolve the project root from the path and open the branch worktree under the root |

If a project is resolved from an existing linked worktree path, `taw` opens
that worktree directly when no branch target is requested. Worktree path
operands reject `.` and `..` segments; absolute paths must resolve beneath
the project's `.worktrees` directory.

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
5. If only a remote ref exists, create a local tracking branch and worktree.

Picker dedupe rules:

- local branch rows suppress matching remote rows
- `origin` wins over other remotes for the same branch name

## Default And Managed Worktrees

Normal projects keep their primary checkout unchanged. Selecting its current
branch opens the project root because Git cannot check out one branch in two
worktrees. Other branch targets are created or reused beneath `.worktrees`.
The portable global Git ignore contains `.worktrees/`, so managed worktree
directories do not appear as untracked content in the primary checkout.

When a bare project needs a default worktree and no explicit target was given,
`taw` probes in this order:

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
- `repo` without a target uses git's default branch; with one target it
  initializes the primary repository and creates the requested orphan
  worktree beneath `.worktrees`
- `bare` accepts at most one pending worktree input, validates the path and branch name before creating the bare repo, then creates an orphan worktree under `.worktrees`

URL clone failures stop the flow; they do not fall through to the create prompt.
URL cloning prompts for `normal` or `bare`, with `normal` as the default.

## Conversion

```text
taw --convert <project>
```

Conversion is an action-only mode. It converts an existing bare repository to
a normal clone, prints the resulting worktree paths, and exits without creating
or selecting a tmux window. It accepts taw wrappers containing `.git` or
`.bare`, and conventional `<name>.git` repositories. Normal and plain projects
are rejected.

The bare repository's symbolic `HEAD` selects the default branch, followed by
the normal `origin/HEAD`, `main`, and `master` fallbacks. An existing worktree
for that branch is promoted to the repository root. If one does not exist, taw
creates a clean default checkout there.

Every other registered worktree is moved beneath `.worktrees`. Branch
worktrees use their complete branch names, including slash-separated paths;
detached worktrees use their previous directory basename. Internal, external,
dirty, staged, untracked, ignored, and detached worktrees retain their Git
state.

Conversion validates all destinations before mutation. It rejects collisions,
duplicate destination names, locked worktrees, active Git operations, Git lock
files, unmerged entries, initialized submodules, sparse or split indexes,
worktree-specific config, and a default worktree that tracks `.worktrees`.
Unmanaged wrapper files are retained at the normal repository root unless
they conflict with promoted default-worktree content. Failures after mutation
starts trigger rollback to the original bare layout. If rollback cannot
finish, taw reports the private recovery directory and leaves it in place.

`--convert` accepts `--debug` but cannot be combined with project, branch,
picker, peer, agent, editor, or shell options. If the invoking shell is inside
a converted worktree, taw changes it to the equivalent directory at its new
location.

## `TAW_AGENT`

- Non-empty trimmed `TAW_AGENT` replaces the default `codex` agent when no explicit `-agent` is supplied.
- unset, empty, or whitespace-only values are ignored.
- explicit `-agent` always wins over the environment.
- plain picker acceptance ignores `TAW_AGENT`; picker layouts containing an agent use it when `-agent` was not supplied.

## tmux Reuse And Layout

Reuse is limited to sessions where no explicit `-agent`, `-ed`, or `-sh` arguments were supplied and `TAW_AGENT` trims to empty. A non-empty trimmed `TAW_AGENT` disables reuse.
When reusing an existing window, taw preserves that window's active pane.

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
taw -p ~/src/repo feature/foo develop
taw --convert ~/src/legacy-bare
taw --peer sheffield-live hallamshire-hotel-all-day
taw --peer --force -p ~/src/repo -agent "claude --resume"
taw --pick-project -agent "claude --resume" -ed "nvim ." -sh "npm test"
taw --mode=wt
taw --mode=branch
```
