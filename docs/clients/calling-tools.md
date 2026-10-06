# Calling tools

## Listing tools

```smalltalk
| tools |
tools := client listTools.
tools do: [:each |
    Transcript show: (each at: 'name') , ': ' , (each at: 'description' ifAbsent: ['']); cr].
```

`listTools` follows pagination until the last page, validates each definition
and answers an `Array`. Each definition has `name` and `inputSchema`, and
optionally `title`, `description`, `outputSchema`, `annotations`, `icons`,
`execution` and `_meta`.

The client remembers each tool's input and output schemas
(`client knownToolSchemas`). It uses them to validate `structuredContent` and,
in modern mode, to emit `Mcp-Param-*` headers for arguments that the schema
marks for it (SEP-2243). Call `listTools` before calling tools whose output
you want validated.

## Calling a tool

```smalltalk
| result |
result := client
    callTool: 'stock_level'
    arguments: (EsOrderedDictionary with: 'sku' -> 'A-17').
```

`arguments` is any keyed collection, or `nil` for no arguments. The answer is
a `CallToolResult`:

| Key | Meaning |
| --- | --- |
| `content` | Array of content blocks (`text`, `image`, `audio`, `resource`, `resource_link`). |
| `structuredContent` | Typed result, present when the tool declares an `outputSchema`. |
| `isError` | `true` if the tool reported a failure. |
| `resultType` | `'complete'` (modern protocol only). |
| `_meta` | Server metadata, e.g. `io.modelcontextprotocol/serverInfo`. |

### Reading content

```smalltalk
(result at: 'content') do: [:block |
    (block at: 'type') = 'text'
        ifTrue: [Transcript show: (block at: 'text'); cr].
    (block at: 'type') = 'image'
        ifTrue: [self showImage: (Base64Coder current decode: (block at: 'data'))]].
```

### Structured output

```smalltalk
(result at: 'structuredContent' ifAbsent: [nil])
    ifNotNil: [:data | (data at: 'onHand') printString]
```

If the tool's `outputSchema` is known from `listTools`, the client checks
`structuredContent` against it. A result that doesn't conform signals an
error.

## Handling failures

```smalltalk
[result := client callTool: 'stock_level' arguments: (EsOrderedDictionary with: 'sku' -> 'A-17').
 (result at: 'isError')
    ifTrue: [self reportToolFailure: ((result at: 'content') first at: 'text')]
    ifFalse: [self useResult: result]]
        on: McpJsonRpcError
        do: [:ex | self reportProtocolError: ex code message: ex messageText]
```

- `isError: true`: the tool ran, or its arguments failed schema validation,
  and it reports a problem. When an LLM is driving, pass the text back to the
  model so that it can correct itself.
- `McpJsonRpcError`: the call couldn't be processed at all, for example
  because of an unknown tool (`-32602`) or an internal server error
  (`-32603`).

## Progress

```smalltalk
client
    callTool: 'import'
    arguments: (EsOrderedDictionary with: 'file' -> 'orders.csv')
    progressCallback: [:progress :total :message |
        Transcript show: 'Import ' , progress printString , '/' , total printString; cr].
```

The client generates a progress token, attaches it to the request, and
evaluates the block for every `notifications/progress` that arrives before the
result. The block is evaluated with `cull:`, so it can take up to four
arguments: `progress`, `total`, `message` and the raw `params`. To use your
own token, call `callTool:arguments:progressToken:progressCallback:`.

## Per-call HTTP headers

On HTTP transports, you can add headers to a single call, for example for
tracing:

```smalltalk
client
    callTool: 'stock_level'
    arguments: (EsOrderedDictionary with: 'sku' -> 'A-17')
    headers: (EsOrderedDictionary with: 'X-Request-Id' -> 'abc-123').
```

The stdio transport has no headers and rejects non-empty ones. The in-memory
transport accepts them but ignores them.
Responses to calls with headers are never answered from the cache.

## Interactive tools

If the server needs more input, the call doesn't fail. The client invokes
your `elicitationCallback:`, `samplingCallback:` or `rootsCallback:`, resends
the call with the answers, and returns the final result. See
[Interactive input](../advanced/mrtr-interactive-input.md).

## Cancelling

To abort a long-running request from another process:

```smalltalk
client cancelRequest: requestId reason: 'User pressed Stop'.
```

This sends `notifications/cancelled`. Cancellation is advisory: the server
may still complete the work.
