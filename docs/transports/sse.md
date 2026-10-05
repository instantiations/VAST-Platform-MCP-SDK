# Legacy HTTP+SSE

Before Streamable HTTP, MCP used a two-endpoint transport (protocol
`2024-11-05`):

1. The client opens a long-lived `GET /sse` stream.
2. The server's first event, `endpoint`, tells the client where to `POST` its
   messages, typically `/messages?sessionId=...`.
3. The client `POST`s each JSON-RPC message there. The server answers
   `202 Accepted` and sends the actual responses as events on the SSE stream.

The specification has deprecated this transport, but some older servers and
hosts still use it. The SDK supports it on both sides for compatibility. Use
[Streamable HTTP](streamable-http.md) for anything new.

## Server side

There is nothing to configure. Every `McpHttpServer` also serves the legacy
endpoints:

| Method and path | Behavior |
| --- | --- |
| `GET /sse` | Creates a session, opens the event stream and sends the `endpoint` event. |
| `POST /messages?sessionId=...` | Validates the session, dispatches the message, and answers `202 Accepted`. The response travels over the stream. |
| `DELETE /messages?sessionId=...` | Ends the session (`204 No Content`). |

The legacy endpoints apply the same Host and Origin checks and the same bearer
authentication as `/mcp`, and accept bodies of up to 4 MB.

!!! warning "No request context"
    Requests that arrive over the legacy endpoints are dispatched **without**
    an `McpServerRequestContext`. Blocks that take a context argument receive
    `nil`, `requestContextFactory:` isn't applied, and progress can't be
    reported. Write context-using tools defensively, e.g.
    `context ifNotNil: [:ctx | ctx reportProgress: ...]`.

## Client side

```smalltalk
| client |
client := McpClient legacy
    transport: (McpLegacySseClientTransport url: 'http://127.0.0.1:8080/sse');
    yourself.
[client connect.
 client listTools]
    ensure: [client close].
```

Use `McpClient legacy` with this transport. The SSE transport predates the
modern protocol.

`McpLegacySseClientTransport`:

- opens the stream and waits for the `endpoint` event,
- accepts only a `POST` endpoint with the **same origin** as the SSE URL, so a
  hostile server can't redirect your messages elsewhere,
- picks up the session id from the endpoint's query string,
- correlates responses that arrive on the stream with the waiting requests,
  and forwards notifications and server requests to the client,
- supports `additionalHeaders:` and per-call headers, like the Streamable HTTP
  transport.

`close` ends the stream and the session.

## Choosing a transport for an unknown server

| The server's URL ends in... | Try |
| --- | --- |
| `/mcp` (or anything that isn't `/sse`) | `McpClient auto` with `McpHttpClientTransport` |
| `/sse` | `McpClient legacy` with `McpLegacySseClientTransport` |
