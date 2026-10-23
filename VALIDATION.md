# Validation of 0.2

Validated on Linux with system json-c 0.17/libcurl 8.5/LDC 1.36 and the pinned
Nix environment (patched json-c 0.18/libcurl 8.18/LDC 1.41).

- 55 deterministic Python protocol/runtime/HTTP tests: 28 base, 14 runtime,
  one legacy feature-dispatch test, and 12 HTTP/SSE tests.
- Four independent official Python SDK tests: modern and legacy stdio, modern
  HTTP JSON and HTTP SSE. Modern tool results are validated against the pinned
  2020-12 schema. SDK commit and schema hash are checked by the test runner.
- Static C embedding, exact remote-error ownership, unchanged SIGPIPE handling
  and child reaping.
- Linux parser-allocation fault injection returns `MCP_NO_MEMORY`; injected
  cancellation-flush I/O failure preserves errno and terminates other pending
  requests with the original typed error.
- 25 measured C/D layout comparisons, 15 D diagnostic round trips, D harness
  discovery/dispatch/cleanup, and a D `-betterC` async/MRTR callback example.
- ASan/UBSan: all 14 runtime and 12 HTTP tests passed on the final C source.
  LeakSanitizer was disabled because the container cannot support its process
  inspection; no leak-check claim is made.
- Both `nix build .#libmcp` and `nix build .#ground` succeeded. Installed shared
  library consumers compiled and ran in C and D. The packaged Ground passed
  ACP ownership, pagination, environment/cwd, rollback, validation, large error
  payload and EOF cleanup checks.

Commands:

```sh
make -C libmcp test test-d
make -C libmcp test-interop SDK_ROOT=/path/to/pinned-sdk SDK_PYTHON=/path/to/venv/bin/python
nix build .#libmcp .#ground --no-link
python3 libmcp/tests/test_ground.py /path/to/installed/ground
```

Scope limits: macOS execution still requires CI. The complete Ground unit suite
has a pre-existing assertion failure in `source/sentry.d:700`, reproduced on
unchanged main during the foundation work; this extension did not alter Sentry
or rerun that unrelated full suite. The checks above are the library and
integration checks actually performed. See `CONFORMANCE.md` for protocol gaps.
