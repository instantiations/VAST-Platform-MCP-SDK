# Security

An MCP server gives an LLM the ability to run your code and read your data.
Treat every request as untrusted input, even when it comes from your own
host application, because the arguments were written by a model that may be
following injected instructions.

This page covers the protections built into the SDK and the parts that you
must configure yourself.

## Checklist

| Concern | What to do |
| --- | --- |
| Network exposure | Keep `McpHttpServer host:` at `'127.0.0.1'` unless remote access is required. |
| DNS rebinding | Set `allowedHosts:` explicitly. See below. |
| Browser origins | Only add trusted origins to `allowedOrigins:`. |
| Authentication | For anything beyond localhost, enable bearer authentication **with a `tokenValidator`**. See [OAuth 2.0](oauth2.md). |
| Transport encryption | `McpHttpServer` speaks plain HTTP. Put a TLS-terminating reverse proxy in front of it. |
| File access | Resolve client-supplied paths with `McpPathSecurity safeJoin:with:`. |
| Tool errors | Don't leak internals in exception messages. See [Tools](../servers/tools.md#errors). |
| Destructive tools | Set `annotations:` (`destructiveHint`) and confirm with the user through an [elicitation](mrtr-interactive-input.md). |
| Request size | Lower `maximumRequestSize:` (default 10 MB) if your tools only take small inputs. |
| Multi-instance MRTR | Configure a shared `McpRequestStateSecurity` key. |

## DNS rebinding protection

A malicious web page can make the user's browser resolve its own domain to
`127.0.0.1` and then send requests to a local MCP server. Servers must
therefore check the `Host` and `Origin` headers.

`McpHttpServer` (both `/mcp` and the legacy SSE endpoints) applies:

| Check | Default behavior | Configuration |
| --- | --- | --- |
| **Origin** | A request with an `Origin` header is rejected (`403`) unless the origin is a localhost origin (`localhost`, `127.0.0.1`, `[::1]`, any port, `http` or `https`). Requests without `Origin` (non-browser clients) pass. | `allowedOrigins:` adds origins, compared case-insensitively. |
| **Host** | **Not checked** while `allowedHosts` is empty. | `allowedHosts:` restricts the `Host` header to the listed names, with or without a port. `'*'` allows any. |

!!! warning
    For full protection of a local server, configure the Host check
    explicitly:

```smalltalk
http allowedHosts: #('localhost' '127.0.0.1' '[::1]').
```

A server reachable under a public name lists that name instead:

```smalltalk
http
    host: '0.0.0.0';
    allowedHosts: #('mcp.example.com');
    allowedOrigins: #('https://app.example.com').
```

The client side helps too: `McpHttpClientTransport` sends
`Host: localhost:<port>` for `127.0.0.1` URLs, and its redirect handling only
follows redirects to the same origin.

## Path sandboxing

When a URI variable or tool argument names a file, never concatenate it onto
a directory yourself:

```smalltalk
| path |
path := McpPathSecurity safeJoin: '/srv/app/docs' with: (args at: 'file').
"'/srv/app/docs/guide/intro.md' for 'guide/intro.md'"
```

`safeJoin:with:` signals `McpPathEscapeError` when the relative part:

- contains `..` segments (with `/` or `\` separators),
- contains a null byte,
- is absolute (a leading `/` or `\`, or a drive letter such as `C:`),
- or either part is empty.

```smalltalk
[McpPathSecurity safeJoin: '/srv/app/docs' with: '../etc/passwd']
    on: McpPathEscapeError
    do: [:ex | ex messageText].    "'Path component contains traversal: ../etc/passwd'"
```

The checks are lexical. They don't resolve symbolic links, so don't place
links that point outside the sandbox inside the sandbox directory. Inside a
tool, an `McpPathEscapeError` becomes a tool error result. Inside a resource
reader, it becomes a JSON-RPC error.

## Input validation

- Tool arguments are validated against the `inputSchema` before your code
  runs. The validator enforces types, `required`, `properties`,
  `additionalProperties`, `items`, `enum`, `const` and local `$ref`s.
  Constraints such as `minimum`, `maxLength` or `pattern` are **not**
  enforced. Check them in your code (see [Tools](../servers/tools.md#input-validation)).
- Prompt arguments must be strings, and undeclared arguments are rejected.
- Resource URIs must be absolute.
- Clients validate every server result before handing it to your code.

## Request state integrity

Multi-round-trip `requestState` tokens are HMAC-SHA256-sealed and bound to the
method, target, arguments, principal and an expiry time. The token is
readable by the client, so don't put secrets in it. See
[Interactive input](mrtr-interactive-input.md#securing-requeststate).

## Authentication

Bearer token authentication and OAuth 2.0 metadata are covered in
[OAuth 2.0](oauth2.md). Two points matter enough to repeat here:

- `McpAuthSettings` without a `tokenValidator` accepts **any** non-empty
  token.
- `requiredScopes` are only advertised in the metadata. They aren't checked
  against the token. Check scopes in your `tokenValidator`.
