# Reading resources

## Listing

```smalltalk
client listResources.            "static resources: uri, name, mimeType, ..."
client listResourceTemplates.    "templates: uriTemplate, name, ..."
```

Both follow pagination and answer an `Array` of validated definitions.

## Reading a resource

```smalltalk
| result |
result := client readResource: 'app://config'.
(result at: 'contents') do: [:entry |
    (entry includesKey: 'text')
        ifTrue: [Transcript show: (entry at: 'text'); cr]
        ifFalse: [self store: (Base64Coder current decode: (entry at: 'blob'))]].
```

The argument must be an absolute URI. Relative or empty URIs are rejected
before anything is sent. The result is a `ReadResourceResult`:

| Key | Meaning |
| --- | --- |
| `contents` | Array of entries. Each has `uri`, optional `mimeType`, and either `text` or Base64 `blob`. |
| `resultType` | `'complete'` (modern). |
| `cacheScope`, `ttlMs` | Caching hints (modern). See [Response caching](caching.md). |

A read can answer several entries, for example a directory-like resource that
expands into multiple files. Always iterate `contents`.

## Reading templated resources

To read from a template, expand it into a concrete URI first:

```smalltalk
| templates uri |
templates := client listResourceTemplates.
uri := (McpUriTemplate template: 'orders://{id}')
    expand: (EsOrderedDictionary with: 'id' -> '1001').
client readResource: uri.    "orders://1001"
```

`McpUriTemplate` implements RFC 6570 expansion, including percent-encoding of
reserved characters. Use it rather than string concatenation.

To help users fill in template variables, ask the server for completions:

```smalltalk
((client completeResource: 'orders://{id}' argument: 'id' value: '10')
    at: 'completion') at: 'values'.
```

## Unknown resources

```smalltalk
[client readResource: 'orders://9999']
    on: McpJsonRpcError
    do: [:ex | ex return: nil].
```

Servers answer `-32602` (modern) or `-32002` (handshake era) for unknown
URIs.

## Watching for changes

```smalltalk
client
    listen: ((EsOrderedDictionary new)
        at: 'resourcesListChanged' put: true;
        yourself)
    do: [:method :params |
        method = 'notifications/resources/updated'
            ifTrue: [self reload: (params at: 'uri')]].
```

See [Response caching](caching.md#change-notifications) for the filter keys
and for how notifications evict cached reads.
