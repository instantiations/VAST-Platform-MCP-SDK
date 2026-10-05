# Interactive input (multi-round-trip requests)

Sometimes a server can't finish a request without help from the client:

| Need | Input request | Client callback |
| --- | --- | --- |
| Ask the **user** something (a confirmation, a missing value) | `elicitation/create` (`McpElicit`) | `elicitationCallback:` |
| Ask the **host's LLM** for a completion | `sampling/createMessage` (`McpSample`) | `samplingCallback:` |
| Ask which **filesystem roots** the client exposes | `roots/list` (`McpListRoots`) | `rootsCallback:` |

The SDK implements this as stateless multi-round-trip requests (MRTR,
SEP-2322). The server doesn't keep a pending request open. Instead:

```text
client                                   server
  │ tools/call {name, arguments}            │
  │────────────────────────────────────────►│ needs 'coupon'
  │ {resultType: 'input_required',          │
  │  inputRequests: {coupon: elicit...},    │
  │  requestState: <sealed token>}          │
  │◄────────────────────────────────────────│
  │ (callback asks the user)                │
  │ tools/call {name, arguments,            │
  │   inputResponses: {coupon: ...},        │
  │   requestState: <same token>}           │
  │────────────────────────────────────────►│ verifies token, runs tool
  │ {content: [...], resultType: 'complete'}│
  │◄────────────────────────────────────────│
```

