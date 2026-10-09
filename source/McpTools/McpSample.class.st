"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# McpSample

`McpSample` is a request marker indicating that a tool resolver requires LLM sampling.

## Responsibilities

- Hold context messages and optional `maxTokens` limit.
- Convert to wire representation (`sampling/createMessage`).

## Lifecycle and boundaries

Transient value object returned by tool resolvers.
"
Class {
	#name : 'McpSample',
	#superclass : 'Object',
	#instVars : [
		'messages',
		'maxTokens'
	],
	#category : 'McpTools'
}

{ #category : 'Instance Creation' }
McpSample class >> messages: aCollection [
	"Answer a new sampling marker with context messages.

	 Arguments:
		aCollection - <Collection> of prompt messages.
	 Answers:
		<McpSample>."

	^self messages: aCollection maxTokens: nil
]

{ #category : 'Instance Creation' }
McpSample class >> messages: aCollection maxTokens: anInteger [
	"Answer a new sampling marker with context messages and token limit.

	 Arguments:
		aCollection - <Collection> of prompt messages.
		anInteger - <Integer> maximum tokens, or nil.
	 Answers:
		<McpSample>."

	^self new initializeMessages: aCollection maxTokens: anInteger
]

{ #category : 'Converting' }
McpSample >> asInputRequest [
	"Answer the MCP wire representation of this sampling request.

	 Answers:
		<KeyedCollection>."

	| params |

	params := EsOrderedDictionary with: 'messages' -> self messages.
	self maxTokens ifNotNil: [:tok | params at: 'maxTokens' put: tok].
	^EsOrderedDictionary new
		at: 'method' put: 'sampling/createMessage';
		at: 'params' put: params;
		yourself
]

{ #category : 'Initialization',
  #vaVisibility : 'private' }
McpSample >> initializeMessages: aCollection maxTokens: anInteger [
	"Initialize sampling properties.

	 Arguments:
		aCollection - <Collection>.
		anInteger - <Integer> or nil.
	 Answers:
		<McpSample> the receiver."

	super initialize.
	messages := aCollection copy.
	maxTokens := anInteger.
	^self
]

{ #category : 'Accessing' }
McpSample >> maxTokens [
	"Answer the optional maximum tokens limit.

	 Answers:
		<Integer> or nil."

	^maxTokens
]

{ #category : 'Accessing' }
McpSample >> messages [
	"Answer the context messages collection.

	 Answers:
		<Collection>."

	^messages
]
