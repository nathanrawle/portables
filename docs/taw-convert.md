# `taw-convert`

Reference for the `taw-convert` Zsh function.

## Invocation

```text
taw-convert [--debug] <project>
```

`--` stops option parsing, allowing a project path beginning with `-`.
Exactly one existing project is required. Resolution checks an existing literal
path, a simple name under `PROJECTS_HOME`, then an exact tmux session name or
session-path basename. URLs, missing projects, normal repositories, and plain
directories are rejected.

## Conversion

`taw-convert` converts an existing bare repository to a normal clone, prints
the resulting worktree paths, and exits without creating or selecting a tmux
window. It accepts wrappers containing `.git` or `.bare`, and conventional
`<name>.git` repositories.

The bare repository's symbolic `HEAD` selects the default branch, followed by
the normal `origin/HEAD`, `main`, and `master` fallbacks. An existing
worktree for that branch is promoted to the repository root. If one does not
exist, `taw-convert` creates a clean default checkout there.

Every other registered worktree is moved beneath `.worktrees`. Branch
worktrees use their complete branch names, including slash-separated paths;
detached worktrees use their previous directory basename. Internal, external,
dirty, staged, untracked, ignored, and detached worktrees retain their Git
state.

Conversion validates all destinations before mutation. It rejects collisions,
duplicate destination names, locked worktrees, active Git operations, Git lock
files, unmerged entries, initialized submodules, sparse or split indexes,
worktree-specific config, and a default worktree that tracks `.worktrees`.
Unmanaged wrapper files are retained at the normal repository root unless they
conflict with promoted default-worktree content.

Failures after mutation starts trigger rollback to the original bare layout.
If rollback cannot finish, `taw-convert` reports the private recovery
directory and leaves it in place.

If the invoking shell is inside a converted worktree, the function changes to
the equivalent directory at its new location. `--debug` prints the resolved
project state before conversion.

## Example

```bash
taw-convert ~/src/legacy-bare
```
