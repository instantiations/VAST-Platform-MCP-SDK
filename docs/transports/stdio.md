# stdio

With the stdio transport, a client starts the server as a subprocess and
exchanges newline-delimited JSON-RPC messages over the process's standard
input and output. This is how desktop hosts such as Claude Desktop or Cursor
run local MCP servers, and how most published MCP servers in the npm and PyPI
ecosystems are distributed.

The SDK supports both directions:

| Class | Use |
| --- | --- |
| `McpStdioClientTransport` | A VAST Platform client launches an external MCP server (Python, Node, Go, another VAST image). |
| `McpStdioServer` | A VAST Platform image *is* the server, launched by a host. |

## Launching an external server

```smalltalk
| client |
client := McpClient auto
    transport: (McpStdioClientTransport
        command: 'npx'
        arguments: #('-y' '@modelcontextprotocol/server-everything'));
    yourself.
[client connect.
 client listTools collect: [:each | each at: 'name']]
    ensure: [client close].
```

The subprocess is started on `connect`, using `OsProcessStarter` from
`OsProcessesApp`, and terminated on `close`. Pending requests fail when the
process exits.

### Configuration

```smalltalk
| transport |
transport := McpStdioClientTransport
    command: 'python'
    arguments: #('-u' 'weather_server.py')
    environment: (EsOrderedDictionary with: 'WEATHER_API_KEY' -> 'secret')
    workingDirectory: '/opt/mcp/weather'.
transport
    requestTimeout: 30;
    stderrHandler: [:line | Transcript show: '[weather] ' , line; cr].
```

| Selector | Default | Purpose |
| --- | --- | --- |
| `command:`, `arguments:` | required | Executable and its arguments. The executable is resolved through the `PATH`. |
| `environment:` | inherited | Variables added to (or overriding) the inherited environment. |
| `workingDirectory:` | inherited | Directory to start the process in. |
| `runInShell:` | `false` | Start through the system shell, e.g. for `.cmd` wrappers on Windows such as `npx.cmd`. |
| `requestTimeout:` | 60 | **Seconds** to wait for each response. |
| `stderrHandler:` | `nil` | One-argument block that receives each line written to stderr. |

The server's stderr is also collected in `transport stderrLines`, which helps
diagnose a server that fails to start. MCP servers use stderr for logging,
because stdout carries the protocol.

!!! tip
    For Python servers, pass `-u` (unbuffered output), or set
    `PYTHONUNBUFFERED=1` in the environment, so that responses aren't held in
    an output buffer. On Windows, use `npx.cmd` or `runInShell: true` for
    Node-based servers.

Per-call HTTP headers aren't available on stdio. `callTool:arguments:headers:`
with non-empty headers signals an error.

## Exposing a VAST server over stdio

`McpStdioServer` reads one JSON-RPC message per line from an input stream,
dispatches it to an `McpServer`, and writes each response as one line to an
output stream:

```smalltalk
| stdio |
stdio := (McpStdioServer forServer: server)
    inputStream: anInputStream;
    outputStream: anOutputStream;
    start;
    yourself.
```

`start` runs the read loop in a background process. The loop ends when the
input stream reaches its end (the host closed the pipe) or when you send
`stop`.

!!! note "TODO"
    `McpStdioServer` doesn't bind to the process's standard input and output
    by itself. In a headless image that a host launches, pass the image's
    stdin and stdout streams. Document the recommended VAST Platform streams
    and the packaging recipe here.

Rules for a stdio-hosted image:

- **Never write anything else to stdout.** A stray `Transcript` line that ends
  up on stdout corrupts the protocol. Log to stderr or to a file.
- Messages are UTF-8 and must not contain raw newlines. The SDK's JSON writer
  escapes them.
- The stdio server dispatches requests in the modern protocol context. Server
  progress notifications aren't sent over stdio.

### Registering with a desktop host

Once you have a launchable image, register it like any other stdio server. For
Claude Desktop, `claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "vast-demo": {
      "command": "<path to the VAST Platform VM executable>",
      "args": ["-i<path to your packaged image>.icx", "-nouistart"]
    }
  }
}
```

Fill in the VM executable and image paths for your installation.
