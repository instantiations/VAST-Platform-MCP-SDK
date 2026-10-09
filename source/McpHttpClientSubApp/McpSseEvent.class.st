"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# McpSseEvent

`McpSseEvent` represents one decoded Server-Sent Event frame.

## Responsibilities

- Retain event type, identifier, retry value, and joined data text.
- Provide a mutable parser target before publication to consumers.

## Lifecycle and boundaries

A parser owns construction; consumers should treat events as values.
"
Class {
	#name : 'McpSseEvent',
	#superclass : 'Object',
	#instVars : [
		'type',
		'data',
		'id',
		'retry'
	],
	#category : 'McpHttpClientSubApp'
}

{ #category : 'Instance Creation' }
McpSseEvent class >> new [
	"Answer a new initialized SSE event.

	 Answers:
		<McpSseEvent>."

	^super new initialize
]

{ #category : 'Accessing' }
McpSseEvent >> data [
	"Answer a copy of the event payload.

	 Answers:
		<String>."

	^data copy
]

{ #category : 'Accessing' }
McpSseEvent >> data: aString [
	"Set the event payload.

	 Arguments:
		aString - <String> event data.
	 Answers:
		<McpSseEvent> the receiver."

	aString isString ifFalse: [self error: 'SSE event data must be a string'].
	data := aString copy.
	^self
]

{ #category : 'Accessing' }
McpSseEvent >> id [
	"Answer a copy of the last-event identifier.

	 Answers:
		<String>."

	^id copy
]

{ #category : 'Accessing' }
McpSseEvent >> id: aString [
	"Set a line-safe last-event identifier.

	 Arguments:
		aString - <String> event identifier.
	 Answers:
		<McpSseEvent> the receiver."

	aString isString ifFalse: [self error: 'SSE event identifier must be a string'].
	((aString includes: Character cr) or: [aString includes: Character lf])
		ifTrue: [self error: 'SSE event identifier must not contain line breaks'].
	(aString anySatisfy: [:character | character codePoint = 0])
		ifTrue: [self error: 'SSE event identifier must not contain null'].
	id := aString copy.
	^self
]

{ #category : 'Initialization',
  #vaVisibility : 'private' }
McpSseEvent >> initialize [
	"Initialize SSE event defaults.

	 Answers:
		<McpSseEvent> the receiver."

	super initialize.
	type := 'message'.
	data := ''.
	id := ''.
	retry := nil.
	^self
]

{ #category : 'Accessing' }
McpSseEvent >> retry [
	"Answer the optional reconnection delay in milliseconds.

	 Answers:
		<Integer> nonnegative delay, or nil."

	^retry
]

{ #category : 'Accessing' }
McpSseEvent >> retry: anInteger [
	"Set the optional reconnection delay in milliseconds.

	 Arguments:
		anInteger - <Integer> nonnegative delay, or nil.
	 Answers:
		<McpSseEvent> the receiver."

	(anInteger isNil or: [anInteger isInteger and: [anInteger >= 0]])
		ifFalse: [self error: 'SSE retry must be a nonnegative integer or nil'].
	retry := anInteger.
	^self
]

{ #category : 'Accessing' }
McpSseEvent >> type [
	"Answer a copy of the event type.

	 Answers:
		<String>."

	^type copy
]

{ #category : 'Accessing' }
McpSseEvent >> type: aString [
	"Set the nonempty event type.

	 Arguments:
		aString - <String> nonempty event type.
	 Answers:
		<McpSseEvent> the receiver."

	(aString isString and: [aString isEmpty not])
		ifFalse: [self error: 'SSE event type must be a nonempty string'].
	type := aString copy.
	^self
]
