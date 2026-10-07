# Troubleshooting

## Error codes

JSON-RPC errors reach the client as `McpJsonRpcError` (`code`, `messageText`,
`data`). The constants are defined in the `McpJsonRpcConstants` pool.

| Code | Constant | Typical cause |
| --- | --- | --- |
| `-32700` | `McpJsonRpcParseErrorCode` | The body isn't valid JSON (stdio: a line isn't a complete JSON message). |
| `-32600` | `McpJsonRpcInvalidRequestCode` | Not a JSON-RPC 2.0 request. |
| `-32601` | `McpJsonRpcMethodNotFoundCode` | Unknown method, or a method not available in the negotiated protocol version. |
| `-32602` | `McpJsonRpcInvalidParamsCode`/ `McpResourceNotFoundErrorCode`| Unknown tool, prompt or resource (modern), missing or invalid params, invalid prompt arguments. |
| `-32603` | `McpJsonRpcInternalErrorCode` | Unhandled server error, e.g. a resource reader that failed, a result that violates the `outputSchema`, or a rejected `requestState`. |
| `-32002` | `McpServerNotInitializedErrorCode` | Unknown resource (handshake era), or a request before `initialize` completed. |
| `-32020` | `McpHeaderMismatchErrorCode` | The `Mcp-Method`/`Mcp-Name`/`Mcp-Param-*` headers don't match the body. |
| `-32021` | `McpMissingRequiredClientCapabilityErrorCode` | The server requires a client extension or capability that the client didn't declare. |
| `-32022` | `McpUnsupportedProtocolVersionErrorCode` | The server doesn't support the requested protocol version. |

Tool failures aren't JSON-RPC errors: they arrive as results with
`isError: true`.

## HTTP status codes

| Status | Meaning |
| --- | --- |
| `400 Bad Request` | Malformed body or headers, header mismatch (`-32020`), unsupported version (`-32022`), missing session id. |
| `401 Unauthorized` | Missing or rejected bearer token. See `WWW-Authenticate`. |
| `403 Forbidden` | `Origin` or `Host` not allowed (DNS-rebinding protection). |
| `404 Not Found` | Unknown or expired handshake-era session. The client re-initializes automatically. |
| `406 Not Acceptable` | The client's `Accept` header doesn't include both `application/json` and `text/event-stream`. |
| `413 Payload Too Large` | Body exceeds `maximumRequestSize`. |

## Common problems

**`MCP client transport is not configured`**
: Set `client transport: ...` before `connect`.

**`MCP client is not connected`**
: Send `connect` first. After `close`, the client must be connected again.

**`MCP server does not support tools/list`** (or another operation)
: The server didn't advertise that capability. Check
`client serverCapabilities`.

**A modern server rejects the client, or `connect` performs an `initialize` handshake**
: `McpClient new` defaults to `#legacy`. Use `McpClient modern` or
`McpClient auto`.

**`Server exceeded maximum inputRequired rounds: 10`**
: The server kept answering `input_required`. Check that the matching
callback is installed and answers what the server expects, and that the tool
has at most one resolver (see
[Interactive input](advanced/mrtr-interactive-input.md)).

**`No client elicitationCallback registered for input request: ...`**
: The server asked for input that the client can't provide. Install the
callback, and declare the capability in `capabilities:`.

**`Failed to configure the SST HTTP listener` / `Failed to start the SST HTTP server`**
: The port is probably in use, possibly by an earlier `McpHttpServer` that is
still running in the image. Stop it, or choose another port.

**`Multiple MCP resource templates match the URI`**
: Two templates overlap. Make them disjoint, or use `matchBlock:` to narrow
one of them.

**`MCP tool with outputSchema requires structuredContent` / `structuredContent violates the outputSchema`**
: A tool with an `outputSchema` must answer a dictionary (without
`'content'`) that conforms to it.

**Tools receive `nil` as context**
: The request came in over the legacy SSE transport, which doesn't create a
request context.

**A tool's error message reveals internals**
: Every `Error` signalled in a tool becomes `isError: true` with its
`messageText`. Catch low-level errors and signal `McpToolError` with a
message intended for the model.

**The stdio server process starts but the client times out**
: Check `transport stderrLines`. Make sure that the server flushes stdout
(`python -u`), and that the command is found (Windows: `npx.cmd` or
`runInShell: true`). Remember that `requestTimeout:` is in **seconds** for
stdio and in **milliseconds** for HTTP.

**An `McpDeprecationWarning` appears in the Transcript**
: A configuration default will change in a future version, e.g. set
`validateTokenResource:` explicitly on `McpAuthSettings`. The warning is
resumable and doesn't stop execution.

## Text encoding

- All transports use **UTF-8**. Pass Smalltalk strings (`String` or
  `UnicodeString`). The SDK encodes and decodes at the transport boundary.
- Streamed HTTP responses arrive in chunks that can split a multi-byte UTF-8
  character. The SSE parser scans line endings at the byte level and decodes
  only complete events, so non-ASCII text survives chunk boundaries.
- In a `UnicodeString`, CR LF is a single grapheme. The JSON writer still
  emits it as `\r\n`, so line endings in tool output and resource text are
  preserved exactly, and SSE framing is recognized on bytes rather than
  graphemes.
- Binary data never goes into `text`. Base64-encode it into `blob` (resources)
  or `data` (image and audio content).

## Debugging techniques

**Leave the network out.** Reproduce with
`McpClient forServer: server mode: #modern`. If the problem disappears, it is
in the transport configuration (Host/Origin, auth, headers).

**Look at the raw protocol.** Bypass the convenience API and result
validation:

```smalltalk
client sendRequest: 'tools/list' params: EsOrderedDictionary new.
client sendRequest: 'tools/call' params: (EsOrderedDictionary
    with: 'name' -> 'add'
    with: 'arguments' -> (EsOrderedDictionary with: 'a' -> 1 with: 'b' -> 2)).
```

**Debug server code in place.** Over the in-memory transport, the tool block
runs in your process. Put `self halt` in the block, or use the VAST debugger
on a failing SUnit test. Over HTTP, tool blocks run in SST worker processes,
so reproduce in-memory first.

**Use MCP Inspector** to see exactly what an external host sees:

```bash
npx @modelcontextprotocol/inspector http://127.0.0.1:8080/mcp
```

**Run the conformance suite** with `--verbose` for a message-level trace (see
[Conformance testing](testing/conformance.md)).

**Clear client state.** `client clearCache` (or `cacheMode: #bypass`) rules
out stale cached results. `client close` followed by `client connect`
re-negotiates.
