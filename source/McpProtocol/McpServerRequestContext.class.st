"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# McpServerRequestContext

`McpServerRequestContext` carries authenticated request-scoped MCP server
metadata for both sessionful (legacy) and sessionless (modern) requests.

## Responsibilities

- Retain protocol version, client information, client capabilities, and
  transport requests.
- Hold multi-round-trip state (`inputResponses`, `requestState`) passed across
  retry rounds.
- Extract and expose caller progress tokens (`progressToken`).
- Provide incremental progress reporting via `reportProgress:total:message:`,
  evaluating an attached `progressReporter` block when a token is present.
- Transparently fall back to an active `session` when present, or use
  request-scoped properties during modern sessionless exchanges.
- Validate required protocol context without assuming a specific transport.

## Lifecycle and boundaries

One request owns the context; it is transient and must not outlive request
execution.
"
Class {
	#name : 'McpServerRequestContext',
	#superclass : 'Object',
	#instVars : [
		'sessionId',
		'protocolVersion',
		'clientInfo',
		'clientCapabilities',
		'principal',
		'metadata',
		'requestState',
		'inputResponses',
		'progressToken',
		'progressReporter',
		'session',
		'transportRequest',
		'logLevel'
	],
	#category : 'McpProtocol'
}

{ #category : 'Instance Creation' }
McpServerRequestContext class >> new [
	"Answer a new initialized server request context.

	 Answers:
		<McpServerRequestContext> initialized context."

	^super new initialize
]

{ #category : 'Testing' }
McpServerRequestContext >> canEmitLog [
	"Answer whether logging is permitted for this request (SEP-2575).
	 In modern protocol versions, servers MUST NOT emit notifications/message
	 unless the request included io.modelcontextprotocol/logLevel in _meta.

	 Answers:
		<Boolean>."

	^logLevel notNil
]

{ #category : 'Accessing' }
McpServerRequestContext >> clientCapabilities [
	"Answer capabilities negotiated for the current client.

	 Answers:
		<KeyedCollection>."

	clientCapabilities ifNotNil: [^clientCapabilities].
	self session ifNotNil: [^self session clientCapabilities].
	^nil
]

{ #category : 'Accessing' }
McpServerRequestContext >> clientCapabilities: aDictionary [
	"Set capabilities for the current client.

	 Arguments:
		aDictionary - <KeyedCollection>.
	 Answers:
		<McpServerRequestContext> the receiver."

	clientCapabilities := aDictionary.
	^self
]

{ #category : 'Accessing' }
McpServerRequestContext >> clientInfo [
	"Answer implementation information for the current client.

	 Answers:
		<KeyedCollection>."

	clientInfo ifNotNil: [^clientInfo].
	self session ifNotNil: [^self session clientInfo].
	^nil
]

{ #category : 'Accessing' }
McpServerRequestContext >> clientInfo: aDictionary [
	"Set implementation information for the current client.

	 Arguments:
		aDictionary - <KeyedCollection>.
	 Answers:
		<McpServerRequestContext> the receiver."

	clientInfo := aDictionary.
	^self
]

{ #category : 'Initialization',
  #vaVisibility : 'private' }
McpServerRequestContext >> initialize [
	"Initialize independent request-scoped metadata.

	 Answers:
		<McpServerRequestContext> the receiver."

	super initialize.
	metadata := EsOrderedDictionary new.
	^self
]

{ #category : 'Accessing' }
McpServerRequestContext >> inputResponses [
	"Answer client responses from an inputRequired multi-round-trip retry, or nil.

	 Answers:
		<KeyedCollection> or nil."

	^inputResponses
]

{ #category : 'Accessing' }
McpServerRequestContext >> inputResponses: aDictionary [
	"Set client responses for an inputRequired multi-round-trip retry.

	 Arguments:
		aDictionary - <KeyedCollection> or nil.
	 Answers:
		<McpServerRequestContext> the receiver."

	inputResponses := aDictionary.
	^self
]

{ #category : 'Accessing' }
McpServerRequestContext >> logLevel [
	"Answer the requested minimum logging level, or nil.

	 Answers:
		<String> or nil."

	^logLevel
]

{ #category : 'Accessing' }
McpServerRequestContext >> logLevel: aLevelString [
	"Set the requested minimum logging level.

	 Arguments:
		aLevelString - <String> or nil.
	 Answers:
		<McpServerRequestContext> the receiver."

	logLevel := aLevelString.
	^self
]

{ #category : 'Accessing' }
McpServerRequestContext >> metadata [
	"Answer mutable application metadata scoped to this request.

	 Answers:
		<KeyedCollection>."

	^metadata
]

{ #category : 'Accessing' }
McpServerRequestContext >> metadata: aDictionary [
	"Set detached top-level application metadata for this request.

	 Arguments:
		aDictionary - <KeyedCollection> metadata, or nil.
	 Answers:
		<McpServerRequestContext> the receiver."

	aDictionary ifNil: [
		metadata := EsOrderedDictionary new.
		^self].
	(aDictionary isKindOf: KeyedCollection)
		ifFalse: [self error: 'MCP request-context metadata must be keyed'].
	metadata := aDictionary copy.
	^self
]

{ #category : 'Accessing' }
McpServerRequestContext >> principal [
	"Answer the authenticated application principal, or nil.

	 Answers:
		<Object> or nil."

	^principal
]

{ #category : 'Accessing' }
McpServerRequestContext >> principal: anObject [
	"Set the authenticated principal supplied by the security layer.

	 Arguments:
		anObject - <Object> or nil.
	 Answers:
		<McpServerRequestContext> the receiver."

	principal := anObject.
	^self
]

{ #category : 'Accessing' }
McpServerRequestContext >> progressReporter [
	"Answer the optional progress reporting callback block.

	 Answers:
		<Block> or nil."

	^progressReporter
]

{ #category : 'Accessing' }
McpServerRequestContext >> progressReporter: aBlock [
	"Set the callback block evaluated when reportProgress: is called.

	 Arguments:
		aBlock - <Block> [:progressParams | ...], or nil.
	 Answers:
		<McpServerRequestContext> the receiver."

	(aBlock isNil or: [aBlock isKindOf: Block])
		ifFalse: [self error: 'Progress reporter must be a block or nil'].
	progressReporter := aBlock.
	^self
]

{ #category : 'Accessing' }
McpServerRequestContext >> progressToken [
	"Answer the progress token supplied by the caller for this request, or nil.

	 Answers:
		<String> or <Integer> or nil."

	^progressToken
]

{ #category : 'Accessing' }
McpServerRequestContext >> progressToken: aToken [
	"Set the progress token supplied by the caller for this request.

	 Arguments:
		aToken - <String> or <Integer> or nil.
	 Answers:
		<McpServerRequestContext> the receiver."

	progressToken := aToken.
	^self
]

{ #category : 'Accessing' }
McpServerRequestContext >> protocolVersion [
	"Answer the protocol version negotiated for the current session or request.

	 Answers:
		<String>."

	protocolVersion ifNotNil: [^protocolVersion].
	self session ifNotNil: [^self session protocolVersion].
	^nil
]

{ #category : 'Accessing' }
McpServerRequestContext >> protocolVersion: aString [
	"Set the protocol version for this request context.

	 Arguments:
		aString - <String>.
	 Answers:
		<McpServerRequestContext> the receiver."

	protocolVersion := aString.
	^self
]

{ #category : 'Protocol Operations' }
McpServerRequestContext >> reportProgress: aProgress [
	"Report incremental progress for this request. No-op if no progressToken was supplied.

	 Arguments:
		aProgress - <Number> current progress value.
	 Answers:
		<McpServerRequestContext> the receiver."

	^self reportProgress: aProgress total: nil message: nil
]

{ #category : 'Protocol Operations' }
McpServerRequestContext >> reportProgress: aProgress total: aTotal [
	"Report incremental progress with an expected total. No-op if no progressToken was supplied.

	 Arguments:
		aProgress - <Number> current progress value.
		aTotal - <Number> total expected progress.
	 Answers:
		<McpServerRequestContext> the receiver."

	^self reportProgress: aProgress total: aTotal message: nil
]

{ #category : 'Protocol Operations' }
McpServerRequestContext >> reportProgress: aProgress total: aTotal message: aMessage [
	"Report incremental progress for this request. No-op if no progressToken was supplied.

	 Arguments:
		aProgress - <Number> current progress amount.
		aTotal - <Number> or nil, total expected progress.
		aMessage - <String> or nil, human-readable progress status.
	 Answers:
		<McpServerRequestContext> the receiver."

	| token params |

	token := self progressToken.
	token ifNil: [^self].
	params :=
		EsOrderedDictionary new
			at: 'progressToken' put: token;
			at: 'progress' put: aProgress;
			yourself.
	aTotal ifNotNil: [params at: 'total' put: aTotal].
	aMessage ifNotNil: [params at: 'message' put: aMessage copy].
	self progressReporter ifNotNil: [:reporter | reporter cull: params].
	^self
]

{ #category : 'Accessing' }
McpServerRequestContext >> requestState [
	"Answer opaque state from an inputRequired multi-round-trip retry, or nil.

	 Answers:
		<String> or nil."

	^requestState
]

{ #category : 'Accessing' }
McpServerRequestContext >> requestState: aString [
	"Set opaque state for an inputRequired multi-round-trip retry.

	 Arguments:
		aString - <String> or nil.
	 Answers:
		<McpServerRequestContext> the receiver."

	requestState := aString.
	^self
]

{ #category : 'Session Management' }
McpServerRequestContext >> session [
	"Answer the established transport session.

	 Answers:
		<Object> session implementing the MCP session protocol."

	^session
]

{ #category : 'Session Management' }
McpServerRequestContext >> session: aSession [
	"Set an established session implementing the required protocol.

	 Arguments:
		aSession - <Object> MCP server session.
	 Answers:
		<McpServerRequestContext> the receiver."

	#(id protocolVersion clientInfo clientCapabilities) do: [:selector |
		(aSession respondsTo: selector)
			ifFalse: [self error: 'MCP request-context session is missing ' , selector asString]].
	session := aSession.
	^self
]

{ #category : 'Session Management' }
McpServerRequestContext >> sessionId [
	"Answer the opaque identifier of the current transport session, or nil.

	 Answers:
		<String> or nil."

	sessionId ifNotNil: [^sessionId].
	self session ifNotNil: [^self session id].
	^nil
]

{ #category : 'Session Management' }
McpServerRequestContext >> sessionId: aString [
	"Set the opaque identifier of the current transport session.

	 Arguments:
		aString - <String> or nil.
	 Answers:
		<McpServerRequestContext> the receiver."

	sessionId := aString.
	^self
]

{ #category : 'Accessing' }
McpServerRequestContext >> transportRequest [
	"Answer the underlying transport-specific request object.

	 Answers:
		<Object>."

	^transportRequest
]

{ #category : 'Accessing' }
McpServerRequestContext >> transportRequest: anObject [
	"Set the underlying transport-specific request object.

	 Arguments:
		anObject - <Object> transport request.
	 Answers:
		<McpServerRequestContext> the receiver."

	transportRequest := anObject.
	^self
]

{ #category : 'Validation' }
McpServerRequestContext >> validate [
	"Validate the required session or protocolVersion, and transport request.

	 Answers:
		<McpServerRequestContext> the receiver."

	(self session isNil and: [self protocolVersion isNil])
		ifTrue: [self error: 'MCP request context requires a session or protocolVersion'].
	self transportRequest ifNil: [self error: 'MCP request context requires a transport request'].
	^self
]
