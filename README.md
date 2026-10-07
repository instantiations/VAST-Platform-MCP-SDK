# MCP VAST Smalltalk SDK

<div align="center">

<strong>VAST Smalltalk implementation of the Model Context Protocol \(MCP\)</strong>

[![License: Apache 2.0](https://img.shields.io/badge/License-Apache2.0-blue.svg)](LICENSE)
[![VAST Platform](https://img.shields.io/badge/Platform-VAST%20Smalltalk-blue.svg)](https://www.instantiations.com/vast-platform/)
[![Protocol](https://img.shields.io/badge/protocol-modelcontextprotocol.io-blue.svg)](https://modelcontextprotocol.io)
[![Specification](https://img.shields.io/badge/spec-2026--07--28-blue.svg)](https://modelcontextprotocol.io/specification/2026-07-28)

</div>

> [!NOTE]
> **This SDK implements the modern [MCP 2026-07-28 specification](https://modelcontextprotocol.io/specification/2026-07-28)** \(stateless requests, per-request capability metadata, `server/discover`, and Streamable HTTP\), while retaining backward compatibility with earlier revisions \(`2025-11-25`, `2025-06-18`, `2025-03-26`, and `2024-11-05` handshake-era protocols and legacy SSE\).
> 
> Choose your client mode explicitly or allow automatic negotiation:
> 
> * `#modern` \(`McpClient modern`\): Modern `2026-07-28` specification with sessionless Streamable HTTP.
> 
> * `#legacy` \(`McpClient legacy`\): Handshake lifecycle \(`initialize` &rarr; `notifications/initialized`\).
> 
> * `#auto` \(`McpClient auto`\): Modern discovery with fallback to legacy handshake.
> 
> **External interoperability target:** Official Python MCP SDK `2.2.0`.

---

## What is MCP?

The [Model Context Protocol](https://modelcontextprotocol.io) enables LLM applications to access external tools, prompts, and contextual resources through a standardized, secure protocol. Think of it like a web API specifically designed for AI agents and LLM host integrations.

With the VAST MCP SDK you can:

* **Build MCP servers** in VAST Smalltalk that expose tools, resources, and reusable prompt templates to any MCP client or host \(e.g., Claude Desktop, MCP Inspector, custom agents\).

* **Build MCP clients** in VAST Smalltalk to consume tools and resources from any MCP server \(running in Smalltalk, Python, TypeScript, etc.\).

* **Communicate across all standard transports:** In-Memory \(direct image dispatch\), Native OS Subprocess stdio, Streamable HTTP, and Legacy HTTP+SSE.

---

## Requirements

* **VAST Platform Smalltalk** 15 (or later).

* **OpenSSL libraries** installed and [configured in VAST](https://www.instantiations.com/vast-support/documentation/FAQ/index.html#page/FAQ/va09002.html).

---

## Installation / Loading

* Clone, or [download a ZIP archive](https://github.com/instantiations/VAST-Platform-MCP-SDK/archive/refs/heads/main.zip) of, this repository.

* In VAST, load [Tonel](https://www.instantiations.com/vast-support/documentation/1500/#page/sg/tonel/tnl01-index.520.02.html) support: from the System Transcript window, use the menu item *Tools › Load/Unload Features* and load the ‘ST: Tonel Support’ feature.

* From the Configuration Maps Browser, use the menu item *Names › Import › Load Configuration Maps from Tonel Repository* and select the root directory of the local clone or extracted archive of the repository.

* In the window that opens, add and load the config map for the MCP SDK that corresponds to your version of VAST. At this time, only `MCP SDK (VAST 15.0)`.

---

## A server workspace

Create and publish an MCP server over Streamable HTTP:

```smalltalk
| server tool template http |
server := McpServer new name: 'Demo'; version: '1.0.0'; yourself.

"1. Register a tool"
tool := McpBlockTool new
    name: 'add';
    description: 'Add two numbers';
    inputSchema: ((EsOrderedDictionary new)
        at: 'type' put: 'object';
        at: 'properties' put: ((EsOrderedDictionary new)
            at: 'a' put: (EsOrderedDictionary with: 'type' -> 'integer');
            at: 'b' put: (EsOrderedDictionary with: 'type' -> 'integer');
            yourself);
        at: 'required' put: #('a' 'b');
        yourself);
    block: [:args | ((args at: 'a') + (args at: 'b')) printString];
    yourself.
server toolRegistry registerTool: tool.

"2. Register a templated resource"
template := McpBlockResourceTemplate new
    uriTemplate: 'greeting://{name}';
    name: 'greeting';
    readBlock: [:uri | | vars |
        vars := (McpUriTemplate template: 'greeting://{name}') matchUri: uri.
        EsOrderedDictionary with: 'contents' -> (Array with: ((EsOrderedDictionary new)
            at: 'uri' put: uri;
            at: 'mimeType' put: 'text/plain';
            at: 'text' put: ('Hello, ' , (vars at: 'name') , '!');
            yourself))];
    yourself.
server resourceTemplateRegistry registerTemplate: template.

"3. Start HTTP server on port 8080"
http := McpHttpServer new
    host: '127.0.0.1';
    port: 8080;
    mcpServer: server;
    start;
    yourself.
```
That's a complete MCP server exposing an `add` tool and a dynamic `greeting://{name}` resource template.

Test it using the official [MCP Inspector](https://github.com/modelcontextprotocol/inspector):

```bash
npx @modelcontextprotocol/inspector http://127.0.0.1:8080/mcp
```
---

## A client workspace

The SDK is also a full-featured MCP **client**. Connect to the HTTP server created above:

```smalltalk
| client result resourceResult |
client := McpClient modern.
client transport: (McpHttpClientTransport url: 'http://127.0.0.1:8080/mcp').

[
    client connect.

    "Invoke a tool"
    result := client callTool: 'add'
        arguments: (EsOrderedDictionary with: 'a' -> 1 with: 'b' -> 2).
    Transcript show: 'Sum: ' , ((result at: 'content') first at: 'text'); cr. "Outputs: 3"

    "Read a templated resource"
    resourceResult := client readResource: 'greeting://Smalltalker'.
    Transcript show: ((resourceResult at: 'contents') first at: 'text'); cr. "Outputs: Hello, Smalltalker!"
] ensure: [
    client close.
].
```

---

## Core Capabilities

### 1. In-Memory Direct Transport

For testing or hosting within the same Smalltalk image, bypass network serialization entirely:

```smalltalk
| client result |
client := McpClient forServer: server mode: #modern.
[
    result := client callTool: 'add'
        arguments: (EsOrderedDictionary with: 'a' -> 10 with: 'b' -> 20).
    Transcript show: ((result at: 'content') first at: 'text'); cr.
] ensure: [client close].
```

### 2. Structured Output & Schemas

Tools can enforce input and output JSON schemas. When an `outputSchema` is defined, returning a keyed dictionary automatically populates `structuredContent`:

```smalltalk
| outputSchema tool |
outputSchema := (EsOrderedDictionary new)
    at: 'type' put: 'object';
    at: 'properties' put: (EsOrderedDictionary with: 'status' -> (EsOrderedDictionary with: 'type' -> 'string'));
    at: 'required' put: #('status');
    yourself.

tool := McpBlockTool new
    name: 'status';
    inputSchema: (EsOrderedDictionary with: 'type' -> 'object');
    outputSchema: outputSchema;
    block: [EsOrderedDictionary with: 'status' -> 'ready'];
    yourself.
server toolRegistry registerTool: tool.
```

### 3. Reusable Prompt Templates

Prompts return parameterized message templates for LLMs:

```smalltalk
| prompt |
prompt := McpBlockPrompt new
    name: 'language';
    description: 'Programming language selector';
    arguments: (Array with: (EsOrderedDictionary with: 'name' -> 'language' with: 'required' -> true));
    block: [:args | | message |
        message := EsOrderedDictionary
            with:'role' -> 'user'
            with: 'content' -> (EsOrderedDictionary with: 'type' -> 'text' with: 'text' -> ('Chosen language: ' , (args at: 'language'))).
        EsOrderedDictionary with: 'messages' -> (Array with: message)];
    yourself.
server promptRegistry registerPrompt: prompt.
```

### 4. Binary Resources

Binary content \(e.g. images, archives\) is supported via Base64 strings in the `blob` property:

```smalltalk
| resource |
resource := McpBlockResource new
    uri: 'app://data/binary';
    name: 'data';
    mimeType: 'application/octet-stream';
    block: [
        EsOrderedDictionary with: 'contents' -> (Array with: ((EsOrderedDictionary new)
            at: 'uri' put: 'app://data/binary';
            at: 'mimeType' put: 'application/octet-stream';
            at: 'blob' put: (Base64Coder current encode: #[1 2 3 4]) asString;
            yourself))];
    yourself.
server resourceRegistry registerResource: resource.
```

### 5. Argument Completions

Provide auto-completions for prompts or URI templates via `completionBlock:`:

```smalltalk
prompt completionBlock: [:argName :prefix :context |
    argName = 'language'
        ifTrue: [#('smalltalk' 'python' 'javascript') select: [:each | (each indexOfSubCollection: prefix startingAt: 1) = 1]]
        ifFalse: [#()]].
```

### 6. Multi-Round-Trip Input \(Elicitation, Sampling, Roots\)

Tools can pause execution to request client/user input, sample a model, or request filesystem roots.
This example demonstrates a server tool requesting a coupon code, and a client intercepting that request to supply the code.

```smalltalk
tool2 := McpBlockTool new
    name: 'checkout';
    inputSchema: (EsOrderedDictionary with: 'type' -> 'object');
    "McpBlockTool automatically skips this block if the client already answered"
    resolve: 'coupon' with: [:ctx :args | McpElicit message: 'Enter coupon code (optional):'];
    block: [:args | | elicitResult couponCode |
        "The argument contains the ElicitResult object returned by the client"
        elicitResult := args at: 'coupon'.
        couponCode := elicitResult at: 'content' ifAbsent: ['none'].
        'Processed with coupon: ' , couponCode printString
    ];
    yourself.
server toolRegistry registerTool: tool2.

"Client supplies callback:"
client elicitationCallback: [:request :clientRef | 
	| prompt |
	prompt := (request at: 'params') at: 'message' ifAbsent: ['Input required:'].
	Transcript show: 'Server asked: ', prompt; cr.
    
	EsOrderedDictionary 
		with: 'action' -> 'accept' 
		with: 'content' -> 'DISCOUNT2026'].
	
result := client callTool: 'checkout' arguments: EsOrderedDictionary new.
```

State continuation is securely signed using `McpRequestStateSecurity`.

### 7. Change Notifications & TTL Caching

Servers can notify clients of updates, invalidating client-side caches:

```smalltalk
"Server publishing:"
server notifyToolsChanged.
server notifyResourceUpdated: 'greeting://world'.

"Client subscribing:"
client listen: (EsOrderedDictionary with: 'toolsListChanged' -> true)
       do: [:method :params | Transcript show: 'Notification: ' , method; cr].
```

### 8. Aggregating Multiple Servers \(`McpSessionGroup`\)

Aggregate multiple distinct MCP servers behind a single client interface:

```smalltalk
| group |
group := McpSessionGroup new prefixToolNamesWithServerName.
[
    group addClient: clientSmalltalk.
    group addClient: clientPython.
    group listTools. "Contains tools prefixed with server names"
] ensure: [group close].
```

---

## Transports Summary

| Transport | Client Class | Server Class | Notes |
| :--- | :--- | :--- | :--- |
| **In-Memory** | `McpInMemoryClientTransport` | `McpServer` | Direct dispatcher invocation; zero wire overhead. |
| **Streamable HTTP** | `McpHttpClientTransport` | `McpHttpServer` | Modern `2026-07-28` POST sessionless transport; SST HTTP/1.1. |
| **Legacy SSE** | `McpLegacySseClientTransport` | `McpHttpServer` \(`/sse`\) | Handshake-era SSE event stream with POST message URL. |
| **Subprocess Stdio** | `McpStdioClientTransport` | External CLI | Spawns external native processes \(Python, Node, Go\) via OS streams. |
| **Stdio Server** | External Host | `McpStdioServer` | Exposes VAST tools over standard I/O streams. |

### Subprocess Stdio Client Example

Launch an external Python MCP server directly from Smalltalk:

```smalltalk
| transport client |
transport := McpStdioClientTransport
    command: 'python'
    arguments: #('-u' 'server.py').
transport workingDirectory: '/path/to/server'; requestTimeout: 30.

client := McpClient auto.
client transport: transport.
[
    client connect.
    client listTools.
] ensure: [client close].
```
---

## Error Handling

JSON-RPC errors are signaled as `McpJsonRpcError`, while tool-level domain errors are returned in `isError: true`:

```smalltalk
[
    result := client callTool: 'add' arguments: EsOrderedDictionary new.
    (result at: 'isError' ifAbsent: [false]) ifTrue: [
        Transcript show: 'Tool execution error'; cr.
    ].
] on: McpJsonRpcError do: [:ex |
    Transcript show: ('RPC Error [', ex code printString, ']: ', ex messageText); cr.
].
```
Standard JSON-RPC error codes are available in `McpJsonRpcConstants`.

---
## Contributing

We encourage contributions! Please check the guidelines in the [CONTRIBUTING](CONTRIBUTING.md) file.

## License

The source code is distributed under the Apache 2.0 license. See the [LICENSE](LICENSE) file for details.
