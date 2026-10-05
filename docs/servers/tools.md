# Tools

A tool is an action that a model can invoke: it takes arguments, runs
Smalltalk code and returns a result. Tools are registered in the server's
`McpToolRegistry` and are advertised through `tools/list` and executed through
`tools/call`.

## Defining a tool

### With a block: `McpBlockTool`

```smalltalk
server toolRegistry registerTool: (McpBlockTool new
    name: 'lookup_customer';
    title: 'Look up customer';
    description: 'Answer the customer record for a customer number';
    inputSchema: ((EsOrderedDictionary new)
        at: 'type' put: 'object';
        at: 'properties' put: (EsOrderedDictionary with: 'number' -> (EsOrderedDictionary new
            at: 'type' put: 'string';
            at: 'description' put: 'Customer number, e.g. C-1001';
            yourself));
        at: 'required' put: #('number');
        yourself);
    block: [:args | (CustomerRepository default at: (args at: 'number')) asJsonSummary];
    yourself).
```

The block may take zero, one or two arguments and is evaluated with
`cull:cull:`:

| Block | Receives |
| --- | --- |
| `['pong']` | nothing |
| `[:args \| ...]` | the validated arguments, as a detached dictionary |
| `[:args :context \| ...]` | the arguments and the [`McpServerRequestContext`](context.md) |

### With a class: subclassing `McpTool`

For tools with more logic, or tools that are shared across servers, subclass
`McpTool` and implement `executeWithArguments:context:`:

```smalltalk
McpTool subclass: #CustomerLookupTool
    instanceVariableNames: 'repository'
    classVariableNames: ''
    poolDictionaries: ''

CustomerLookupTool >> initialize
    super initialize.
    self
        name: 'lookup_customer';
        description: 'Answer the customer record for a customer number';
        inputSchema: self class inputSchema

CustomerLookupTool >> executeWithArguments: arguments context: requestContext
    ^(repository at: (arguments at: 'number')) asJsonSummary
```

The rest of this page applies equally to both styles.

### Tool metadata

| Selector | Purpose |
| --- | --- |
| `name:` | Required. Case-sensitive protocol name, unique in the registry. |
| `title:` | Human-readable display name. |
| `description:` | Tells the model what the tool does and when to use it. Write it for the model. |
| `inputSchema:` | JSON Schema for the arguments. Must be object-rooted. Defaults to `{"type": "object"}`. |
| `outputSchema:` | Optional JSON Schema for `structuredContent` (see below). |
| `annotations:` | Behavioral hints: `title`, `readOnlyHint`, `destructiveHint`, `idempotentHint`, `openWorldHint`. |
| `icons:` | Array of icon dictionaries (`src`, `mimeType`, `sizes`). |
| `meta:` | Free-form `_meta` dictionary that is published with the definition. |
| `execution:` | Task execution metadata, e.g. `EsOrderedDictionary with: 'taskSupport' -> 'optional'`. |

Every setter validates its input immediately, so a malformed definition
fails when you build it, not when a client calls it.

```smalltalk
tool annotations: ((EsOrderedDictionary new)
    at: 'readOnlyHint' put: true;
    at: 'openWorldHint' put: false;
    yourself).
```

Annotations are hints for the host's user interface, for example to decide
whether to ask the user for confirmation. They are not a security boundary.

## Input validation

Before your code runs, the server validates the arguments against
`inputSchema`. If they don't match, the call answers a tool error
(`isError: true`) that explains the problem, and your code is not executed:

```json
{ "content": [{ "type": "text", "text": "Invalid params: missing required property b" }],
  "isError": true }
```

Returning the validation failure as a tool result rather than as a protocol
error lets the model read the message and retry with corrected arguments.

The built-in validator, `McpSchemaValidator`, enforces this subset of JSON
Schema:

| Keyword | Enforced |
| --- | --- |
| `type` (`object`, `array`, `string`, `number`, `integer`, `boolean`, `null`) | yes |
| `properties`, `required`, `additionalProperties` | yes |
| `items` | yes |
| `enum`, `const` | yes |
| `$ref` to `#/$defs/...`, `#/definitions/...` or an `$anchor` in the same document | yes |
| `minimum`, `maxLength`, `pattern`, `format`, `allOf`/`anyOf`/`oneOf`, ... | published to clients but **not** enforced |

The validator never fetches remote schemas. Check constraints that it
doesn't enforce, such as ranges and patterns, in your tool code.

## Results

### Plain values

Whatever the tool answers is converted into a `CallToolResult`:

| Tool answers | Client receives |
| --- | --- |
| a `String` | one `text` content block with that string |
| any other JSON-compatible value (number, Boolean, array, dictionary) | one `text` content block with the value serialized as JSON |
| a dictionary with a `'content'` key | that dictionary, unchanged |

### Rich content

