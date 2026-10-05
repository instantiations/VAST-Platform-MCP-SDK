# Your first server

This guide builds a small MCP server step by step. It publishes:

- a **tool** that the model can call (`add`),
- a static **resource** that the model can read (`demo://motd`),
- a **resource template** that maps a URI pattern to data (`greeting://{name}`).

Then it hosts the server over Streamable HTTP and inspects it with MCP
Inspector. Each step is a Workspace snippet. Keep the variables in one
Workspace so later steps can use earlier results.

## 1. Create the server

```smalltalk
| server |
server := McpServer new
    name: 'Demo';
    version: '1.0.0';
    yourself.
```

`name` and `version` are sent to clients as `serverInfo`. The defaults are
`'VastMcpServer'` and `'1.0.0'`. A new `McpServer` comes with empty registries
for tools, resources, resource templates and prompts.

## 2. Add a tool

A tool is an action that the model can invoke. The simplest way to define one
is `McpBlockTool`: a name, a JSON Schema describing the arguments, and a block
that does the work.

```smalltalk
server toolRegistry registerTool: (McpBlockTool new
    name: 'add';
    title: 'Add numbers';
    description: 'Add two integers and return the sum';
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
```

How the call is handled:

- **Arguments are validated** against `inputSchema` before your block runs. If
  validation fails, for example because `b` is missing, the call returns a
  tool error result (`isError: true`) with a readable message. Your block never
  sees invalid input.
- **The block's arguments are optional.** The block is evaluated with `cull:`,
  so it can take no arguments, the arguments dictionary, or the dictionary and
  an `McpServerRequestContext` (see [Request context](../servers/context.md)).
- **The return value is normalized.** A `String` becomes a single text content
  block. Other values are serialized as JSON text. A dictionary that already
  has a `'content'` key is passed through unchanged.
- **Errors become tool errors.** If the block signals an error, the client
  receives `isError: true` and the exception's `messageText`. Use
  `McpToolError signal: 'Order not found'` for failures that the model should
  see.

!!! warning
    Because every `Error` is turned into a tool result, the `messageText` of
    unexpected exceptions reaches the client. Catch and rephrase exceptions
    whose message might reveal internals.

[Tools](../servers/tools.md) covers `outputSchema` and `structuredContent`,
annotations, and resolvers that request input from the user.

## 3. Add a resource

A resource is read-only data addressed by an absolute URI. `McpBlockResource`
evaluates its block whenever a client reads the resource. The block must
answer an MCP `ReadResourceResult`, which is a dictionary with a `'contents'`
array:

```smalltalk
server resourceRegistry registerResource: (McpBlockResource new
    uri: 'demo://motd';
    name: 'motd';
    description: 'Message of the day';
    mimeType: 'text/plain';
    block: [
        EsOrderedDictionary with: 'contents' -> (Array with: ((EsOrderedDictionary new)
            at: 'uri' put: 'demo://motd';
            at: 'mimeType' put: 'text/plain';
            at: 'text' put: 'Welcome to VAST MCP';
            yourself))];
    yourself).
```

For binary data, use a Base64 `'blob'` entry instead of `'text'`. See
[Resources](../servers/resources.md).

## 4. Add a resource template

A resource template publishes a whole family of URIs. It uses an
[RFC 6570](https://www.rfc-editor.org/rfc/rfc6570) URI template, and the
`readBlock` receives the concrete URI that the client requested.
`McpUriTemplate` extracts the variables from it:

```smalltalk
server resourceTemplateRegistry registerTemplate: (McpBlockResourceTemplate new
    uriTemplate: 'greeting://{name}';
    name: 'greeting';
    description: 'A personalised greeting';
    mimeType: 'text/plain';
    readBlock: [:uri | | vars |
        vars := (McpUriTemplate template: 'greeting://{name}') matchUri: uri.
        EsOrderedDictionary with: 'contents' -> (Array with: ((EsOrderedDictionary new)
            at: 'uri' put: uri;
            at: 'mimeType' put: 'text/plain';
            at: 'text' put: 'Hello, ' , (vars at: 'name') , '!';
            yourself))];
    yourself).
```

Clients list templates with `resources/templates/list`, then read concrete
URIs such as `greeting://Smalltalker` with an ordinary `resources/read`.

## 5. Test it in the image

Before you open a port, check the server with an in-memory client. Nothing is
serialized onto a network, but each request goes through the full JSON-RPC
dispatcher and validation:

```smalltalk
| client |
client := McpClient forServer: server mode: #modern.
[
    (client listTools collect: [:each | each at: 'name']) inspect.
    (client callTool: 'add'
        arguments: (EsOrderedDictionary with: 'a' -> 40 with: 'b' -> 2)) inspect.
    (client readResource: 'greeting://Smalltalker') inspect
] ensure: [client close].
```

The `add` result looks like this:

```json
{
  "content": [{ "type": "text", "text": "42" }],
  "isError": false,
  "resultType": "complete",
  "_meta": { "io.modelcontextprotocol/serverInfo": { "name": "Demo", "version": "1.0.0" } }
}
```

## 6. Host it over Streamable HTTP

```smalltalk
| http |
http := McpHttpServer new
    host: '127.0.0.1';
    port: 8080;
    mcpServer: server;
    start;
    yourself.
```

The server now listens at `http://127.0.0.1:8080/mcp`. The defaults are host
`127.0.0.1`, port `8080` and endpoint path `/mcp`. Change the path with
`endpointPath:`. The listener runs on the SST servlet engine, and on loopback
addresses it rejects requests with a rebound `Host` or `Origin` header (see
[Security](../advanced/security.md)).

Open it in MCP Inspector:

```bash
npx @modelcontextprotocol/inspector http://127.0.0.1:8080/mcp
```

The *Tools* tab lists `add`, and the *Resources* tab lists `demo://motd` and
the `greeting://{name}` template.

Stop the listener when you are done:

```smalltalk
http stop.
```

## 7. Change things while it runs

The registries are live, so you can register or unregister definitions while
the server is running. Tell connected clients about the change:

```smalltalk
server toolRegistry unregisterToolNamed: 'add'.
server notifyToolsChanged.

server notifyResourceUpdated: 'demo://motd'.
```

Clients that subscribed with `subscriptions/listen` (or with an older
session-based subscription) receive the notification and refresh their
caches.

## Other ways to host

| Host with | When |
| --- | --- |
| `McpHttpServer` | Remote or multi-client access. Supports both protocol eras and legacy SSE. See [Streamable HTTP](../transports/streamable-http.md). |
| `McpStdioServer forServer: server` | The image is launched as a subprocess by a desktop host. See [stdio](../transports/stdio.md). |
| `McpInMemoryClientTransport` | Tests, and agents running in the same image. See [In-memory](../transports/in-memory.md). |

## Next steps

- [Your first client](first-client.md): consume this server from Smalltalk.
- [Tools](../servers/tools.md), [Resources](../servers/resources.md) and
  [Prompts](../servers/prompts.md): the server primitives in depth.