Because every round is a self-contained request, this works over sessionless
HTTP, behind load balancers, and across server restarts, as long as the
servers share the [request-state key](#securing-requeststate).

## Server side: resolvers

Declare a **resolver** for each argument that may have to be obtained from
the client. The resolver block receives the request context and the arguments
received so far. It answers either a value or an input request:

```smalltalk
server toolRegistry registerTool: (McpBlockTool new
    name: 'delete_file';
    description: 'Delete a file after the user confirms';
    inputSchema: ((EsOrderedDictionary new)
        at: 'type' put: 'object';
        at: 'properties' put: (EsOrderedDictionary with: 'path' -> (EsOrderedDictionary with: 'type' -> 'string'));
        at: 'required' put: #('path');
        yourself);
    resolve: 'confirmation' with: [:context :args |
        McpElicit
            message: 'Really delete ' , (args at: 'path') , '?'
            schema: ((EsOrderedDictionary new)
                at: 'type' put: 'object';
                at: 'properties' put: (EsOrderedDictionary with: 'confirm' -> (EsOrderedDictionary with: 'type' -> 'boolean'));
                at: 'required' put: #('confirm');
                yourself)];
    block: [:args | | answer |
        answer := args at: 'confirmation'.
        ((answer at: 'action' ifAbsent: [nil]) = 'accept'
            and: [(answer at: 'content') at: 'confirm'])
                ifTrue: [self deleteFile: (args at: 'path'). 'Deleted']
                ifFalse: ['Cancelled']];
    yourself).
```

How it works:

1. On the first call, `confirmation` is missing, so the resolver runs and
   answers an `McpElicit`. The tool returns an `input_required` result with
   that request.
2. The client answers. On the retry, the answer is in `inputResponses`, the
   resolver is skipped, and the answer is put into the arguments under the
   resolver's name.
3. The block runs with `args at: 'confirmation'` holding whatever the client
   callback answered.

A resolver can also answer a plain value, in which case no round trip is
needed, e.g. `[:context :args | args at: 'confirm' ifAbsent: [McpElicit message: ...]]`.

### Input request types

```smalltalk
McpElicit message: 'Enter a coupon code'.
McpElicit message: 'Shipping address?' schema: aJsonSchemaDictionary.

McpSample messages: (Array with: ((EsOrderedDictionary new)
    at: 'role' put: 'user';
    at: 'content' put: ((EsOrderedDictionary new)
        at: 'type' put: 'text';
        at: 'text' put: 'Summarize the following log: ...';
        yourself);
    yourself)) maxTokens: 200.

McpListRoots new.
```

!!! warning "One resolver per tool"
    In the current release, a tool with **more than one** resolver doesn't
    complete. Each retry only carries the answer from the latest round, so
    the server keeps asking until the client reaches `inputRequiredMaxRounds`.
    Use at most one resolver per tool. To collect several values, use one
    `McpElicit` with an object schema.

### Writing InputRequiredResults by hand

Tools, resource readers and prompt renderers can also answer an
`InputRequiredResult` themselves. Use `context inputResponses` and
`context requestState` to continue on the next round:

```smalltalk
block: [:args :context |
    (context inputResponses ifNotNil: [:responses | responses at: 'approval' ifAbsent: [nil]])
        ifNil: [
            (EsOrderedDictionary new)
                at: 'resultType' put: 'input_required';
                at: 'inputRequests' put: (EsOrderedDictionary
                    with: 'approval' -> (McpElicit message: 'Approve the transfer?') asInputRequest);
                at: 'requestState' put: 'awaiting-approval';
                yourself]
        ifNotNil: [:approval | self executeTransferWith: approval]]
```

In the modern protocol, the server seals the `requestState` string before
sending it and unseals and verifies it when it comes back. Your code only
sees the plain string.

## Client side: callbacks

```smalltalk
client
    capabilities: ((EsOrderedDictionary new)
        at: 'elicitation' put: EsOrderedDictionary new;
        at: 'sampling' put: EsOrderedDictionary new;
        at: 'roots' put: EsOrderedDictionary new;
        yourself);
    elicitationCallback: [:request :aClient |
        "request: {method: 'elicitation/create', params: {message, requestedSchema}}"
        (self askUser: ((request at: 'params') at: 'message'))
            ifTrue: [EsOrderedDictionary
                with: 'action' -> 'accept'
                with: 'content' -> (EsOrderedDictionary with: 'confirm' -> true)]
            ifFalse: [EsOrderedDictionary with: 'action' -> 'decline']];
    samplingCallback: [:request :aClient |
        self llm complete: ((request at: 'params') at: 'messages')];
    rootsCallback: [:request :aClient |
        Array with: (EsOrderedDictionary
            with: 'uri' -> 'file:///home/me/project'
            with: 'name' -> 'project')].
```

- Each callback receives the input request (`method` and `params`) and the
  client.
- **Whatever the callback answers is passed to the server as is**, and with
  `McpBlockTool` resolvers it ends up as the argument value. Answer the shape
  that the tool expects. The MCP shapes are `{action, content}` for
  elicitation, a message for sampling and a list of roots for `roots/list`.
- Declare the matching `capabilities:` so that servers know you can handle
  them. Installing a callback doesn't declare anything.
- If the server asks for something without a callback installed, the call
  signals an error.
- `inputRequiredMaxRounds:` (default 10) protects against servers that never
  finish.

Callbacks work in all modes and over all transports. `callTool:arguments:`,
`readResource:` and `getPrompt:arguments:` all drive the rounds
automatically.

## Securing `requestState`

The client returns `requestState` to the server unchanged. To prevent
tampering, the server seals it (SEP-2577) as `<base64 claims>.<HMAC-SHA256>`.
The claims bind the state to:

- the method (`tools/call`, `resources/read`, ...) and target (tool name,
  prompt name or URI),
- a SHA-256 digest of the canonical (RFC 8785) arguments,
- the request context's `principal`, if any,
- an expiry time.

A token that has been tampered with, has expired, or is replayed against
another tool, other arguments or another principal is rejected with a JSON-RPC
error (currently `-32603 Internal error`).

!!! note
    The token is **signed, not encrypted**. The client can decode the claims,
    including your state string. Don't put secrets in `requestState`.

By default, every `McpServer` generates a random 32-byte key at startup, and
tokens are valid for 15 minutes. If you run several server instances behind a
load balancer, or want tokens to survive a restart, configure a shared key:

```smalltalk
server requestStateSecurity: (McpRequestStateSecurity
    secretKey: (self secretStore at: 'mcp-request-state-key')
    ttlSeconds: 600).
```

Sealing uses OpenSSL (`OSSslDigest`, `OSSslRandom`) and JSON canonicalization
from `JsonCanonicalizationApp`.

## Handshake-era clients

In legacy (handshake) mode, the same resolvers and callbacks work. The
`input_required` result and the retry are exchanged in the same way, but the
`requestState` isn't sealed.
