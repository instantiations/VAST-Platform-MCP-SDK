# Prompts

Prompts are reusable, parameterized message templates. A host typically shows
them to the user, for example as slash commands, and inserts the rendered
messages into the conversation. Clients list them through `prompts/list` and
render them through `prompts/get`.

## Defining a prompt

```smalltalk
server promptRegistry registerPrompt: (McpBlockPrompt new
    name: 'code_review';
    title: 'Review code';
    description: 'Ask the model to review a piece of code';
    arguments: (Array
        with: ((EsOrderedDictionary new)
            at: 'name' put: 'language';
            at: 'description' put: 'Programming language';
            at: 'required' put: true;
            yourself)
        with: ((EsOrderedDictionary new)
            at: 'name' put: 'code';
            at: 'required' put: true;
            yourself)
        with: ((EsOrderedDictionary new)
            at: 'name' put: 'focus';
            at: 'description' put: 'Optional focus such as performance or security';
            yourself));
    block: [:args |
        (EsOrderedDictionary new)
            at: 'description' put: 'Code review request';
            at: 'messages' put: (Array with: ((EsOrderedDictionary new)
                at: 'role' put: 'user';
                at: 'content' put: ((EsOrderedDictionary new)
                    at: 'type' put: 'text';
                    at: 'text' put: 'Review this ' , (args at: 'language') , ' code'
                        , ((args at: 'focus' ifAbsent: [nil])
                            ifNil: ['']
                            ifNotNil: [:focus | ' with a focus on ' , focus])
                        , ':' , (String with: Character lf) , (args at: 'code');
                    yourself);
                yourself));
            yourself];
    yourself).
```

The block may take no argument, the arguments, or the arguments and the
[request context](context.md). It must answer a `GetPromptResult`: a
dictionary with a `'messages'` array and an optional `'description'`. As with
tools and resources, you can subclass `McpPrompt` and implement
`renderWithArguments:context:` instead.

## Arguments

Each argument definition is a dictionary with `name` (required), and optional
`title`, `description` and `required` (default `false`).

Before rendering, the server checks the supplied arguments. Each of these is
answered with JSON-RPC error `-32602`, and the block is not evaluated:

- a required argument is missing,
- an argument that the prompt doesn't declare is supplied,
- a value isn't a string. Prompt arguments are always strings.

Your block therefore only has to handle optional arguments that are absent.
Use `at:ifAbsent:` for those.

## Messages

Every message has a `role`, `'user'` or `'assistant'`, and one content block.
Use an `assistant` message to prime the conversation, for example with a
response format:

```smalltalk
(EsOrderedDictionary new)
    at: 'role' put: 'assistant';
    at: 'content' put: ((EsOrderedDictionary new)
        at: 'type' put: 'text';
        at: 'text' put: 'Understood. I will list issues as bullet points ordered by severity.';
        yourself);
    yourself
```

The content types are the same as for tool results:

| `type` | Fields |
| --- | --- |
| `text` | `text` |
| `image`, `audio` | `data` (Base64), `mimeType` |
| `resource` | `resource`: a dictionary with `uri` and either `text` or `blob` |
| `resource_link` | `uri`, `name` |

Embedding a resource lets a prompt carry its context with it:

```smalltalk
(EsOrderedDictionary new)
    at: 'role' put: 'user';
    at: 'content' put: ((EsOrderedDictionary new)
        at: 'type' put: 'resource';
        at: 'resource' put: ((EsOrderedDictionary new)
            at: 'uri' put: 'app://config';
            at: 'mimeType' put: 'application/json';
            at: 'text' put: AppSettings current asJsonString;
            yourself);
        yourself);
    yourself
```

The server validates every message and content block before returning the
result.

## Completions

Prompt arguments can offer auto-completion while the user types:

```smalltalk
prompt completionBlock: [:argumentName :prefix :context |
    argumentName = 'language'
        ifTrue: [#('smalltalk' 'python' 'javascript') select: [:each | each beginsWithSubCollection: prefix]]
        ifFalse: [#()]].
```

See [Completions](completions.md).

## Managing the registry

```smalltalk
server promptRegistry includesPromptNamed: 'code_review'.
server promptRegistry promptNamed: 'code_review' ifAbsent: [nil].
server promptRegistry unregisterPromptNamed: 'code_review'.
server notifyPromptsChanged.
```
