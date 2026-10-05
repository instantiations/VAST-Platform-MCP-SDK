# OAuth 2.0 and bearer authentication

MCP's authorization model is standard OAuth 2.0. The MCP server is a
*protected resource* that accepts bearer access tokens issued by a separate
*authorization server*, for example Keycloak, Entra ID, Auth0 or your own.
Clients discover the authorization server through the server's
**Protected Resource Metadata** ([RFC 9728](https://www.rfc-editor.org/rfc/rfc9728))
and then obtain tokens from it.

| Piece | Class | Application |
| --- | --- | --- |
| Token check on every request | `McpAuthSettings` on `McpHttpServer` | `McpHttpServerSubApp` |
| `/.well-known/oauth-protected-resource` and `/.well-known/oauth-authorization-server` | `McpOAuth2ProtectedHttpServer`, `McpAuthMetadataServlet` | `McpHttpOAuth2App` |
| Client-side discovery and token acquisition | `McpOAuth2ClientProvider`, `McpOAuth2CallbackServer` | `McpHttpOAuth2App` |

`McpHttpOAuth2App` builds on SST's OAuth 2.0 support (`SstOAuth2App`).

## Protecting a server

```smalltalk
| settings http |
settings := McpAuthSettings new
    issuerUrl: 'https://auth.example.com/realms/mcp';
    resourceServerUrl: 'https://mcp.example.com/mcp';
    requiredScopes: #('mcp:tools');
    validateTokenResource: true;
    tokenValidator: [:token | self verifyAccessToken: token];
    yourself.

http := McpOAuth2ProtectedHttpServer new
    port: 8080;
    mcpServer: server;
    authSettings: settings;
    allowedHosts: #('mcp.example.com');
    start;
    yourself.
```

Every request to `/mcp` (and to the legacy SSE endpoints) must then carry
`Authorization: Bearer <token>`. Missing or rejected tokens get
`401 Unauthorized` with a `WWW-Authenticate: Bearer ...` header that names the
issuer as realm.

Use plain `McpHttpServer` with `authSettings:` if you only need the token
check. `McpOAuth2ProtectedHttpServer` additionally serves the discovery
metadata.

### The token validator

```smalltalk
tokenValidator: [:token |
    "Answer a principal when the token is valid, nil to reject it."
    | claims |
    claims := self jwtVerifier verify: token.    "signature, issuer, expiry"
    claims isNil
        ifTrue: [nil]
        ifFalse: [
            ((claims at: 'scope' ifAbsent: ['']) subStrings includes: 'mcp:tools')
                ifTrue: [claims]
                ifFalse: [nil]]]
```

- Answer any non-nil object (the *principal*) to accept the token, and `nil`
  to reject it. Errors signalled inside the block also reject.
- Verify the signature, issuer, expiry **and scopes** here.
  `requiredScopes` is only advertised in the metadata, not enforced.
- With `validateTokenResource: true`, the principal must be a dictionary
  whose `'resource'` entry equals `resourceServerUrl`. This is the RFC 8707
  audience binding, which prevents tokens minted for another service from
  being replayed against yours. It requires `resourceServerUrl`.
- For JWTs, consider the VAST Platform's `SstSecurityJWTApp` and
  `SstOIDCApp`. For opaque tokens, call the authorization server's
  introspection endpoint.

!!! danger
    Without a `tokenValidator`, `McpAuthSettings` accepts **any** non-empty
    bearer token. Always install a validator.

!!! note
    If `resourceServerUrl` is set and `validateTokenResource:` isn't, an
    `McpDeprecationWarning` is written to the Transcript once: the default
    will change to `true` in a future major version. Set it explicitly.

!!! note
    The validated principal isn't copied into the
    [request context](../servers/context.md). To make the caller's identity
    available to tools, derive it in a `requestContextFactory:`.

### Discovery metadata

`McpOAuth2ProtectedHttpServer` serves:

| Path | Content |
| --- | --- |
| `/.well-known/oauth-protected-resource` (and below it, e.g. `.../mcp`) | `resource` (= `resourceServerUrl`), `authorization_servers` (= `issuerUrl`), `scopes_supported` (= `requiredScopes`) |
| `/.well-known/oauth-authorization-server` | `McpAuthSettings authorizationServerMetadata`, derived from `issuerUrl` |

Clients that follow the MCP authorization specification start here.

## Authenticating a client

### Static or self-managed tokens

```smalltalk
(McpHttpClientTransport url: 'https://mcp.example.com/mcp')
    bearerToken: 'eyJhbGciOi...';
    yourself.

(McpHttpClientTransport url: 'https://mcp.example.com/mcp')
    tokenProvider: [self tokenCache currentAccessToken];
    yourself.
```

The `tokenProvider` block is evaluated for every request, so it can renew
tokens transparently.

### OAuth 2.0 discovery with `McpOAuth2ClientProvider`

```smalltalk
| provider transport client |
provider := (McpOAuth2ClientProvider newForServerUrl: 'https://mcp.example.com/mcp')
    clientId: 'vast-agent';
    clientSecret: 'secret';    "for the client-credentials grant"
    scope: 'mcp:tools';
    yourself.

transport := (McpHttpClientTransport url: 'https://mcp.example.com/mcp')
    auth: provider;
    yourself.

client := McpClient auto transport: transport; yourself.
[client connect.
 client listTools]
    ensure: [client close].
```

`auth:` installs the provider as the transport's `tokenProvider`. Before each
request, the provider answers a valid access token:

1. A cached, unexpired token is reused.
2. An expired token is refreshed with its refresh token, if it has one.
3. Otherwise, the provider runs full discovery:
    - it fetches `/.well-known/oauth-protected-resource/<path>` from the MCP
      server ([RFC 9728](https://www.rfc-editor.org/rfc/rfc9728)),
    - it fetches the authorization server metadata of the first entry in
      `authorization_servers` ([RFC 8414](https://www.rfc-editor.org/rfc/rfc8414)),
    - it uses the **client-credentials** grant when a `clientSecret` is set and
      the server supports it, and the interactive **authorization code** grant
      otherwise.

For the authorization code grant, the provider starts an
`McpOAuth2CallbackServer` on `http://localhost:3030/callback` (change it with
`callbackPort:`), opens the authorization URL, waits for the redirect and
exchanges the code for tokens.

The default `redirectHandler` opens the URL with the Windows `start` command.
On other platforms, or in headless images, install your own:

```smalltalk
provider redirectHandler: [:authorizationUrl |
    Transcript show: 'Open this URL to sign in: ' , authorizationUrl asString; cr].
```

!!! note
    The client must already be registered with the authorization server
    (`clientId:`). Dynamic client registration is not performed. Register
    `http://localhost:<callbackPort>/callback` as a redirect URI.

!!! note
    The token is obtained before each request. A `401` response isn't retried
    automatically: it signals an error (`HTTP Error: 401 Unauthorized`) on the
    client. Reconnect, or clear `provider credentials: nil`, to force a new
    token.
