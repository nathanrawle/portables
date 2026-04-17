# Tests

Run the full suite from the repository root:

```bash
tests/run
```

The test system is intentionally dependency-free so it can run on a fresh
machine before `instantiate` has installed any tooling. Tests execute scripts as
black boxes, isolate `$HOME` in temporary directories, clean up after
themselves, and assert observable filesystem behavior instead of internal
implementation details.

Add new script tests as `tests/<script>_test.bash`. Source files are loaded by
`tests/run`, and each test module should register cases with `test_case`.
