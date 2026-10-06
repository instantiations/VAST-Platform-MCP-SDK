# Resources

Resources expose read-only data, such as files, records, configuration or
reports, that a host can load into the model's context. Each resource is
addressed by an absolute URI. Unlike tools, the host or user usually decides
when to read a resource, not the model.

The SDK has two kinds:

| Kind | Registry | Addressed by |
| --- | --- | --- |
| Resource | `server resourceRegistry` | one fixed URI, e.g. `app://config` |
| Resource template | `server resourceTemplateRegistry` | an RFC 6570 URI template, e.g. `orders://{id}` |

Clients see resources through `resources/list` and templates through
`resources/templates/list`. Both are read with `resources/read` on a concrete
URI.

## Static resources

### `McpBlockResource`

```smalltalk
server resourceRegistry registerResource: (McpBlockResource new
    uri: 'app://config';
    name: 'config';
    title: 'Application configuration';
    description: 'Current runtime settings';
    mimeType: 'application/json';
    block: [
        EsOrderedDictionary with: 'contents' -> (Array with: ((EsOrderedDictionary new)
            at: 'uri' put: 'app://config';
            at: 'mimeType' put: 'application/json';
            at: 'text' put: AppSettings current asJsonString;
            yourself))];
    yourself).
```

The block is evaluated on every read. It may take no argument or one argument,
the [`McpServerRequestContext`](context.md), and must answer a
`ReadResourceResult`: a dictionary whose `'contents'` array holds one or more
entries.

### Subclassing `McpResource`

As with tools, you can subclass `McpResource` and implement
`readWithContext:` instead of using a block.

### Resource metadata

| Selector | Purpose |
| --- | --- |
| `uri:` | Required. Absolute URI with a scheme. |
| `name:` | Required. Short identifier. |
| `title:`, `description:` | Display name and explanation for the host. |
| `mimeType:` | MIME type of the content. |
| `size:` | Size in bytes, if known. Hosts can use it to estimate context usage. |
| `annotations:` | `audience`, `priority`, `lastModified`. |
| `icons:`, `meta:` | Icons and free-form `_meta`. |

## Text and binary content

Each entry in `'contents'` has a `uri`, an optional `mimeType`, and **exactly
one** of:

- `'text'`: a String.
- `'blob'`: Base64-encoded binary data.

```smalltalk
server resourceRegistry registerResource: (McpBlockResource new
    uri: 'app://logo';
    name: 'logo';
    mimeType: 'image/png';
    block: [
        EsOrderedDictionary with: 'contents' -> (Array with: ((EsOrderedDictionary new)
            at: 'uri' put: 'app://logo';
            at: 'mimeType' put: 'image/png';
            at: 'blob' put: (Base64Coder current encode: self logoBytes) asString;
            yourself))];
    yourself).
```

The server validates every entry. An entry with both `text` and `blob`, or
neither, is rejected.

## Resource templates

A template publishes a parameterized family of resources:

```smalltalk
server resourceTemplateRegistry registerTemplate: (McpBlockResourceTemplate new
    uriTemplate: 'orders://{id}';
    name: 'order';
    description: 'An order by its number';
    mimeType: 'application/json';
    readBlock: [:uri :context | | vars order |
        vars := (McpUriTemplate template: 'orders://{id}') matchUri: uri.
        order := OrderRepository default
            at: (vars at: 'id')
            ifAbsent: [McpJsonRpcError signalCode: -32602 message: 'Unknown order' data: nil].
        EsOrderedDictionary with: 'contents' -> (Array with: ((EsOrderedDictionary new)
            at: 'uri' put: uri;
            at: 'mimeType' put: 'application/json';
            at: 'text' put: order asJsonString;
            yourself))];
    yourself).
```

When a client reads `orders://1001`, the server first looks for a static
resource with that exact URI. If there is none, it searches the templates. At
most one template may match a URI; overlapping templates cause an error.

The `readBlock` receives the concrete URI and, optionally, the request
context. When a context is present, the extracted variables are also stored in
`context metadata at: 'variables'`.

### Custom matching

By default, the template string decides which URIs match. Use `matchBlock:` to
restrict matching further, for example to numeric ids:

```smalltalk
template matchBlock: [:uri |
    ((McpUriTemplate template: 'orders://{id}') matchUri: uri)
        ifNil: [false]
        ifNotNil: [:vars | (vars at: 'id') allSatisfy: [:each | each isDigit]]].
```

### `McpUriTemplate`

`McpUriTemplate` implements RFC 6570 levels 1 to 4 and is useful on its own:

```smalltalk
| template |
template := McpUriTemplate template: 'files://{+path}{?rev}'.
template variableNames.                          "('path' 'rev')"
template expand: (EsOrderedDictionary with: 'path' -> 'src/main.st' with: 'rev' -> '7').
    "'files://src/main.st?rev=7'"
template matchUri: 'files://src/main.st?rev=7'.  "path -> 'src/main.st', rev -> '7'"
template matchesUri: 'other://x'.                "false"
McpUriTemplate isTemplate: 'orders://{id}'.      "true"
```

Supported operators are simple `{var}`, reserved `{+var}`, fragment `{#var}`,
label `{.var}`, path `{/var}`, path-style parameters `{;var}`, and query
`{?var}` / `{&var}`, plus the explode modifier `{/var*}`. `matchUri:`
percent-decodes the extracted values.

Templates can also offer [argument completions](completions.md) for their
variables.

## Serving files safely

When a URI variable becomes part of a filesystem path, validate it with
`McpPathSecurity` so that a client can't read outside a sandbox directory:

```smalltalk
readBlock: [:uri | | vars path |
    vars := (McpUriTemplate template: 'docs://{+path}') matchUri: uri.
    path := McpPathSecurity safeJoin: '/srv/app/docs' with: (vars at: 'path').
    ...]
```

`safeJoin:with:` signals `McpPathEscapeError` if the relative part contains
`..` traversal (with `/` or `\`), a null byte, or is itself absolute (a
leading slash or a drive letter). For individual checks, use
`McpPathSecurity containsPathTraversal:` and `McpPathSecurity isAbsolutePath:`.
See [Security](../advanced/security.md).

## Caching hints

In the modern protocol, every successful `resources/read` result carries
`cacheScope` and `ttlMs` hints. They default to `'private'` and `0` (don't
cache). Set them per resource through `meta:`:

```smalltalk
resource meta: ((EsOrderedDictionary new)
    at: 'ttlMs' put: 60000;
    at: 'cacheScope' put: 'public';
    yourself).
```

The [client response cache](../clients/caching.md) follows these hints.

## Change notifications

```smalltalk
server notifyResourceUpdated: 'app://config'.    "contents of one resource changed"
server notifyResourcesChanged.                   "the list of resources changed"
```

Subscribed clients receive `notifications/resources/updated` or
`notifications/resources/list_changed` and evict their cached copies.

## Errors

Reading an unknown URI answers a JSON-RPC error: `-32602` in the modern
protocol, `-32002` (resource not found) in handshake-era sessions. Malformed
or relative URIs are rejected with `-32602`. For your own failures, signal
`McpJsonRpcError signalCode:message:data:` with a meaningful code.

## Managing the registries

```smalltalk
server resourceRegistry includesResourceAt: 'app://config'.
server resourceRegistry unregisterResourceAt: 'app://config'.
server resourceTemplateRegistry includesTemplate: 'orders://{id}'.
server resourceTemplateRegistry templateMatchingUri: 'orders://1001' ifAbsent: [nil].
server resourceTemplateRegistry unregisterTemplate: 'orders://{id}'.
```
