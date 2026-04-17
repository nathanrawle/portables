# Personal defaults for Codex

These are global, repository-agnostic working preferences that apply unless a project overrides them.

## How to work

- Start by understanding the task and the relevant files before editing.
- Prefer small, reversible changes over broad rewrites.
- State assumptions briefly when they materially affect the solution.
- Surface uncertainty early instead of guessing.
- When several approaches are viable, prefer the simplest one that meets the requirement.

## Before changing code

- Read the nearest relevant documentation and configuration first.
- Look for existing patterns in the repository and follow them.
- Do not introduce new dependencies unless they are clearly justified.
- Avoid changing unrelated files while addressing the task.

## While changing code

- Preserve existing style unless the repository specifies otherwise.
- Keep names, comments, and docs concrete rather than clever.
- Prefer explicitness over hidden magic.
- Minimise irreversible or destructive actions.

## Validation

- After making changes, run the smallest relevant checks first.
- If fast local validation exists, use it before broader test suites.
- Report what you validated, what passed, and what you could not verify.
- If you could not run validation, say so clearly.

## Communication

- Be concise but not cryptic.
- Summarise the change, the reason for it, and any follow-up the user should know about.
- Do not claim success unless the relevant checks passed or the limitation is stated explicitly.

## Safety

- Ask for approval before destructive operations, external side effects, or secrets-related actions.
- Treat production, billing, infrastructure, and authentication changes as higher risk.
- Prefer inspection and explanation over mutation when the intent is unclear.

## Language-specific defaults

These are personal, global preferences. Apply them when relevant unless the repository clearly prefers something else.

### Terraform

- Prefer clear, conventional HCL over clever expression-heavy constructs.
- Keep resource and module definitions readable and explicit.
- Avoid introducing unnecessary dynamic blocks, nested conditionals, or heavily compacted comprehensions.
- Prefer stable plan-time behavior; avoid patterns that depend on values only known at apply time unless clearly necessary.
- Be careful with `for_each`, `count`, and map keys; prefer predictable keys and deterministic addressing.
- Preserve provider and module structure already used by the repository.
- Do not add provider, module, or version constraints unless the task requires it.
- When suggesting examples outside a repository, assume GCP unless the surrounding context clearly indicates otherwise.
- Call out likely plan/apply risks, permadiff risks, or unknown-value risks when they are material.

### Shell scripts

- Default to modern Bash for shell snippets unless the repository or file clearly requires another shell.
- Prefer Bash compatibility over zsh-specific features and over strict POSIX portability by default.
- If writing shell intended for very broad portability, use POSIX `sh` only when that requirement is clear.
- Preserve the shell already used by the repository when editing existing files.
- Prefer simple pipelines and readable command composition over dense one-liners.
- Assume common CLI tools such as `jq` and `yq` are available unless portability requirements suggest otherwise.
- Quote carefully and consistently.
- Avoid fragile parsing of human-readable command output when structured output is available.
- Be explicit when using Bash-specific features.

### GitHub Actions

- Prefer valid, conservative workflow syntax over clever expression tricks.
- Keep workflows readable and easy to debug.
- Reuse existing workflow patterns in the repository where possible.
- Prefer least-privilege permissions and avoid silently broadening token access.
- Be careful with matrix, `needs`, outputs, conditionals, and expression syntax; prefer approaches that are straightforward and valid over ones that are merely compact.
- Avoid introducing unnecessary third-party actions when official actions or simple shell steps are sufficient.
- Call out where behavior differs between pull request, push, and manual dispatch contexts when it matters.

### Python

- Prefer straightforward, standard-library-first solutions unless a dependency is already established or clearly justified.
- Write code that is readable, typed where useful, and lightly commented when the intent may not be obvious.
- Prefer explicit control flow over dense abstraction.
- Include reasonable error handling where failure is plausible.
- Keep scripts and functions small and composable.
- Preserve the repository’s formatting, linting, and test conventions where they exist.
