"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# McpElicit

`McpElicit` is a request marker indicating that a tool resolver requires user input.

## Responsibilities

- Hold prompt message and optional requested input schema.
- Convert to wire representation (`elicitation/create`).

## Lifecycle and boundaries

Transient value object returned by tool resolvers.
"
Class {
	#name : 'McpElicit',
	#superclass : 'Object',
	#instVars : [
		'message',
		'schema'
	],
	#category : 'McpTools'
}

{ #category : 'Instance Creation' }
McpElicit class >> message: aString [
	"Answer a new elicitation marker with a prompt message.

	 Arguments:
		aString - <String> question to prompt the user with.
	 Answers:
		<McpElicit>."

	^self message: aString schema: nil
]

{ #category : 'Instance Creation' }
McpElicit class >> message: aString schema: aSchemaDictionary [
	"Answer a new elicitation marker with a prompt message and expected schema.

	 Arguments:
		aString - <String> question to prompt the user with.
		aSchemaDictionary - <KeyedCollection> or nil.
	 Answers:
		<McpElicit>."

	^self new initializeMessage: aString schema: aSchemaDictionary
]

{ #category : 'Converting' }
McpElicit >> asInputRequest [
	"Answer the MCP wire representation of this elicitation request.

	 Answers:
		<KeyedCollection>."

	| params |

	params := EsOrderedDictionary with: 'message' -> self message.
	self schema ifNotNil: [:s | params at: 'requestedSchema' put: s].
	^EsOrderedDictionary new
		at: 'method' put: 'elicitation/create';
		at: 'params' put: params;
		yourself
]

{ #category : 'Initialization',
  #vaVisibility : 'private' }
McpElicit >> initializeMessage: aString schema: aSchemaDictionary [
	"Initialize elicitation properties.

	 Arguments:
		aString - <String>.
		aSchemaDictionary - <KeyedCollection> or nil.
	 Answers:
		<McpElicit> the receiver."

	super initialize.
	message := aString copy.
	schema := aSchemaDictionary.
	^self
]

{ #category : 'Accessing' }
McpElicit >> message [
	"Answer the prompt message string.

	 Answers:
		<String>."

	^message
]

{ #category : 'Accessing' }
McpElicit >> schema [
	"Answer the requested schema, or nil.

	 Answers:
		<KeyedCollection> or nil."

	^schema
]
