# Your first client

`McpClient` connects to any MCP server, whether it runs in this image, in
another VAST image, or in Python, TypeScript or Go. This guide connects to the
server from [Your first server](first-server.md), finds out what it offers,
and calls it.

## 1. Choose a mode and a transport

A client has a **mode**, which selects the protocol era, and a **transport**,
which carries the messages:

```smalltalk
| client |
client := McpClient auto
    transport: (McpHttpClientTransport url: 'http://127.0.0.1:8080/mcp');
    yourself.
```

| Mode | Use when |
| --- | --- |
| `McpClient modern` | The server supports `2026-07-28`. This is the cheapest option: there is no handshake and no session state. |
| `McpClient legacy` | The server only supports the `initialize` handshake (`2024-11-05` to `2025-11-25`). |
| `McpClient auto` | You don't know which era the server supports. The client tries `server/discover` and falls back to the handshake if that fails. |

Transports:

| Transport | Constructor |
| --- | --- |
| Streamable HTTP | `McpHttpClientTransport url: 'http://host:port/mcp'` |
| Subprocess stdio | `McpStdioClientTransport command: 'python' arguments: #('-u' 'server.py')` |
| Legacy HTTP+SSE | `McpLegacySseClientTransport`. See [Legacy HTTP+SSE](../transports/sse.md). |
| In-memory | `McpInMemoryClientTransport server: anMcpServer` |

For an in-image server, the shortcut `McpClient forServer: server mode: #modern`
creates the in-memory transport and connects in one step.

## 2. Connect

```smalltalk
client connect.

client protocolVersion.     "'2026-07-28', or e.g. '2025-11-25' after a fallback"
client serverInfo.          "name and version, e.g. Demo 1.0.0"
client serverCapabilities.  "tools, prompts, resources, ..."
```

`connect` does nothing if the client is already connected. Always pair it with
`close`, which ends the session (for handshake-era HTTP it sends a session
`DELETE`) and shuts down the transport:

```smalltalk
[client connect.
 "... work ..."]
    ensure: [client close].
```

!!! tip "Skip discovery on reconnect"
    In modern mode, store the `server/discover` result and pass it back with
    `client priorDiscover: aResult` before you connect. The client then skips
    the discovery round trip.

The client doesn't keep the discover result after `connect`. Request it
explicitly once, then reuse it on later connections:

```smalltalk
| url discover client result |
url := 'http://127.0.0.1:8080/mcp'.

"First connection: fetch and keep the discovery result"
client := McpClient modern
    transport: (McpHttpClientTransport url: url);
    yourself.
[client connect.
    discover := client sendRequest: 'server/discover' params: EsOrderedDictionary new]
    ensure: [client close].

"Later connections: reuse it; connect sends no server/discover request"
client := McpClient modern
    priorDiscover: discover;
    transport: (McpHttpClientTransport url: url);
    yourself.
[client connect.
    result := client callTool: 'add' arguments: (EsOrderedDictionary with: 'a' -> 1 with: 'b' -> 2).
    Transcript show: ((result at: 'content') first at: 'text')]
    ensure: [client close].
```

The capabilities and server info are taken from the stored result. If
the server may have changed, for example after a redeploy, discard the
stored result and connect without it.

## 3. Discover what the server offers

```smalltalk
client listTools.              "Array of tool definitions"
client listResources.
client listResourceTemplates.
client listPrompts.
```

Each list method fetches every page (following `nextCursor`), validates each
definition and answers an `Array` of dictionaries. Your code never shares
mutable state with the transport. If the server didn't advertise the
capability, for example `prompts`, the client signals an error before it sends
anything. Check first with `client serverSupportsCapability: 'prompts'`.

```smalltalk
client listTools collect: [:each | each at: 'name'].    "#('add')"
```

`listTools` also caches each tool's input and output schemas. The client uses
them to validate `structuredContent` in later results.

