# Request context

Every request that the server handles gets an `McpServerRequestContext`. It
describes who is calling and how, and gives tools, resources and prompts a
channel back to the client for progress reports. Declare an extra block
argument to receive it:

```smalltalk
McpBlockTool new
    name: 'whoami';
    inputSchema: (EsOrderedDictionary with: 'type' -> 'object');
    block: [:args :context |
        'Protocol ' , context protocolVersion , ', client '
            , ((context clientInfo ifNil: [Dictionary new]) at: 'name' ifAbsent: ['unknown'])];
    yourself.
```

| Primitive | Block that receives the context |
| --- | --- |
| `McpBlockTool` | `[:args :context \| ...]` |
| `McpBlockResource` | `[:context \| ...]` |
| `McpBlockResourceTemplate` | `[:uri :context \| ...]` |
| `McpBlockPrompt` | `[:args :context \| ...]` |

A context lives for one request only. Don't store it.

!!! warning
    Over the [legacy HTTP+SSE transport](../transports/sse.md), the context
    is `nil`. If a primitive may be served over that transport, guard its
    use: `context ifNotNil: [:ctx | ...]`.

## What the context knows

| Accessor | Contents |
| --- | --- |
| `protocolVersion` | Negotiated version, e.g. `'2026-07-28'`. |
| `clientInfo` | The client's `name` and `version`. |
| `clientCapabilities` | Capabilities declared by the client, e.g. whether it supports elicitation. |
| `principal` | The authenticated caller, if your transport or authentication sets one. |
| `session`, `sessionId` | The session for handshake-era connections. `nil` in the sessionless modern protocol. |
| `transportRequest` | The underlying request, e.g. the `SstHttpServletRequest` over HTTP. |
| `metadata` | A dictionary for request-scoped data. Resource templates store their extracted URI `variables` here. |
| `progressToken` | The client's progress token, if it asked for progress. |
| `logLevel` | The minimum log level that the client requested, or `nil`. |
| `inputResponses`, `requestState` | Multi-round-trip state. See [Interactive input](../advanced/mrtr-interactive-input.md). |

In the modern protocol, `clientInfo` and `clientCapabilities` come from the
`io.modelcontextprotocol/*` entries in each request's `params._meta`. In
handshake-era sessions they come from `initialize`.

Use `clientCapabilities` to adapt your behavior, for example to avoid asking
for input from a client that can't answer:

```smalltalk
((context clientCapabilities ifNil: [Dictionary new]) includesKey: 'elicitation')
    ifFalse: [McpToolError signal: 'This tool requires a client that supports elicitation'].
```

## Reporting progress

```smalltalk
block: [:args :context | | files |
    files := self filesToImport.
    files doWithIndex: [:file :index |
        self import: file.
        context
            reportProgress: index
            total: files size
            message: 'Imported ' , file name].
    'Done']
```

`reportProgress:`, `reportProgress:total:` and
`reportProgress:total:message:` send `notifications/progress` to the caller.
If the client didn't supply a progress token, they do nothing, so you can call
them unconditionally.

Progress is delivered by the in-memory transport and by Streamable HTTP. Over
HTTP, the response switches to an SSE stream, and the progress notifications
precede the final result. On the client, use
`callTool:arguments:progressCallback:`.

## Logging

The modern protocol (SEP-2575) allows a server to send `notifications/message`
log entries only when the request asked for them through
`io.modelcontextprotocol/logLevel`. `context canEmitLog` answers whether that
is the case, and `context logLevel` gives the requested minimum level.

!!! note
    The SDK records the requested level but doesn't yet offer a helper that
    sends `notifications/message`. Log to the Transcript or to your own
    logging framework for now. Never write to standard output in a server
    that is hosted over stdio, because stdout carries the protocol.

## Customizing the context over HTTP

`McpHttpServer` creates a fresh `McpServerRequestContext` for every request.
To attach information from the HTTP request, such as an authenticated user,
install a factory. It receives the servlet request and the session (`nil` for
modern requests):

```smalltalk
http requestContextFactory: [:request :session |
    McpServerRequestContext new
        principal: (self userForRequest: request);
        yourself].
```

The `principal` is also bound into sealed multi-round-trip `requestState`, so
a continuation can't be replayed under a different identity.

!!! note
    When bearer authentication is enabled (see [OAuth 2.0](../advanced/oauth2.md)),
    the transport validates the token but does **not** copy the validated
    principal into the request context. If your tools need the caller's
    identity, derive it in the `requestContextFactory`, for example by
    reading the `Authorization` header of `request`.
