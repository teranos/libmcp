# libMCP

A C11 MCP **client** library for Ground's D `-betterC` harness. Builds static
and shared libraries with a C ABI in `include/mcp.h` and handwritten bindings
in [`source/libmcp.d`](../source/libmcp.d). MIT, like Ground.

Ground owns the connections, catalogs and dispatch. Provider adapters can use
them without owning MCP processes or introducing another language runtime.

## Build and link

```sh
nix develop
make -C libmcp
make test-mcp
nix build .#libmcp --no-link
make -C libmcp install PREFIX="$HOME/.local"
```

Outside Nix: C11, make, pkg-config, json-c and libcurl (7.85+); tests also need Python 3 and
LDC. json-c 0.18 requires the upstream fix in `json-c-strict-utf8.patch`: its
strict mode otherwise rejects valid UTF-8. The flake applies this fix to its
locked dependency. json-c 0.17 works unpatched. Validation remains strict.

Installation includes `mcp.h`, both libraries, `libmcp.pc`, and the D binding
under `include/d`. Link shared consumers using `pkg-config --cflags --libs
libmcp`. For static linkage select the archive explicitly and include its dependencies:

```sh
cc client.c libmcp/build/libmcp.a -Ilibmcp/include $(pkg-config --cflags --libs json-c libcurl)
ldc2 -betterC -I=source app.d libmcp/build/libmcp.a -L-ljson-c -L-lcurl
```

## API and ownership

Initialize `mcp_options` with `mcp_options_init`, set `command`, null-terminated
`argv` (including argv[0]), and `client_name`, then call `mcp_client_open`.
Initialize each `mcp_response` to zero, consume it on success **and failure**,
and release it with `mcp_response_free` before reuse. `mcp_client_close` consumes
the handle, including on failure. [`tests/client.c`](tests/client.c) and
[`examples/client.d`](examples/client.d) are executable examples.

Helpers cover tools, resources, resource templates, prompts, completions and
subscriptions. `mcp_client_request` waits for one response; `mcp_client_call`
also fulfills multi-round input requests through declared host handlers.
Pagination belongs to the caller. Transport failures never trigger tool retries.

For multiplexing, use `mcp_client_submit`, drive `mcp_client_poll`, then inspect,
take and destroy each `mcp_request`. Responses can arrive out of order. Each
request has its own deadline and cancellation. Completed handles count toward
`max_pending` until destroyed (64 by default). Acknowledged subscriptions remain
active until cancelled, completed or disconnected. libMCP runs on the polling thread; libcurl may use resolver threads.
All access to one client must happen on one thread at a time; independent
clients may run concurrently. The [async D example](examples/async.d) exercises
concurrent requests and a host elicitation callback without druntime or GC.

Responses retain the exact wire frame without its terminal newline. Remote
JSON-RPC errors, tool `isError` results, and input-required results have distinct
statuses and retain their full payload. System errors include errno and child
exit failures include raw waitpid status. Failed opens expose secondary rollback
failures in `error.cleanup_*`. Error message pointers have static lifetime.

Defaults: 30 seconds per call, 500 ms for discovery probing, one second per
shutdown grace interval, and 1 MiB per frame. Timeouts/limits must be positive;
zero is rejected. An absolute monotonic deadline covers writing, reading and
interleaved notifications. A timeout cancels only its request. Stdio transport, framing and incoming size
failures make the connection unusable. HTTP transfer failures are isolated to
their request. There is no silent retry
of a possibly side-effecting tool call.

Servers launch directly through argv with no shell. `envp = NULL` inherits the
environment; supplied envp replaces it. `cwd = NULL` inherits the working
directory. Stderr is inherited and never treated as proof of protocol failure.
The optional message callback observes notifications and legacy server requests
using borrowed frames; it must return promptly and cannot reenter its client.
No process-wide signal disposition is changed, including SIGPIPE. Shutdown
closes stdin, waits, then escalates TERM/KILL and reaps; forced shutdown is an
error, not success.

## Ground harness integration

ACP `session/new` now connects the stdio servers in `params.mcpServers`.
Each configuration has `name`, `command`, `args` and `env`; environment entries
are `{ "name": "KEY", "value": "value" }` and override inherited keys.
Processes run in the session's `cwd`.

