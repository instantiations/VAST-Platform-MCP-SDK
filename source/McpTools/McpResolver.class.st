"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# McpResolver

`McpResolver` encapsulates a dynamic parameter resolution dependency for an MCP tool,
matching `Resolve(fn)` in `mcp-python`.

## Responsibilities

- Bind a parameter name to a resolution block `[:context :arguments | ...]`.
- Evaluate dynamically before tool execution to compute parameter values or
  request markers (`McpElicit`, `McpSample`, `McpListRoots`).

## Lifecycle and boundaries

Owned by an `McpTool`. Evaluated per tool call round.
"
Class {
	#name : 'McpResolver',
	#superclass : 'Object',
	#instVars : [
		'name',
		'block'
	],
	#category : 'McpTools'
}

{ #category : 'Instance Creation' }
McpResolver class >> named: aString block: aBlock [
	"Answer a new parameter resolver for a named parameter.

	 Arguments:
		aString - <String> parameter name.
		aBlock - <Block> [:context :arguments | ...] resolver block.
	 Answers:
		<McpResolver>."

	^self new initializeNamed: aString block: aBlock
]

{ #category : 'Accessing' }
McpResolver >> block [
	"Answer the resolution block.

	 Answers:
		<Block>."

	^block
]

{ #category : 'Initialization',
  #vaVisibility : 'private' }
McpResolver >> initializeNamed: aString block: aBlock [
	"Initialize the resolver with its parameter name and resolution block.

	 Arguments:
		aString - <String>.
		aBlock - <Block>.
	 Answers:
		<McpResolver> the receiver."

	super initialize.
	name := aString copy.
	block := aBlock.
	^self
]

{ #category : 'Accessing' }
McpResolver >> name [
	"Answer the parameter name this resolver populates.

	 Answers:
		<String>."

	^name
]

{ #category : 'Execution' }
McpResolver >> resolveInContext: requestContext arguments: arguments [
	"Evaluate this resolver to produce a parameter value or input request marker.

	 Arguments:
		requestContext - <McpServerRequestContext> or nil.
		arguments - <KeyedCollection> current arguments dictionary.
	 Answers:
		<Object> resolved value or request marker (McpElicit, McpSample, McpListRoots)."

	^self block cull: requestContext cull: arguments
]
