# Response caching

Every `McpClient` has an `McpClientResponseCache` (SEP-2549). It stores
results that the server marks as cacheable and answers repeated requests
locally until they expire or the server says that something changed.

## How it works

1. When a result carries a positive `ttlMs`, at top level or in `_meta`, the
   client stores it under the method name and the request parameters,
   together with the `cacheScope`.
2. A later identical request is answered from the cache while the entry is
   fresh. The answer is a detached copy, so changing it doesn't affect the
   cache.
3. Expired entries are dropped when they are next looked up.

Nothing is cached unless the server sends a TTL. An `McpServer` sends
`ttlMs: 0` by default. To make a resource cacheable, set its `meta:` (see
[Resources](../servers/resources.md#caching-hints)):

```smalltalk
resource meta: ((EsOrderedDictionary new)
    at: 'ttlMs' put: 60000;
    at: 'cacheScope' put: 'public';
    yourself).
```

Requests that carry a progress callback or per-call headers are never
answered from the cache.

## Cache modes

```smalltalk
client cacheMode: #use.        "default: read from and write to the cache"
client cacheMode: #refresh.    "always ask the server, but store fresh results"
client cacheMode: #bypass.     "neither read nor write"

client clearCache.             "drop all entries"
```

`#refresh` is handy after you know the server state changed without
receiving a notification. Switch back to `#use` afterwards.

## Tuning

```smalltalk
client responseCache
    maxEntries: 256;       "default 1024; the oldest entries are evicted first"
    defaultTtlMs: 0.       "TTL for results that have no ttlMs (default 0: don't cache)"
```

TTLs are capped at 24 hours. You can also install your own cache with
`client responseCache: anMcpClientResponseCache`, for example to share one
between clients.

## Change notifications

Servers announce changes with notifications. Subscribe with `listen:do:`,
which sends `subscriptions/listen` and answers the server's acknowledgement:

```smalltalk
client
    listen: ((EsOrderedDictionary new)
        at: 'toolsListChanged' put: true;
        at: 'promptsListChanged' put: true;
        at: 'resourcesListChanged' put: true;
        yourself)
    do: [:method :params | Transcript show: 'Server changed: ' , method; cr].
```

| Filter key | Notification | Evicted from the cache |
| --- | --- | --- |
| `toolsListChanged` (or `tools`) | `notifications/tools/list_changed` | `tools/list` |
| `promptsListChanged` (or `prompts`) | `notifications/prompts/list_changed` | `prompts/list` |
| `resourcesListChanged` (or `resources`) | `notifications/resources/list_changed` | `resources/list` |
| `resourceSubscriptions` | `notifications/resources/updated` | `resources/read` for that URI (all reads if no URI is given) |

`listen:do:` returns as soon as the server acknowledges the subscription. The
notifications arrive in the background (over HTTP on an SSE stream) and
evaluate your block in the transport's process. Keep the block short, or fork
longer work.

On the server side, the matching triggers are `notifyToolsChanged`,
`notifyPromptsChanged`, `notifyResourcesChanged` and
`notifyResourceUpdated: aUri`.

## Example: a cached catalog browser

```smalltalk
| client |
client := McpClient modern
    transport: (McpHttpClientTransport url: 'http://127.0.0.1:8080/mcp');
    yourself.
client connect.
client
    listen: (EsOrderedDictionary with: 'resourcesListChanged' -> true)
    do: [:method :params | Transcript show: 'Catalog changed, cache evicted'; cr].

client readResource: 'catalog://products'.    "network"
client readResource: 'catalog://products'.    "cache, while the TTL lasts"
```
