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

### The OAuth 2.0 client provider

`McpOAuth2ClientProvider` implements the client side of the
[MCP authorization flow](https://modelcontextprotocol.io/specification/2026-07-28/basic/authorization).
Given only the MCP server's URL and your OAuth client registration, it
discovers the authorization server, obtains an access token (if necessary by
letting the user sign in through the browser), refreshes it when it expires,
and hands it to the HTTP transport for every request.

This example connects to GitHub's remote MCP server:

```smalltalk
| authProvider transport client tools |

"1. Configure the OAuth provider"
authProvider := McpOAuth2ClientProvider new
    serverUrl: 'https://api.githubcopilot.com/mcp';
    clientId: '<client id of your GitHub OAuth app>';
    clientSecret: '<client secret of your GitHub OAuth app>';
    scope: 'repo user';
    callbackPort: 9999;
    yourself.

"2. Configure standard transport with the provider"
transport := McpHttpClientTransport url: 'https://api.githubcopilot.com/mcp' sstAsUrl.
transport auth: authProvider.

"3. Connect client"
client := McpClient modern.
client transport: transport.

[
    client connect.
    tools := client listTools.
    tools inspect.
] ensure: [
    client close
].
```

On `connect`, the browser opens on GitHub's sign-in and consent page. After
you approve, GitHub redirects to `http://localhost:9999/callback`, where the
provider picks up the authorization code and exchanges it for tokens. Then the
`server/discover` request is sent with `Authorization: Bearer <token>`.

Before this works, register an OAuth app with the authorization server (for
GitHub: *Settings › Developer settings › OAuth Apps*) and set its callback URL
to `http://localhost:<callbackPort>/callback`, here
`http://localhost:9999/callback`.

#### Configuration

| Selector | Default | Purpose |
| --- | --- | --- |
| `serverUrl:` | the transport's URL | The MCP endpoint, used to find the protected resource metadata. `auth:` fills it in from the transport when it is unset. `McpOAuth2ClientProvider newForServerUrl: aUrl` sets it at creation. Accepts a `String` or an `SstUrl`. |
| `clientId:` | required | Client id of your registration with the authorization server. |
| `clientSecret:` | `nil` | Client secret, for confidential clients. It also enables the client-credentials grant (see below). |
| `scope:` | `nil` | Space-separated scopes to request, e.g. `'repo user'`. |
| `callbackPort:` | `3030` | Local port for the redirect listener. The redirect URI is `http://localhost:<port>/callback`. |
| `redirectHandler:` | Windows `start` | One-argument block that receives the authorization URL and must bring it to the user. |
| `credentials:` | `nil` | The current `SstOAuth2Credentials`. Read it to keep tokens, set it to reuse them, or set it to `nil` to force a new sign-in. |

`transport auth: aProvider` installs the provider as the transport's
`tokenProvider`, so it can be combined with every other transport setting.
Only `McpHttpClientTransport` (Streamable HTTP) supports `auth:`, `bearerToken:`
and `tokenProvider:`. The legacy SSE client transport has no token support.

#### How a token is obtained

Before each request, the transport asks the provider for
`validAccessToken`:

1. **Cached token:** an unexpired access token is reused.
2. **Refresh:** an expired token with a refresh token is refreshed at the token
   endpoint. If the refresh fails, the provider falls back to step 3.
3. **Discovery and grant:**
    1. `GET <server origin>/.well-known/oauth-protected-resource<server path>`
       ([RFC 9728](https://www.rfc-editor.org/rfc/rfc9728)), e.g.
       `https://api.githubcopilot.com/.well-known/oauth-protected-resource/mcp`.
       Its `authorization_servers` names the issuer. The first entry is used.
    2. `GET <issuer origin>/.well-known/oauth-authorization-server<issuer path>`
       ([RFC 8414](https://www.rfc-editor.org/rfc/rfc8414)), which gives the
       `authorization_endpoint`, `token_endpoint` and `grant_types_supported`.
    3. The grant is chosen as follows:
        - **Client credentials** if `clientId` and `clientSecret` are set, and
          either the server lists `client_credentials` in
          `grant_types_supported`, or it publishes neither grant types nor an
          authorization endpoint. No user is involved, which suits services
          and agents running unattended.
        - **Authorization code** otherwise: the interactive browser sign-in
          described above.

The discovery requests and token exchanges use SST's HTTP client and OAuth 2.0
support (`SstOAuth2App`). `https` endpoints require OpenSSL.

#### The authorization code flow

For the authorization code grant, the provider:

1. starts an `McpOAuth2CallbackServer` on `callbackPort`,
2. builds the authorization URL (client id, scope, redirect URI and a random
   `state`) and passes it to the `redirectHandler`,
3. waits up to **300 seconds** for the browser to hit
   `http://localhost:<callbackPort>/callback`. The page shows *Success*, and
   on timeout the request signals `Timeout waiting for OAuth callback`,
4. exchanges the code at the token endpoint, sending `clientSecret` if it is
   set,
5. stops the callback listener shortly afterwards.

The default `redirectHandler` opens the URL in the default browser with the
Windows `start` command. On Linux or macOS, or in a headless image, install
your own:

```smalltalk
"macOS"
authProvider redirectHandler: [:authorizationUrl |
    OsProcessStarter startShell: { 'open'. '"%1"' bindWith: authorizationUrl asString }].

"Linux"
authProvider redirectHandler: [:authorizationUrl |
    OsProcessStarter startShell: { 'xdg-open'. '"%1"' bindWith: authorizationUrl asString }].

"Headless: let the operator open it"
authProvider redirectHandler: [:authorizationUrl |
    Transcript show: 'Open this URL to sign in: ' , authorizationUrl asString; cr].
```

The callback listener binds to the local machine. The browser that completes
the sign-in must run on the same machine as the image.

#### Token lifetime and reuse

The provider keeps its credentials in memory for as long as it lives. Reuse
the same provider (or its `credentials`) across reconnects to avoid signing in
again:

```smalltalk
| savedCredentials otherProvider |
savedCredentials := authProvider credentials.

"later, e.g. for a new client"
otherProvider := McpOAuth2ClientProvider new
    serverUrl: 'https://api.githubcopilot.com/mcp';
    clientId: '<client id>';
    clientSecret: '<client secret>';
    credentials: savedCredentials;
    yourself.
```

Credentials contain bearer and refresh tokens. If you persist them, store them
encrypted, never in source code or the image's change log.

#### Limitations

- **No dynamic client registration.** The client must be registered in
  advance (`clientId:`).
- **No automatic retry on `401`.** If the server rejects a token that hasn't
  expired yet (revoked, wrong audience), the request signals
  `HTTP Error: 401 Unauthorized`. Set `authProvider credentials: nil` and
  reconnect to sign in again.
- **Only the first** authorization server listed by the resource is used.
- The callback timeout (300 seconds) and the callback path (`/callback`) are
  fixed.
