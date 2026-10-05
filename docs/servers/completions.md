# Completions

A completion suggests values for a prompt argument or a resource-template
variable while the user types. Hosts send `completion/complete` with a
reference (a prompt or a resource template), the argument name, the text typed
so far and, optionally, the values of other arguments that are already filled
in. The server answers up to 100 suggestions.

`McpServer` always advertises the `completions` capability.

## Per prompt or template

Attach a `completionBlock:` to an `McpBlockPrompt` or an
`McpBlockResourceTemplate`. The block receives the argument name, the current
value and a context dictionary (possibly `nil`) holding the values of the
other arguments. It is evaluated with `cull:`, so you can declare fewer block
arguments:

```smalltalk
template := McpBlockResourceTemplate new
    uriTemplate: 'repos://{owner}/{repo}';
    name: 'repository';
    readBlock: [:uri | self readRepository: uri];
    completionBlock: [:argumentName :prefix :context |
        argumentName = 'owner'
            ifTrue: [self owners select: [:each | each beginsWithSubCollection: prefix]]
            ifFalse: [| owner |
                owner := context ifNotNil: [:ctx |
                    (ctx at: 'arguments' ifAbsent: [nil])
                        ifNotNil: [:args | args at: 'owner' ifAbsent: [nil]]].
                (self reposOf: owner) select: [:each | each beginsWithSubCollection: prefix]]];
    yourself.
```

## What to return

The block answers either:

- **a collection of strings**: the suggestions, or
- **a dictionary** with `values` and, optionally, `total` (the number of
  matches) and `hasMore` (more matches exist than were returned).

```smalltalk
completionBlock: [:argumentName :prefix |
    | matches |
    matches := self customerNumbers select: [:each | each beginsWithSubCollection: prefix].
    (EsOrderedDictionary new)
        at: 'values' put: (matches copyFrom: 1 to: (matches size min: 20));
        at: 'total' put: matches size;
        at: 'hasMore' put: matches size > 20;
        yourself]
```

Values are converted with `asString` and truncated to 100 entries. A prompt or
template without a `completionBlock` answers an empty list.

## One handler for the whole server

To centralize completion logic, set a block on the server itself. **It takes
precedence** over all per-prompt and per-template blocks. It receives the raw
protocol values:

```smalltalk
server completionBlock: [:ref :argument :context :aServer |
    "ref:      {type: 'ref/prompt', name: ...} or {type: 'ref/resource', uri: ...}
     argument: {name: ..., value: ...}
     context:  {arguments: {...}} or nil"
    ((ref at: 'type') = 'ref/prompt' and: [(argument at: 'name') = 'language'])
        ifTrue: [#('smalltalk' 'python') select: [:each | each beginsWithSubCollection: (argument at: 'value')]]
        ifFalse: [#()]].
```

## Errors

Unknown prompts or templates, and malformed requests, are answered with
JSON-RPC error `-32602`.

## From the client side

```smalltalk
client completePrompt: 'code_review' argument: 'language' value: 'sm'.
client completeResource: 'repos://{owner}/{repo}' argument: 'owner' value: 'inst'.
client
    completeResource: 'repos://{owner}/{repo}'
    argument: 'repo'
    value: 'VA'
    context: (EsOrderedDictionary with: 'arguments' -> (EsOrderedDictionary with: 'owner' -> 'instantiations')).
```

Each answers the `CompleteResult`. The suggestions are at
`(result at: 'completion') at: 'values'`.
