# In-memory

`McpInMemoryClientTransport` connects an `McpClient` directly to an `McpServer`
in the same image. No socket, process or byte stream is involved, but every
message still goes through the full JSON-RPC dispatcher, the server's
validation and the client's result validation. Use it for:

- **unit tests** of tools, resources and prompts,
- **in-image agents** that use the image's own MCP server,
- **trying out** a server in a Workspace before you host it.

## Usage

The shortcut creates the transport and connects:

```smalltalk
| client |
client := McpClient forServer: server mode: #modern.
[client callTool: 'add' arguments: (EsOrderedDictionary with: 'a' -> 1 with: 'b' -> 2)]
    ensure: [client close].
```

`McpClient forServer: server` without a mode uses `#auto`.

The explicit form gives you a chance to configure the client before it
connects:

```smalltalk
| client |
client := McpClient legacy
    transport: (McpInMemoryClientTransport server: server);
    capabilities: (EsOrderedDictionary with: 'elicitation' -> EsOrderedDictionary new);
    elicitationCallback: [:request :aClient | 'yes'];
    yourself.
client connect.
```

All three modes work in-memory, so you can test both protocol eras of your
server without starting HTTP.

## What is supported

| Feature | In-memory |
| --- | --- |
| Requests, notifications, pagination | yes |
| Progress notifications (`reportProgress:`) | yes |
| Multi-round-trip input (elicitation, sampling, roots) | yes |
| Per-call headers (`callTool:arguments:headers:`) | accepted but ignored |
| `listen:do:` change notifications | yes |
| HTTP-level checks (Host/Origin, bearer auth, request size) | no: these live in the HTTP transport |

Results are serialized to detached copies at the boundary, so the client and
server never share mutable objects, just as over a real wire.

## Testing with SUnit

```smalltalk
TestCase subclass: #InventoryToolTest
    instanceVariableNames: 'server client'
    classVariableNames: ''
    poolDictionaries: ''

InventoryToolTest >> setUp
    server := McpServer new.
    server toolRegistry registerTool: InventoryTools stockLevelTool.
    client := McpClient forServer: server mode: #modern

InventoryToolTest >> tearDown
    client close

InventoryToolTest >> testStockLevel
    | result |
    result := client callTool: 'stock_level' arguments: (EsOrderedDictionary with: 'sku' -> 'A-17').
    self deny: (result at: 'isError').
    self assert: ((result at: 'structuredContent') at: 'onHand') equals: 42

InventoryToolTest >> testUnknownSku
    | result |
    result := client callTool: 'stock_level' arguments: (EsOrderedDictionary with: 'sku' -> 'nope').
    self assert: (result at: 'isError')
```

To exercise the dispatcher without a client, create the transport with a
specific dispatcher: `McpInMemoryClientTransport server: server dispatcher:
anMcpJsonRpcDispatcher`.
