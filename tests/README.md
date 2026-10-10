# Tests

List and run focused tests from the repository root:

```bash
tests/run --list tests/taw_test.bash
tests/run --filter 'branch picker' tests/taw_test.bash
tests/run tests/wspath_test.bash
```

`--filter` performs a case-sensitive literal substring match and can be repeated to
select multiple sets of cases. Explicit files and filters run sequentially by default.

Terminal runs show one progress row per selected test file. Rows start queued, spin
while the group's cases run, and finish with pass/fail and completed/selected counts.
Filtered runs include only files with matching cases. Progress combines cases across
parallel workers. Small terminals use a static group list and final group statuses;
a resize that causes wrapping or makes the panel too tall also switches to this display.

Captured or piped output contains no progress redraws. Use `--no-progress` when an
agent runs through a pseudo-terminal, or whenever you want plain output:

```bash
tests/run --no-progress tests/taw_test.bash
```

The final report defaults to failed cases and their captured diagnostics, followed by
the suite total. Choose the individual results shown at completion with `--report`:

| Mode | Results shown |
| --- | --- |
| `failed` (default) | Failed cases and diagnostics |
| `passed` | Successful cases |
| `all` | Every case in test order, including failure diagnostics |
| `none` | Only the suite total |

Completed progress rows remain visible in terminals even with `--report none`.
Report selection does not change failure counts or exit status, and runner errors
remain visible in every mode. Successful cases' captured output stays hidden.
Both `--report MODE` and `--report=MODE` are supported. `--list` continues to print
matching test names without progress or a final report.

Test workers receive an empty stdin so tests cannot read input from the invoking
terminal or pipeline. Supply any input a test needs explicitly within its fixture.

```bash
tests/run --report all tests/run_test.bash
tests/run --filter 'branch picker' --report none tests/taw_test.bash
```

Run the full suite only at the pull-request publication gates described in
[`AGENTS.md`](../AGENTS.md):

```bash
tests/run
```

Full runs detect the available logical cores and shard test cases across them. Override
the concurrency for diagnosis with `tests/run --jobs N` or `TEST_JOBS=N`; use
`--jobs 1` to reproduce a case without parallel workers.

The test system is intentionally dependency-free so it can run on a fresh
machine before `instantiate` has installed any tooling. Tests execute scripts as
black boxes, isolate `$HOME` in temporary directories, clean up after
themselves, and assert observable filesystem behavior instead of internal
implementation details.

Add new script tests as `tests/<script>_test.bash`. Source files are loaded by
`tests/run`, and each test module should register cases with `test_case`.

Prefer representative equivalence classes over combinatorial matrices. Retain explicit
boundaries for destructive operations, data preservation, rollback, bootstrap and
process lifecycle, and compatibility behavior.
