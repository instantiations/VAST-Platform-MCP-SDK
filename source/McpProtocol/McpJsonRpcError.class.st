"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# McpJsonRpcError

`McpJsonRpcError` carries a structured JSON-RPC error across MCP boundaries.

## Responsibilities

- Retain canonical numeric code, message text, and optional data.
- Produce detached protocol values without exposing mutable data.

## Lifecycle and boundaries

The exception owns its snapshot after construction and signaling.
"
Class {
	#name : 'McpJsonRpcError',
	#superclass : 'Error',
	#instVars : [
		'code',
		'data'
	],
	#category : 'McpProtocol'
}

{ #category : 'Signaling' }
McpJsonRpcError class >> signalCode: anInteger message: aString [
	"Construct and signal one validated JSON-RPC protocol error with no data.

	 Arguments:
		anInteger - <Integer> JSON-RPC error code.
		aString - <String> nonempty human-readable message.
	 Answers:
		<McpJsonRpcError>."

	^self signalCode: anInteger message: aString data: nil
]

{ #category : 'Signaling' }
McpJsonRpcError class >> signalCode: anInteger message: aString data: anObject [
	"Construct and signal one validated JSON-RPC protocol error.

	 Arguments:
		anInteger - <Integer> JSON-RPC error code.
		aString - <String> nonempty human-readable message.
		anObject - <Object> optional JSON-compatible error data.
	 Answers:
		<McpJsonRpcError>."

	anInteger isInteger ifFalse: [self error: 'JSON-RPC error code must be an integer'].
	(aString isString and: [aString isEmpty not])
		ifFalse: [self error: 'JSON-RPC error message must be nonempty'].
	^self new
		code: anInteger;
		messageText: aString copy;
		data: anObject;
		signal
]

{ #category : 'Accessing' }
McpJsonRpcError >> code [
	"Answer the JSON-RPC error code.

	 Answers:
		<Integer>."

	^code
]

{ #category : 'Accessing' }
McpJsonRpcError >> code: anInteger [
	"Set the JSON-RPC error code.

	 Arguments:
		anInteger - <Integer> error code.
	 Answers:
		<McpJsonRpcError> the receiver."

	anInteger isInteger ifFalse: [self error: 'JSON-RPC error code must be an integer'].
	code := anInteger.
	^self
]

{ #category : 'Accessing' }
McpJsonRpcError >> data [
	"Answer a detached copy of optional protocol error data.

	 Answers:
		<Object> JSON-compatible data, or nil."

	data ifNil: [^nil].
	^self detachedProtocolValue: data
]

{ #category : 'Accessing' }
McpJsonRpcError >> data: anObject [
	"Set optional JSON-compatible protocol error data.

	 Arguments:
		anObject - <Object> JSON-compatible data, or nil.
	 Answers:
		<McpJsonRpcError> the receiver."

	data := anObject ifNotNil: [self detachedProtocolValue: anObject].
	^self
]

{ #category : 'Serialization',
  #vaVisibility : 'private' }
McpJsonRpcError >> detachedProtocolValue: anObject [
	"Answer a detached JSON-compatible protocol value.

	 Arguments:
		anObject - <Object> protocol value.
	 Answers:
		<Object> detached value."

	^self detachedProtocolValue: anObject visited: IdentitySet new
]

{ #category : 'Serialization',
  #vaVisibility : 'private' }
McpJsonRpcError >> detachedProtocolValue: anObject visited: visitedObjects [
	"Copy protocol data while rejecting cycles and unsupported objects.

	 Arguments:
		anObject - <Object> value being copied.
		visitedObjects - <IdentitySet> active containers.
	 Answers:
		<Object> detached JSON-compatible value."

	| detached |

	anObject ifNil: [^nil].
	anObject isBoolean ifTrue: [^anObject].
	anObject isNumber ifTrue: [^anObject].
	anObject isString ifTrue: [^anObject copy].
	(visitedObjects includes: anObject) ifTrue: [self error: 'JSON-RPC error data contains a cycle'].
	(anObject isKindOf: KeyedCollection)
		ifTrue: [
			visitedObjects add: anObject.
			[
				detached := EsOrderedDictionary new.
				anObject keysAndValuesDo: [:key :value |
					key isString ifFalse: [self error: 'JSON-RPC error data keys must be strings'].
					detached
						at: key copy
						put: (self detachedProtocolValue: value visited: visitedObjects)]]
							ensure: [visitedObjects remove: anObject ifAbsent: []].
			^detached].
	(anObject isKindOf: SequenceableCollection)
		ifTrue: [
			visitedObjects add: anObject.
			[
				detached :=
					anObject
						collect: [:value | self detachedProtocolValue: value visited: visitedObjects]]
							ensure: [visitedObjects remove: anObject ifAbsent: []].
			^detached asArray].
	self error: 'JSON-RPC error data is not JSON-compatible'
]