To return several content blocks, or images and audio, answer the
`CallToolResult` yourself:

```smalltalk
block: [:args |
    (EsOrderedDictionary new)
        at: 'content' put: (Array
            with: (EsOrderedDictionary new
                at: 'type' put: 'text';
                at: 'text' put: 'Chart for Q3';
                yourself)
            with: (EsOrderedDictionary new
                at: 'type' put: 'image';
                at: 'mimeType' put: 'image/png';
                at: 'data' put: (Base64Coder current encode: self chartPngBytes) asString;
                yourself));
        at: 'isError' put: false;
        yourself]
```

Supported content types are `text`, `image` and `audio` (Base64 `data` plus
`mimeType`), `resource` (an embedded resource with `uri` and either `text` or
`blob`) and `resource_link` (`uri` and `name`). The server validates every
block before sending it.

### Structured output

If a tool declares an `outputSchema`, it promises a typed JSON result in
`structuredContent`. Answer a dictionary without a `'content'` key and the
server does the rest. It places the dictionary in `structuredContent`, adds its
JSON text as a `text` block for older clients, and validates it against the
schema:

```smalltalk
server toolRegistry registerTool: (McpBlockTool new
    name: 'stock_level';
    inputSchema: ((EsOrderedDictionary new)
        at: 'type' put: 'object';
        at: 'properties' put: (EsOrderedDictionary with: 'sku' -> (EsOrderedDictionary with: 'type' -> 'string'));
        at: 'required' put: #('sku');
        yourself);
    outputSchema: ((EsOrderedDictionary new)
        at: 'type' put: 'object';
        at: 'properties' put: ((EsOrderedDictionary new)
            at: 'sku' put: (EsOrderedDictionary with: 'type' -> 'string');
            at: 'onHand' put: (EsOrderedDictionary with: 'type' -> 'integer');
            yourself);
        at: 'required' put: #('sku' 'onHand');
        yourself);
    block: [:args |
        (EsOrderedDictionary new)
            at: 'sku' put: (args at: 'sku');
            at: 'onHand' put: (Inventory onHandFor: (args at: 'sku'));
            yourself];
    yourself).
```

The client receives:

```json
{
  "content": [{ "type": "text", "text": "{\"sku\":\"A-17\",\"onHand\":42}" }],
  "structuredContent": { "sku": "A-17", "onHand": 42 },
  "isError": false
}
```

!!! warning
    A result that violates the `outputSchema` is a server bug, not a tool
    error. The server signals an error instead of sending invalid data, and
    the client receives a JSON-RPC error.

## Errors

There are two kinds of failure, and they reach the client differently:

| Situation | Client sees |
| --- | --- |
| The tool ran and failed (business rule, missing record, upstream API down) | Normal result with `isError: true`. The model can read the message and react. |
| The request itself is wrong (unknown tool, malformed params) | JSON-RPC error `-32602`, signalled on the client as `McpJsonRpcError`. |

Inside a tool, signal `McpToolError` for failures that the model should see:

```smalltalk
block: [:args |
    | customer |
    customer := CustomerRepository default
        at: (args at: 'number')
        ifAbsent: [McpToolError signal: 'No customer with number ' , (args at: 'number')].
    customer asJsonSummary]
```

The server catches **every** `Error` signalled during execution, not only
`McpToolError`, and returns its `messageText` with `isError: true`. Be aware
of what your exception texts reveal. Wrap code that may raise low-level
errors (database drivers, file I/O) and signal an `McpToolError` with a
message intended for the model instead.

## Interactive tools

A tool can pause and ask for missing input: from the user (elicitation), from
the host's model (sampling) or about the client's filesystem roots. Declare
this with resolvers:

```smalltalk
tool resolve: 'confirm' with: [:context :args |
    McpElicit message: 'Delete ' , (args at: 'path') , '?'].
```

When `confirm` hasn't been supplied yet, the call returns an
`input_required` result. The client gathers the answer and resends the call,
and the block then runs with `args at: 'confirm'` filled in. See
[Interactive input](../advanced/mrtr-interactive-input.md).

## Progress

Long-running tools can report progress through the request context:

```smalltalk
block: [:args :context |
    1 to: 10 do: [:step |
        self importBatch: step.
        context reportProgress: step total: 10 message: 'Batch ' , step printString].
    'Imported 10 batches']
```

See [Request context](context.md).

## Managing the registry

```smalltalk
server toolRegistry includesToolNamed: 'stock_level'.
server toolRegistry toolNamed: 'stock_level' ifAbsent: [nil].
server toolRegistry unregisterToolNamed: 'stock_level'.
server toolRegistry tools.    "name -> tool"
server notifyToolsChanged.    "tell subscribed clients to refresh"
```

The registry is thread-safe and can be changed while the server handles
requests. `tools/list` is paginated, with `server listPageSize` entries per
page (default 100).
