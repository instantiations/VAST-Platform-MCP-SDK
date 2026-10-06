# VAST MCP SDK

The VAST Platform MCP SDK is a VAST Smalltalk implementation of the
[Model Context Protocol](https://modelcontextprotocol.io) (MCP). It lets you
expose VAST functionality to LLM applications, and lets VAST applications
use tools and data published by any other MCP server.

With the SDK you can:

- **Build MCP servers** that publish tools, resources, resource templates and
  prompts to MCP hosts such as Claude Desktop, MCP Inspector or your own agents.
- **Build MCP clients** that connect to MCP servers written in Smalltalk,
  Python, TypeScript, Go or any other language.
- **Choose a transport** that fits the deployment: in-memory, stdio,
  Streamable HTTP or legacy HTTP+SSE.

## Protocol support

The SDK targets the **`2026-07-28`** MCP specification and remains compatible
with the earlier handshake-based revisions.

| Era | Versions | Lifecycle |
| --- | --- | --- |
| Modern | `2026-07-28` | Sessionless. The client sends `server/discover`, then attaches its capabilities and version to every request in `params._meta`. Change notifications arrive through `subscriptions/listen`. |
| Handshake | `2025-11-25`, `2025-06-18`, `2025-03-26`, `2024-11-05` | Stateful session: `initialize`, then `notifications/initialized`, then requests. |

A client picks its era with a **mode**:

| Mode | Constructor | Behavior |
| --- | --- | --- |
| `#modern` | `McpClient modern` | Uses `2026-07-28` only. |
| `#legacy` | `McpClient legacy` | Uses the `initialize` handshake. |
| `#auto` | `McpClient auto` | Tries modern discovery first and falls back to the handshake if that fails. |

The server needs no configuration for this: one `McpServer` answers clients
from both eras.

## Quickstart

### A server in 30 seconds

Evaluate this in a Workspace. It starts an MCP server on
`http://127.0.0.1:8080/mcp` with one tool:

```smalltalk
| server http |
server := McpServer new
    name: 'Demo';
    version: '1.0.0';
    yourself.

server toolRegistry registerTool: (McpBlockTool new
    name: 'add';
    description: 'Add two integers';
    inputSchema: ((EsOrderedDictionary new)
        at: 'type' put: 'object';
        at: 'properties' put: ((EsOrderedDictionary new)
            at: 'a' put: (EsOrderedDictionary with: 'type' -> 'integer');
            at: 'b' put: (EsOrderedDictionary with: 'type' -> 'integer');
            yourself);
        at: 'required' put: #('a' 'b');
        yourself);
    block: [:args | ((args at: 'a') + (args at: 'b')) printString];
    yourself).

http := McpHttpServer new
    port: 8080;
    mcpServer: server;
    start;
    yourself.
```

Try it with the [MCP Inspector](https://github.com/modelcontextprotocol/inspector):

```bash
npx @modelcontextprotocol/inspector http://127.0.0.1:8080/mcp
```

Evaluate `http stop` when you are done.

### A client in 30 seconds

From a second Workspace, connect to the server above:

```smalltalk
| client result |
client := McpClient modern
    transport: (McpHttpClientTransport url: 'http://127.0.0.1:8080/mcp');
    yourself.
[
    client connect.
    result := client
        callTool: 'add'
        arguments: (EsOrderedDictionary with: 'a' -> 1 with: 'b' -> 2).
    Transcript show: ((result at: 'content') first at: 'text')    "3"
] ensure: [client close].
```

You don't need the network to try it. `McpClient forServer: server mode:
#modern` answers a client that is already connected to `server` through the
in-memory transport.

## Architecture

```text
 ┌─────────────────────── McpServer ────────────────────────┐
 │ toolRegistry              McpToolRegistry     ← McpTool / McpBlockTool
 │ resourceRegistry          McpResourceRegistry ← McpResource / McpBlockResource
 │ resourceTemplateRegistry  McpResourceTemplateRegistry
 │                                               ← McpResourceTemplate / McpBlockResourceTemplate
 │ promptRegistry            McpPromptRegistry   ← McpPrompt / McpBlockPrompt
 │ subscriptionBus           McpSubscriptionBus  (list_changed / updated)
 │ requestStateSecurity      McpRequestStateSecurity (HMAC-sealed requestState)
 └────────────────────────────▲─────────────────────────────┘
                              │ McpJsonRpcDispatcher (JSON-RPC 2.0)
        ┌─────────────────────┼──────────────────────┬────────────────────┐
  McpHttpServer         McpStdioServer     McpInMemoryClientTransport  McpSseServerTransport
  (Streamable HTTP,     (stdin/stdout)     (direct dispatch)           (legacy /sse + /messages)
   SST servlets)
        ▲                     ▲                      ▲                    ▲
  McpHttpClientTransport  McpStdioClientTransport    │       McpLegacySseClientTransport
        └─────────────────────┴───────── McpClient ──┴────────────────────┘
                                 (#modern / #legacy / #auto)
```

The **server** side is transport-neutral. You register tools, resources and
prompts on an `McpServer`, then host that server through one or more
transports. The same `McpServer` instance can be served over HTTP and stdio,
and used in-memory, at the same time.

The **client** side mirrors this. An `McpClient` holds one transport, handles
negotiation, validates every result it receives and drives multi-round-trip
input requests through callbacks that you provide.

## Applications

The SDK ships as the `MCP SDK` configuration map:

| Application | Contents |
| --- | --- |
| `McpApp` | Core model. Sub-applications `McpProtocol` (client, server, dispatcher, caching, session groups, request-state security), `McpTools`, `McpResources` (including RFC 6570 `McpUriTemplate` and `McpPathSecurity`) and `McpPrompts`. Also contains the in-memory and stdio transports. |
| `JsonCanonicalizationApp` | RFC 8785 JSON canonicalization, used by the core. |
| `McpHttpApp` | Streamable HTTP and legacy SSE, client and server (`McpHttpClientSubApp`, `McpHttpServerSubApp`). Includes DNS-rebinding protection and `McpAuthSettings`. |
| `McpHttpOAuth2App` | OAuth 2.0 protected-resource metadata (`McpAuthMetadataServlet`, `McpOAuth2ProtectedHttpServer`) and client token acquisition (`McpOAuth2ClientProvider`). |
| `McpTestsApp`, `McpHttpTestsApp`, `McpHttpOAuth2TestsApp` | SUnit suites and conformance fixtures (`McpConformanceServer`, `McpConformanceClient`). |

## Where to go next

- [Your first server](get-started/first-server.md): tools, resources and
  hosting, step by step.
- [Your first client](get-started/first-client.md): connect, discover and call.
- [Compatibility](COMPATIBILITY.md): protocol targets and the upstream Python
  SDK reference.
