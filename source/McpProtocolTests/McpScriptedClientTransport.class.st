"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# McpScriptedClientTransport

`McpScriptedClientTransport` is a deterministic client transport for unit
tests. It records protocol interactions and answers explicitly queued results.

## Responsibilities

- Record requests, notifications, and closure in transport order.
- Answer one queued result for each request.
- Expose recorded interactions without performing network I/O.

## Lifecycle and ownership

An `McpClient` owns each instance through the normal transport contract. A test
creates a fresh instance and queues every expected request result. The class is
mutable, performs no scheduling, and is not safe for concurrent mutation.
"
Class {
	#name : 'McpScriptedClientTransport',
	#superclass : 'McpClientTransport',
	#instVars : [
		'responses',
		'requests',
		'notifications',
		'interactions',
		'closed',
		'closeCount',
		'requestBlock'
	],
	#category : 'McpProtocolTests'
}

{ #category : 'Starting and Stopping' }
McpScriptedClientTransport >> close [
	"Record transport closure.

	 Answers:
		<McpScriptedClientTransport> the receiver."

	closed := true.
	closeCount := closeCount + 1.
	interactions add: (EsOrderedDictionary with: 'kind' -> 'close').
	^self
]

{ #category : 'Accessing' }
McpScriptedClientTransport >> closeCount [
	"Answer how many times the transport was closed.

	 Answers:
		<Integer>."

	^closeCount
]

{ #category : 'Accessing' }
McpScriptedClientTransport >> closed [
	"Answer whether the transport was closed at least once.

	 Answers:
		<Boolean>."

	^closed
]

{ #category : 'Test Support' }
McpScriptedClientTransport >> enqueueResponse: aResponse [
	"Queue one decoded result for the next request.

	 Arguments:
		aResponse - <Object> decoded JSON-compatible result.
	 Answers:
		<McpScriptedClientTransport> the receiver."

	responses add: aResponse.
	^self
]

{ #category : 'Initialization',
  #vaVisibility : 'private' }
McpScriptedClientTransport >> initialize [
	"Initialize empty scripts and interaction logs.

	 Answers:
		<McpScriptedClientTransport> the receiver."

	super initialize.
	responses := OrderedCollection new.
	requests := OrderedCollection new.
	notifications := OrderedCollection new.
	interactions := OrderedCollection new.
	closed := false.
	closeCount := 0.
	^self
]

{ #category : 'Accessing' }
McpScriptedClientTransport >> interactions [
	"Answer the ordered transport interaction log.

	 Answers:
		<OrderedCollection> of <KeyedCollection>."

	^interactions
]

{ #category : 'Accessing' }
McpScriptedClientTransport >> notifications [
	"Answer the notifications received by the transport.

	 Answers:
		<OrderedCollection> of <KeyedCollection>."

	^notifications
]

{ #category : 'Accessing' }
McpScriptedClientTransport >> requestBlock [
	"Answer the optional request observer block.

	 Answers:
		<Block> or nil."

	^requestBlock
]

{ #category : 'Accessing' }
McpScriptedClientTransport >> requestBlock: aBlock [
	"Set an optional request observer block evaluated when sendRequest:id: is called.

	 Arguments:
		aBlock - <Block> or nil.
	 Answers:
		<McpScriptedClientTransport> the receiver."

	requestBlock := aBlock.
	^self
]

{ #category : 'Accessing' }
McpScriptedClientTransport >> requests [
	"Answer the requests received by the transport.

	 Answers:
		<OrderedCollection> of <KeyedCollection>."

	^requests
]

{ #category : 'Protocol Operations' }
McpScriptedClientTransport >> sendNotification: aNotification [
	"Record one JSON-RPC notification.

	 Arguments:
		aNotification - <KeyedCollection> JSON-RPC notification.
	 Answers:
		<McpScriptedClientTransport> the receiver."

	notifications add: aNotification.
	interactions add: (
		EsOrderedDictionary new
			at: 'kind' put: 'notification';
			at: 'message' put: aNotification;
			yourself).
	^self
]

{ #category : 'Protocol Operations' }
McpScriptedClientTransport >> sendRequest: aRequest id: anIdentifier [
	"Record one request and answer its next scripted result.

	 Arguments:
		aRequest - <KeyedCollection> JSON-RPC request.
		anIdentifier - <String> or <Integer> correlation identifier.
	 Answers:
		<Object> the next scripted result."

	requests add: aRequest.
	interactions add: (
		EsOrderedDictionary new
			at: 'kind' put: 'request';
			at: 'message' put: aRequest;
			at: 'identifier' put: anIdentifier;
			yourself).
	requestBlock ifNotNil: [requestBlock cull: aRequest cull: anIdentifier].
	responses isEmpty ifTrue: [self error: 'No scripted MCP response remains'].
	^responses removeFirst
]
