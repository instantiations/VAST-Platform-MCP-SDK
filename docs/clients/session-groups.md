# Session groups

An agent often needs tools from several MCP servers at once, for example a
VAST service, a Python data server and a filesystem server. `McpSessionGroup`
combines several connected `McpClient`s behind one interface. It lists the
tools, prompts and resources of all servers together and routes each call to
the server that owns it.

## Building a group

```smalltalk
| inventory files group |
inventory := McpClient modern
    transport: (McpHttpClientTransport url: 'http://127.0.0.1:8080/mcp');
    yourself.
files := McpClient auto
    transport: (McpStdioClientTransport
        command: 'npx'
        arguments: #('-y' '@modelcontextprotocol/server-filesystem' '/srv/shared'));
    yourself.

group := McpSessionGroup new.
[
    group addClient: inventory; addClient: files.
    group listTools.
    group callTool: 'read_file' arguments: (EsOrderedDictionary with: 'path' -> '/srv/shared/notes.txt')
] ensure: [group close].
```

`addClient:` connects the client if necessary, then fetches its tools,
prompts and resources and records which client owns each name. A server that
fails to list one category simply contributes nothing for it.

| Message | Routed by |
| --- | --- |
| `listTools`, `listPrompts`, `listResources` | aggregated over all clients |
| `callTool:arguments:` | tool name |
| `getPrompt:arguments:` | prompt name |
| `readResource:` | resource URI |
| `removeClient:` | removes a client and its entries |
| `close` | closes every client in the group |

Calling an unknown name signals an error.

!!! note
    The aggregated `listTools` answers each tool's `name` and `inputSchema`
    only. For descriptions and annotations, ask the individual clients
    (`group clients`).

## Name collisions

Names must be unique across the group. Without configuration, adding a second
server that also has a tool named `search` signals
`Tool name collision in session group: search`.

### Prefixing with the server name

```smalltalk
group := McpSessionGroup new prefixToolNamesWithServerName; yourself.
```

Every tool and prompt name is then published as `<serverName>_<name>`, for
example `inventory_search` and `files_search`, where `serverName` comes from
each server's `serverInfo`. Calls are translated back to the original name.
Make sure that the servers report distinct names.

### Custom naming

```smalltalk
group nameCollisionHook: [:rawName :serverInfo |
    (serverInfo at: 'name') asLowercase , '.' , rawName].
```

The hook is applied to **every** tool and prompt name, not only to colliding
ones. When a hook is installed, duplicate names that it still produces are not
detected: the last server added wins. Resource URIs are never renamed.

## Typical agent loop

```smalltalk
| tools answer |
tools := group listTools.
answer := self llm chooseToolFrom: tools for: userQuestion.
group callTool: (answer at: 'tool') arguments: (answer at: 'arguments').
```

Session groups are thread-safe. Lookups and registrations are guarded by a
mutex, and the routed calls run on the individual clients.
