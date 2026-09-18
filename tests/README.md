# Tests

List and run focused tests from the repository root:

```bash
tests/run --list tests/taw_test.bash
tests/run --filter 'branch picker' tests/taw_test.bash
tests/run tests/wspath_test.bash
```

`--filter` performs a case-sensitive literal substring match and can be repeated to
select multiple groups. Explicit files and filters run sequentially by default so their
output is easy to inspect.

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
