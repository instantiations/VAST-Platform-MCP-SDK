# Streamable HTTP

Streamable HTTP is the standard network transport of MCP. Requests are HTTP
`POST`s to a single endpoint, and responses come back either as plain JSON or,
when the server has something to stream (progress, notifications), as a
Server-Sent Events (SSE) stream on the same response.

In the SDK:

| Side | Class | Application |
| --- | --- | --- |
| Server | `McpHttpServer` (with `McpStreamableHttpTransport` and `McpHttpServlet`) | `McpHttpServerSubApp` |
| Client | `McpHttpClientTransport` | `McpHttpClientSubApp` |

Both run on SST, the VAST Platform's HTTP stack.

## Hosting a server

```smalltalk
| http |
http := McpHttpServer new
    host: '127.0.0.1';
    port: 8080;
    mcpServer: server;
    start;
    yourself.

http isRunning.    "true"
http stop.
```

`start` creates an SST servlet engine with these endpoints:

| Path | Purpose |
| --- | --- |
| `/mcp` (`endpointPath:`) | Streamable HTTP: `POST` for requests, `GET` for handshake-era server streams, `DELETE` to end a handshake-era session |
| `/sse` and `/messages` | [Legacy HTTP+SSE](sse.md) for old clients |

One `McpHttpServer` serves both protocol eras on the same endpoint:

- **Modern (`2026-07-28`)** requests are sessionless. Each `POST` carries its
  version and capabilities in `params._meta`, and the `MCP-Protocol-Version`,
  `Mcp-Method` and `Mcp-Name` headers are checked against the body.
- **Handshake-era** clients `POST` `initialize` and receive an
  `MCP-Session-ID` header, which they send with every later request.

### Configuration

| Selector | Default | Purpose |
| --- | --- | --- |
| `host:` | `'127.0.0.1'` | Interface to bind. Keep the loopback address unless remote access is required. |
| `port:` | `8080` | TCP port. |
| `endpointPath:` | `'/mcp'` | Path of the Streamable HTTP endpoint. |
| `mcpServer:` | required | The `McpServer` to expose. |
| `allowedHosts:` | empty | Accepted `Host` header values. See [DNS rebinding](#dns-rebinding-and-origins). |
| `allowedOrigins:` | empty | Accepted `Origin` values in addition to localhost origins. |
| `authSettings:` | `nil` | Bearer token authentication. See [OAuth 2.0](../advanced/oauth2.md). |
| `maximumRequestSize:` | 10 MB | Larger request bodies are rejected. |
| `sessionIdleTimeout:` | 1800 s | Idle handshake-era sessions are discarded after this. |
| `maxSessions:` | 10000 | Upper bound on concurrent handshake-era sessions. |
| `requestContextFactory:` | `nil` | `[:request :session \| ...]` building each [`McpServerRequestContext`](../servers/context.md). |

You can run several `McpHttpServer`s in one image, on different ports, each
with its own or a shared `McpServer`.

### Streaming responses

When a tool reports progress (`context reportProgress:...`) and the client
asked for it, the response is switched to `text/event-stream`. The progress
notifications are sent as SSE events, followed by the final JSON-RPC response.
Without progress, the server answers `application/json`.

### DNS rebinding and origins

A browser page on a malicious site can try to reach a server on `127.0.0.1`
through DNS rebinding. `McpHttpServer` defends against this as follows:

- **Origin:** every request with an `Origin` header must come from a localhost
  origin (`localhost`, `127.0.0.1`, `[::1]`, any port, `http` or `https`) or
  from an entry in `allowedOrigins:`. Anything else is rejected with
  `403 Forbidden`.
- **Host:** once `allowedHosts:` is set, the `Host` header must match one of
  its entries, with or without the port. `'*'` allows any host.

!!! warning
    With the default, empty `allowedHosts`, the `Host` header is **not**
    checked. To get full DNS-rebinding protection on a local server, set it
    explicitly:

```smalltalk
http allowedHosts: #('localhost' '127.0.0.1' '[::1]').
```

If the server is reachable under a public name, list that name instead, and
put the server behind a TLS-terminating reverse proxy. `McpHttpServer` only
listens on plain HTTP. See [Security](../advanced/security.md).

## Connecting a client

```smalltalk
| client |
client := McpClient auto
    transport: (McpHttpClientTransport url: 'http://127.0.0.1:8080/mcp');
    yourself.
[client connect.
 client listTools]
    ensure: [client close].
```

`https://` URLs are supported through `SstHttpsCommunications` (OpenSSL).

### Configuration

| Selector | Default | Purpose |
| --- | --- | --- |
| `url:` | required | Endpoint URL. |
| `requestTimeout:` | 60000 | Milliseconds to wait for a response. |
| `additionalHeaders:` | empty | Headers sent with every request, e.g. API keys or tracing. |
| `bearerToken:` | `nil` | Static token, sent as `Authorization: Bearer ...`. |
| `tokenProvider:` | `nil` | Zero-argument block that answers a token for each request. Use it when tokens expire. |

```smalltalk
(McpHttpClientTransport url: 'https://mcp.example.com/mcp')
    requestTimeout: 120000;
    additionalHeaders: (EsOrderedDictionary with: 'X-Api-Key' -> 'secret');
    tokenProvider: [self tokenStore currentAccessToken];
    yourself.
```

For OAuth 2.0 servers, use `McpOAuth2ClientProvider`. It obtains tokens and
retries after `401` responses. See [OAuth 2.0](../advanced/oauth2.md).

### What the transport does for you

- Sends `Accept: application/json, text/event-stream` and, in modern mode,
  `MCP-Protocol-Version` and the routing headers.
- Reads both plain JSON and SSE responses. Progress events are routed to your
  `progressCallback:`, and notifications to the client's handlers.
- Keeps the `MCP-Session-ID` for handshake-era servers and sends `DELETE` on
  `close`. If the server forgets the session (`404`), the session is
  re-established.
- Follows redirects only to the same origin, and only a limited number of
  times.
- Rewrites `Host: 127.0.0.1:port` to `localhost:port` for loopback URLs, so
  servers with strict `localhost` allowlists accept the client.

## Interoperability

The SDK's interoperability target is the official Python MCP SDK (see
[Compatibility](../COMPATIBILITY.md)), and the server is exercised with MCP
Inspector and the official [conformance suite](../testing/conformance.md).
Use `McpClient auto` when you don't control the server's version.
