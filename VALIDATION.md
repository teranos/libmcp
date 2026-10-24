# Validation

## 0.3 first increment: request-owned HTTP diagnostics

Executed on Linux with json-c 0.17 and libcurl 8.5.0:

- `make test`: 62 Python tests (28 base, 14 runtime, one legacy feature test,
  19 HTTP tests), static C embedding, parser allocation and cancellation I/O
  fault injection passed.
- `make test-interop` against the SDK pin in `spec/PINNED.json`: all four
  independent modern/legacy stdio and HTTP JSON/SSE tests passed.
- All 19 HTTP tests passed with AddressSanitizer and UndefinedBehaviorSanitizer.
  Leak detection was disabled; no leak-check claim is made.
- `make install PREFIX=/absolute/staging/path` followed by compilation and
  execution of `tests/client.c` against the installed header/archive passed.
  Dependencies were linked with `pkg-config --cflags --libs json-c libcurl`.
  The fully expanded `pkg-config --static libmcp` link was not verified here:
  this environment lacks development libraries for libcurl's transitive deps.
- No macOS, Nix or D execution was performed for this increment. Existing
  public struct layouts are unchanged; the new accessors take opaque handles.

The seven added HTTP regressions cover per-request 401/403 diagnostics despite
other completions and `take`, repeated challenges with quoted commas, interim
header reset, independent transport failures, SSE/cancellation diagnostics,
aggregate challenge limits, and continuation diagnostics/Content-Type reset.
The static C consumer exercises the new symbols for NULL and stdio handles.

Reproduce the sanitizer check from the repository root:

```sh
make BUILD=build-sanitize CFLAGS='-O1 -g -std=c11 -Wall -Wextra -Wpedantic -Werror -fPIC -fsanitize=address,undefined -fno-omit-frame-pointer'
ASAN_OPTIONS=detect_leaks=0:halt_on_error=1 UBSAN_OPTIONS=halt_on_error=1 \
  LD_PRELOAD="$(cc -print-file-name=libasan.so)" \
  python3 tests/test_http.py build-sanitize/libmcp.so
```

## Historical 0.2 validation in Ground

The following records the original Ground integration before extraction into
this repository. Ground-specific targets and D bindings are not provided by
the standalone Makefile; these are historical results, not fresh 0.3 checks.

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
