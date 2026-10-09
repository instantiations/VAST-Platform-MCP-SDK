"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# McpBlockResource

`McpBlockResource` reads one concrete MCP resource through a configured
block.

## Responsibilities

- Pass request context to the resource implementation.
- Preserve the base resource definition and URI validation contract.

## Lifecycle and boundaries

Configuration is mutable; callers own block thread-safety.
"
Class {
	#name : 'McpBlockResource',
	#superclass : 'McpResource',
	#instVars : [
		'block'
	],
	#category : 'McpResources'
}

{ #category : 'Accessing' }
McpBlockResource >> block [
	"Answer the configured resource-reading block.

	 Answers:
		<Block>."

	^block
]

{ #category : 'Accessing' }
McpBlockResource >> block: aBlock [
	"Set a reading block accepting zero or one argument.

	 Arguments:
		aBlock - <Block> resource reader.
	 Answers:
		<McpBlockResource> the receiver."

	(aBlock isBlock and: [aBlock numArgs between: 0 and: 1])
		ifFalse: [self error: 'MCP resource block must accept zero or one argument'].
	block := aBlock.
	^self
]

{ #category : 'Execution' }
McpBlockResource >> readWithContext: requestContext [
	"Read the resource by evaluating the configured block.

	 The block may accept no arguments or requestContext. Its arity is
	 validated when the block is configured.

	 Arguments:
		requestContext - <McpServerRequestContext> or nil.
	 Answers:
		<KeyedCollection> MCP ReadResourceResult."

	block ifNil: [self error: 'MCP resource reading block is not configured'].
	^block cull: requestContext
]