## 4. Call a tool

```smalltalk
| result |
result := client
    callTool: 'add'
    arguments: (EsOrderedDictionary with: 'a' -> 40 with: 'b' -> 2).

(result at: 'isError') ifFalse: [
    Transcript show: ((result at: 'content') first at: 'text')].    "42"
```

Failures come back in two different ways:

| Failure | How it arrives |
| --- | --- |
| The tool ran but failed, or its arguments didn't match the schema | Normal result with `isError: true`. The message is in `content`. |
| Protocol error, such as an unknown tool, invalid params or a missing capability | `McpJsonRpcError` is signalled, with `code` and `messageText`. |

```smalltalk
[client callTool: 'nope' arguments: EsOrderedDictionary new]
    on: McpJsonRpcError
    do: [:ex | ex return: ex code -> ex messageText].
"-32602 -> 'Unknown tool: nope'"
```

If the tool has an `outputSchema`, read the typed value from
`result at: 'structuredContent'`. A long-running tool can stream progress:

```smalltalk
client
    callTool: 'import'
    arguments: EsOrderedDictionary new
    progressCallback: [:progress :total :message |
        Transcript show: progress printString , '/' , total printString].
```

The progress block is evaluated with `cull:`, so it can take one to four
arguments: progress, total, message and the raw notification params.

## 5. Read resources

```smalltalk
| contents |
contents := (client readResource: 'demo://motd') at: 'contents'.
contents first at: 'text'.    "'Welcome to VAST MCP'"

((client readResource: 'greeting://Smalltalker') at: 'contents') first at: 'text'.
"'Hello, Smalltalker!'"
```

Templated and static resources are read the same way, with a concrete absolute
URI. Binary entries have a Base64 `'blob'` key instead of `'text'`.

## 6. Get a prompt

```smalltalk
(client getPrompt: 'review' arguments: (EsOrderedDictionary with: 'language' -> 'smalltalk'))
    at: 'messages'.
```

## 7. Answer server requests for input

A server can pause a tool call to ask the user for input (elicitation), ask
the host's model for a completion (sampling), or ask which filesystem roots
are available. The client handles these automatically if you install
callbacks:

```smalltalk
client elicitationCallback: [:request :aClient |
    "Ask the user. Answer the content for the server."
    'DISCOUNT2026'].
client samplingCallback: [:request :aClient | "call your LLM here" ].
client rootsCallback: [:request :aClient | #() ].
```

The client resends the original request with your answers and keeps going
until the server returns a final result, for at most `inputRequiredMaxRounds`
rounds. See [Interactive input](../advanced/mrtr-interactive-input.md).

## 8. React to changes

```smalltalk
client
    listen: (EsOrderedDictionary with: 'toolsListChanged' -> true)
    do: [:method :params | Transcript show: 'Changed: ' , method].
```

The client also drops matching entries from its response cache when a
notification arrives. See [Response caching](../clients/caching.md).

## Putting it together

```smalltalk
| client tools sum |
client := McpClient auto
    transport: (McpHttpClientTransport url: 'http://127.0.0.1:8080/mcp');
    yourself.
[
    client connect.
    Transcript show: 'Connected to ' , (client serverInfo at: 'name') ,
        ' using ' , client protocolVersion.
    tools := client listTools collect: [:each | each at: 'name'].
    Transcript show: 'Tools: ' , tools printString.
    sum := client callTool: 'add'
        arguments: (EsOrderedDictionary with: 'a' -> 1 with: 'b' -> 2).
    Transcript show: 'add(1, 2) = ' , ((sum at: 'content') first at: 'text')
] ensure: [client close].
```

## Next steps

- [Clients](../clients/index.md): modes, lifecycle and custom request handlers.
- [Session groups](../clients/session-groups.md): combine several servers
  behind one client interface.
- [stdio](../transports/stdio.md): drive a Python or Node MCP server from
  Smalltalk.
