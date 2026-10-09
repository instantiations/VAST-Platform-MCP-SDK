"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# McpListRoots

`McpListRoots` is a request marker indicating that a tool resolver requires workspace roots.

## Responsibilities

- Convert to wire representation (`roots/list`).

## Lifecycle and boundaries

Transient value object returned by tool resolvers.
"
Class {
	#name : 'McpListRoots',
	#superclass : 'Object',
	#category : 'McpTools'
}

{ #category : 'Converting' }
McpListRoots >> asInputRequest [
	"Answer the MCP wire representation of this roots listing request.

	 Answers:
		<KeyedCollection>."

	^EsOrderedDictionary new
		at: 'method' put: 'roots/list';
		at: 'params' put: EsOrderedDictionary new;
		yourself
]