Configuration is validated before spawning. Limits: 32 unique server names per
session, 128 arguments and 128 environment entries per server. A session owns
every connection and all initial `tools/list` pages (maximum 128 pages, repeated
cursor rejected). Partial setup rolls back. `session/close` and host EOF close
and reap the children. Cleanup errors reach stderr and the ACP response; large
error payloads grow the reply buffer instead of being cut to 4096 bytes.

[`source/code/mcp.d`](../source/code/mcp.d) exposes `McpGroup`,
`McpServer.tools` and `callMcpTool(group, serverName, toolName, arguments,
response, error)` to the harness. The `(server, tool)` pair prevents collisions
between servers exposing identically named tools.

This change supplies the MCP client layer. Ground's model/provider loop,
`session/prompt`, tool approval policy and ACP tool-call updates remain separate
harness work. No custom ACP tool-dispatch method is added.

For direct diagnostics, Ground and the standalone D client use the same ABI:

```sh
make -C libmcp test-d
libmcp/build/mcp-client tools/list '{}' -- /path/to/mcp-server
ground mcp tools/call '{"name":"echo","arguments":{"text":"hello"}}' -- /path/to/mcp-server
```

## Protocol scope

The pinned target is `2026-07-28`; see the [coverage matrix](CONFORMANCE.md)
and [source pins](spec/PINNED.json). This is a broader client implementation,
with explicit remaining gaps, not a full conformance claim.

Stdio supports automatic discovery and legacy fallback, plus modern-only and
legacy-only modes. Recognized modern errors never trigger downgrade. Legacy
initialization accepts `2025-11-25`, `2025-06-18`, `2025-03-26` and `2024-11-05`.
Client capabilities default to `{}`. `mcp_client_open_ex` accepts explicit roots,
sampling and elicitation capabilities and a host handler. Modern peers use
input-required results; legacy peers receive JSON-RPC replies. Unsupported
features are never advertised automatically. Sampling and roots are deprecated
in the pinned modern revision and remain opt-in compatibility features.

`mcp_client_open_http` discovers a modern Streamable HTTP endpoint. The library
accepts JSON and request-scoped SSE, sets the required MCP headers, checks TLS,
and rejects redirects. Plain HTTP is restricted to loopback endpoints.
`mcp_client_create_http` creates the endpoint without network I/O: call
`server/discover` explicitly to observe an initial 401 and its authentication
challenge, obtain a token through your host, set it with `mcp_client_set_bearer`,
then explicitly retry discovery. The library never refreshes or stores tokens
on disk. It does not implement OAuth discovery, authorization or registration.

HTTP tool discovery builds a filtered catalog accessible through
`mcp_client_tools_catalog`. Use that catalog for tool selection; raw
`tools/list` responses preserve the original wire JSON, including rejected tool
definitions, for diagnostics. Valid `x-mcp-header` annotations are mirrored as
`Mcp-Param-*` headers. A new first page resets the catalog; subsequent pages
append. Refresh the catalog when tools change. Concurrent catalog refreshes are
not supported. No automatic replay occurs after HeaderMismatch.

General JSON Schema 2020-12 validation remains a host responsibility. The
library validates framing, correlation, multi-round envelopes, progress,
subscription filters and HTTP header annotations; these checks do not substitute
for full schema validation. It never fetches external schema references.

## Validation

`make test-mcp`: shared C ABI subprocess tests, a static C client, measured C/D
layouts, D round trips, asynchronous D callbacks, multiplexing/cancellation/MRTR,
legacy client-feature replies, loopback HTTP/SSE, and the D harness boundary.
Linux also fault-injects parser allocation failure to verify typed OOM errors.
`python3 libmcp/tests/test_ground.py ./ground`: actual ACP session ownership,
pagination, env/cwd, rollback, malformed configuration, large errors and EOF
cleanup. CI runs the package and ACP checks on Linux and macOS.

`make -C libmcp test-interop SDK_ROOT=/path/to/python-sdk SDK_PYTHON=/path/to/venv/bin/python`
runs independent stdio/HTTP JSON/HTTP SSE tests against the pinned official SDK
and validates its tool results against the vendored schema. See
[reproduction instructions](spec/README.md). This optional test target requires
an explicitly prepared SDK; normal builds and tests never download code.
