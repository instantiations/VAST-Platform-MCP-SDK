# Clients

`McpClient` is the SDK's MCP client. One client talks to one server over one
transport. It negotiates the protocol, validates every result, and handles
server requests for input. [Your first client](../get-started/first-client.md)
walks through a complete session. This page covers configuration and
lifecycle in more detail.

## Creating a client

```smalltalk
McpClient modern.    "2026-07-28 only"
McpClient legacy.    "initialize handshake (2024-11-05 ... 2025-11-25)"
McpClient auto.      "try modern, fall back to legacy"
```

!!! note
    `McpClient new` defaults to `#legacy`. Prefer the explicit constructors.

`mode:` also accepts a symbol (`#modern`, `#legacy`, `#auto`). Set the mode
before `connect`.

### Identity and capabilities

A default client identifies itself as `VastMcpClient 1.0.0` and declares no
capabilities unless you configure them:

```smalltalk
client
    clientInfo: (EsOrderedDictionary with: 'name' -> 'InvoiceAgent' with: 'version' -> '2.3.0');
    capabilities: ((EsOrderedDictionary new)
        at: 'elicitation' put: EsOrderedDictionary new;
        at: 'sampling' put: EsOrderedDictionary new;
        at: 'roots' put: (EsOrderedDictionary with: 'listChanged' -> false);
        yourself).
```

Installing an `elicitationCallback:`, `samplingCallback:` or `rootsCallback:`
does **not** advertise the matching capability automatically. Declare it in
`capabilities:` as well, so that servers know they may ask.

In modern mode, `clientInfo`, `capabilities` and the protocol version are
attached to every request's `params._meta` (`io.modelcontextprotocol/clientInfo`,
`.../clientCapabilities`, `.../protocolVersion`). In legacy mode, they are sent
once in `initialize`.

## Lifecycle

```text
 new ──► configure (mode, transport, info, capabilities, callbacks)
      ──► connect ──► requests ... ──► close
```

| Message | Effect |
| --- | --- |
| `connect` | Modern: `server/discover`, or adopts `priorDiscover`. Legacy: `initialize` then `notifications/initialized`. Auto: modern first, legacy on any error. Does nothing if already connected. |
| `connectWithHeaders: aDictionary` | Same, with extra HTTP headers for the connect request only. |
| `isConnected` | Whether the client is connected. |
| `protocolVersion`, `serverInfo`, `serverCapabilities` | The negotiation results. |
| `close` | Marks the client disconnected, closes the transport (HTTP sessions are ended with `DELETE`), and resets the negotiated state. |

Always use `ensure:`:

```smalltalk
[client connect.
 ...]
    ensure: [client close].
```

A closed client can be connected again. In modern mode, reconnecting is cheap,
and with `priorDiscover:` it costs no request at all (see
[Your first client](../get-started/first-client.md#2-connect)).

## Operations

| Area | Messages |
| --- | --- |
| Tools | `listTools`, `callTool:arguments:`, `callTool:arguments:progressCallback:`. See [Calling tools](calling-tools.md). |
| Resources | `listResources`, `listResourceTemplates`, `readResource:`. See [Reading resources](reading-resources.md). |
| Prompts | `listPrompts`, `getPrompt:arguments:` |
| Completions | `completePrompt:argument:value:`, `completeResource:argument:value:`, and variants with `context:` |
| Utility | `ping`, `cancelRequest:`, `cancelRequest:reason:` |
| Change events | `listen:do:`. See [Response caching](caching.md#change-notifications). |
| Raw protocol | `sendRequest:params:`, `sendNotification:params:`, and variants with `headers:` |

Before sending, each operation checks that the server advertised the
corresponding capability. If it didn't, the client signals an error without
contacting the server. Test with `serverSupportsCapability: 'prompts'`.

## Results and errors

Results are answered as detached `EsOrderedDictionary` and `Array` trees, so
you can keep or modify them freely. Before returning a result, the client
validates its structure (content blocks, URIs, schemas). A malformed server
response signals an error instead of reaching your code.

| Condition | Signalled as |
| --- | --- |
| JSON-RPC error answered by the server | `McpJsonRpcError` (`code`, `messageText`, `data`) |
| Missing capability, malformed result, not connected, transport failure | `Error` |
| Tool execution failure | Not signalled. The result has `isError: true`. |

```smalltalk
[client getPrompt: 'review' arguments: EsOrderedDictionary new]
    on: McpJsonRpcError
    do: [:ex |
        Transcript show: 'Server refused: [' , ex code printString , '] ' , ex messageText.
        ex return: nil]
```

## Handling server-initiated messages

Servers can send notifications, and in handshake-era sessions also requests,
to the client. Register handlers by method name. Each block receives the
`params` dictionary:

```smalltalk
client onNotification: 'notifications/message' do: [:params |
    Transcript show: (params at: 'level') , ': ' , (params at: 'data') printString].

client onRequest: 'ping' do: [:params | EsOrderedDictionary new].
```

Remove handlers with `removeNotificationHandlerFor:` and
`removeRequestHandlerFor:`. Registering a request handler does not advertise a
capability.

For elicitation, sampling and roots, use the dedicated callbacks rather than
raw handlers, because they also drive the modern multi-round-trip flow:

```smalltalk
client elicitationCallback: [:request :aClient | ...].
client samplingCallback: [:request :aClient | ...].
client rootsCallback: [:request :aClient | ...].
client inputRequiredMaxRounds: 5.    "default 10"
```

See [Interactive input](../advanced/mrtr-interactive-input.md).

## Extensions

Clients and servers can negotiate protocol extensions with `addExtension:`.
An extension is an `McpExtension` with an `identifier` and `settings`, which
are advertised under `capabilities.extensions`.

## Concurrency

A client can be shared between processes. Request ids are assigned under a
mutex, and the transports correlate responses by id. `connect` and `close`
are serialized. Use one client per server. To work with several servers, see
[Session groups](session-groups.md).
