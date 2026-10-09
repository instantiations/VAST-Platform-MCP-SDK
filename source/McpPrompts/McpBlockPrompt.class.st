"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# McpBlockPrompt

`McpBlockPrompt` renders an MCP prompt by evaluating a configured block, and
optionally computes argument autocompletions.

## Responsibilities

- Pass validated arguments and request context to the rendering block.
- Provide dynamic autocompletions for prompt arguments via `completionBlock:`.
- Preserve the base prompt definition and metadata contract.

## Lifecycle and boundaries

Configuration is mutable; callers own block thread-safety.
"
Class {
	#name : 'McpBlockPrompt',
	#superclass : 'McpPrompt',
	#instVars : [
		'block',
		'completionBlock'
	],
	#category : 'McpPrompts'
}

{ #category : 'Accessing' }
McpBlockPrompt >> block [
	"Answer the configured prompt-rendering block.

	 Answers:
		<Block>."

	^block
]

{ #category : 'Accessing' }
McpBlockPrompt >> block: aBlock [
	"Set a rendering block accepting zero, one, or two arguments.

	 Arguments:
		aBlock - <Block> prompt renderer.
	 Answers:
		<McpBlockPrompt> the receiver."

	(aBlock isBlock and: [aBlock numArgs between: 0 and: 2])
		ifFalse: [self error: 'MCP prompt block must accept zero, one, or two arguments'].
	block := aBlock.
	^self
]

{ #category : 'Protocol Operations' }
McpBlockPrompt >> completeArgument: anArgumentName value: aCurrentValue context: aContextDictionary [
	"Compute completion values for an argument using the configured completion block.

	 Arguments:
		anArgumentName - <String> argument name.
		aCurrentValue - <String> current prefix or value.
		aContextDictionary - <KeyedCollection> optional context, or nil.
	 Answers:
		<Collection of String> or <KeyedCollection>."

	self completionBlock ifNil: [^#()].
	^self completionBlock cull: anArgumentName cull: aCurrentValue cull: aContextDictionary
]

{ #category : 'Accessing' }
McpBlockPrompt >> completionBlock [
	"Answer the completion handler block for prompt arguments.

	 Answers:
		<Block> or nil."

	^completionBlock
]

{ #category : 'Accessing' }
McpBlockPrompt >> completionBlock: aBlock [
	"Set the completion handler block for prompt arguments.

	 Arguments:
		aBlock - <Block> [:argName :currentVal :contextDict | ...], or nil.
	 Answers:
		<McpBlockPrompt> the receiver."

	(aBlock isNil or: [aBlock isKindOf: Block])
		ifFalse: [self error: 'Completion handler must be a block or nil'].
	completionBlock := aBlock.
	^self
]

{ #category : 'Execution' }
McpBlockPrompt >> renderWithArguments: argumentValues context: requestContext [
	"Render the prompt by evaluating the configured block.

	 The block may accept no arguments, argumentValues, or argumentValues and
	 requestContext. Its arity is validated when the block is configured.

	 Arguments:
		argumentValues - <KeyedCollection> validated prompt arguments.
		requestContext - <McpServerRequestContext> or nil.
	 Answers:
		<KeyedCollection> MCP GetPromptResult."

	block ifNil: [self error: 'MCP prompt rendering block is not configured'].
	^block cull: argumentValues cull: requestContext
]
