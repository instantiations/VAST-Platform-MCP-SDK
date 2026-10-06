# Conformance testing

The official [MCP conformance suite](https://github.com/modelcontextprotocol/conformance)
(`@modelcontextprotocol/conformance`) checks an implementation against the
protocol specification. The SDK ships two fixtures for it in
`McpHttpTestsApp`:

| Fixture | Role |
| --- | --- |
| `McpConformanceServer` | An `McpServer` with the tools, resources, prompts, completions and MRTR scenarios that the suite expects, hosted on Streamable HTTP. |
| `McpConformanceClient` | Runs the client scenarios that the suite requests. |

```text
            @modelcontextprotocol/conformance
              │                          ▲
  server mode │                          │ client mode
              ▼                          │
   McpConformanceServer         McpConformanceClient
   http://127.0.0.1:3000/mcp    (started by the runner)
```

The SDK's own SUnit suites in `McpTestsApp`, `McpHttpTestsApp` and
`McpHttpOAuth2TestsApp` complement the conformance suite. Run them from the
SUnit Browser before a release.

## Prerequisites

- The `MCP SDK` configuration map, including the test applications.
- Node.js 20 or later with `npx`.

## Testing the server

### 1. Start the fixture

```smalltalk
| conformance |
conformance := McpConformanceServer startOnPort: 3000.
Transcript show: 'Conformance server running at: ' , conformance url; cr.
```

`McpConformanceServer defaultPort` is `3000`. After changing fixtures or SDK
code, `conformance restart` picks up the changes. `conformance stop` shuts the
server down.

### 2. Run the suite

From the repository's `tests` directory, which holds the baseline file:

```bash
npx @modelcontextprotocol/conformance server --url http://127.0.0.1:3000/mcp --expected-failures ./conformance-baseline.yml
```

To run a single scenario:

```bash
npx @modelcontextprotocol/conformance server --url http://127.0.0.1:3000/mcp --scenario tools-call-with-progress
```

Useful scenarios while working on a specific area:

| Scenario | Exercises |
| --- | --- |
| `tools-call-simple-text` | basic tool call |
| `tools-call-with-progress` | progress over an SSE response stream |
| `dns-rebinding-protection` | Host and Origin validation |
| `input-required-result-basic-elicitation` | SEP-2322 multi-round-trip elicitation |
| `server-sse-multiple-streams` | concurrent POSTs |

## Testing the client

### In the image

Run every client scenario against a running `McpConformanceServer`, without
packaging:

```smalltalk
McpConformanceClient runAllOnUrl: 'http://127.0.0.1:3000/mcp'.
```

The Transcript shows a `[PASS]`/`[FAIL]` line per scenario and a summary. Run
one scenario and inspect its result:

```smalltalk
(McpConformanceClient runScenario: 'sep-2322-client-request-state' onUrl: 'http://127.0.0.1:3000/mcp') inspect.
```

Supported scenarios: `initialize` (alias `tools-call`), `request-metadata`,
`sep-2322-client-request-state`, `elicitation-defaults`,
`json-schema-2020-12-preservation`, `json-schema-ref-no-deref`, and `auth/...`
scenarios.

### With the official runner

In client mode, the runner starts its own mock server and launches your client
as a process. The scenario name, context and protocol version are passed in
the `MCP_CONFORMANCE_SCENARIO`, `MCP_CONFORMANCE_CONTEXT` and
`MCP_CONFORMANCE_PROTOCOL_VERSION` environment variables, and the server URL
as the last command-line argument.

1. Package a headless image whose startup runs `McpConformanceClient main`.
   `main` runs the scenario and exits with status 0 on success or 1 on
   failure.
2. Point the runner at it:

```bash
npx @modelcontextprotocol/conformance client --command "<VAST VM executable> -i<path>/mcp-conformance-client.icx -nouistart" --suite all --expected-failures ./conformance-baseline.yml
```

## The baseline file

`tests/conformance-baseline.yml` lists scenarios that are expected to fail,
grouped by reason:

- scenarios for features that `2026-07-28` deprecated or replaced (legacy
  elicitation/sampling, `logging/setLevel`, `resources/subscribe`),
- optional extensions that the SDK doesn't implement (tasks, skills, several
  OAuth variants),
- scenarios whose harness checks aren't yet verified against the reference.

The runner also fails when an entry in the baseline unexpectedly **passes**:

```text
Stale baseline entries (now passing - remove from baseline):
  ? <scenario-name>
```

Remove such entries from the file. This keeps the baseline honest.

## Investigating failures

- Each run writes `results/<mode>-<scenario>-*/checks.json`, with the HTTP
  status codes, headers and messages of every check.
- `--verbose` prints every JSON-RPC message.
- DNS-rebinding failures usually mean that the server isn't accepting
  `localhost`, `127.0.0.1` or `[::1]`, or is reached through a proxy or Docker
  bridge name. Configure `allowedHosts:` accordingly (see
  [Security](../advanced/security.md#dns-rebinding-protection)).
