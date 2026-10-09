"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# McpBlockTool

`McpBlockTool` executes an MCP tool through a configured block, evaluating any
registered parameter resolvers.

## Responsibilities

- Evaluate parameter resolvers prior to block execution.
- If a resolver yields a request marker (`McpElicit`, `McpSample`, `McpListRoots`),
  produce an `InputRequiredResult` with `requestState` to trigger client multi-round-trip resolution.
- Pass validated arguments (with resolved injections) and request context to the tool block.
- Preserve the base tool definition and result contract.

## Lifecycle and boundaries

Configuration is mutable; callers own block thread-safety.
"
Class {
	#name : 'McpBlockTool',
	#superclass : 'McpTool',
	#instVars : [
		'block'
	],
	#category : 'McpTools'
}

{ #category : 'Accessing' }
McpBlockTool >> block [
	"Answer the configured tool-execution block.

	 Answers:
		<Block> or nil."

	^block
]

{ #category : 'Accessing' }
McpBlockTool >> block: aBlock [
	"Set an execution block accepting zero, one, or two arguments.

	 Arguments:
		aBlock - <Block> tool implementation.
	 Answers:
		<McpBlockTool> the receiver."

	(aBlock isBlock and: [aBlock numArgs between: 0 and: 2])
		ifFalse: [self error: 'MCP tool block must accept zero, one, or two arguments'].
	block := aBlock.
	^self
]

{ #category : 'Execution' }
McpBlockTool >> executeWithArguments: arguments context: requestContext [
	"Execute the configured block with arguments and optional context,
	 evaluating parameter resolvers and yielding InputRequiredResult when needed.

	 Arguments:
		arguments - <KeyedCollection> validated tool arguments.
		requestContext - <McpServerRequestContext> or nil.
	 Answers:
		<Object> raw tool result or InputRequiredResult."

	| effectiveArgs inputResponses |

	block ifNil: [self error: 'MCP tool execution block is not configured'].
	effectiveArgs := arguments copy.
	inputResponses := requestContext ifNotNil: [:ctx | ctx inputResponses].

	self resolvers do: [:resolver | | paramName resolved |
		paramName := resolver name.
		(inputResponses notNil and: [inputResponses includesKey: paramName])
			ifTrue: [| resp |
				resp := inputResponses at: paramName.
				effectiveArgs at: paramName put: resp]
			ifFalse: [
				resolved := resolver resolveInContext: requestContext arguments: effectiveArgs.
				((resolved isKindOf: McpElicit)
					or: [(resolved isKindOf: McpSample) or: [resolved isKindOf: McpListRoots]])
						ifTrue: [| inputRequired |
							inputRequired :=
								EsOrderedDictionary new
									at: 'resultType' put: 'input_required';
									at: 'inputRequests'
										put: (
											EsOrderedDictionary
												with: paramName -> resolved asInputRequest);
									at: 'requestState' put: paramName;
									yourself.
							^inputRequired].
				effectiveArgs at: paramName put: resolved]].

	^block cull: effectiveArgs cull: requestContext
]
