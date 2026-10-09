"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

State and detached identity for a legacy Streamable HTTP session.
The owning transport serializes lifecycle, active-request count and idle
timestamp access with its session mutex. Active requests prevent expiry.
The idle interval begins when the last active request finishes.
"
Class {
	#name : 'McpStreamableHttpSession',
	#superclass : 'Object',
	#instVars : [
		'id',
		'protocolVersion',
		'state',
		'clientInfo',
		'clientCapabilities',
		'idleSince',
		'inFlight'
	],
	#category : 'McpHttpServerSubApp'
}

{ #category : 'Instance Creation' }
McpStreamableHttpSession class >> id: sessionId protocolVersion: aProtocolVersion [
	"Answer a session with empty client metadata for compatibility.

	 Arguments:
		sessionId - <String> opaque session identifier.
		aProtocolVersion - <String> negotiated protocol version.
	 Answers:
		<McpStreamableHttpSession> initialized session."

	^self
		id: sessionId
		protocolVersion: aProtocolVersion
		clientInfo: EsOrderedDictionary new
		capabilities: EsOrderedDictionary new
]

{ #category : 'Instance Creation' }
McpStreamableHttpSession class >> id: sessionId
	protocolVersion: aProtocolVersion
	clientInfo: implementationInfo
	capabilities: capabilityDeclaration [
	"Answer a session retaining detached negotiated client metadata.

	 Arguments:
		sessionId - <String> opaque session identifier.
		aProtocolVersion - <String> negotiated protocol version.
		implementationInfo - <KeyedCollection> client implementation metadata.
		capabilityDeclaration - <KeyedCollection> client capabilities.
	 Answers:
		<McpStreamableHttpSession> initialized session."

	^self new
		initializeId: sessionId
		protocolVersion: aProtocolVersion
		clientInfo: implementationInfo
		capabilities: capabilityDeclaration
]

{ #category : 'Accessing' }
McpStreamableHttpSession >> activeRequestCount [
	"Answer the number of pinned requests; caller holds the session mutex.
	Answers:
		<Integer> nonnegative request count."
	^inFlight ifNil: [0]

]

{ #category : 'Resource Management' }
McpStreamableHttpSession >> beginRequestAt: seconds [
	"Pin a request while the owning transport holds its session mutex.
	Arguments:
		seconds - <Number> current clock seconds.
	Answers:
		<McpStreamableHttpSession> the receiver."
	inFlight := self activeRequestCount + 1.
	idleSince := seconds

]

{ #category : 'Accessing' }
McpStreamableHttpSession >> clientCapabilities [
	"Answer a detached snapshot of negotiated client capabilities.

	 Answers:
		<KeyedCollection> JSON-compatible capabilities."

	^self detachedJsonValue: clientCapabilities
]

{ #category : 'Accessing' }
McpStreamableHttpSession >> clientInfo [
	"Answer a detached snapshot of negotiated client information.

	 Answers:
		<KeyedCollection> JSON-compatible implementation metadata."

	^self detachedJsonValue: clientInfo
]

{ #category : 'Serialization',
  #vaVisibility : 'private' }
McpStreamableHttpSession >> detachedJsonValue: anObject [
	"Answer a detached JSON-compatible value.

	 Arguments:
		anObject - <Object> JSON-compatible value.
	 Answers:
		<Object> detached value."

	^self detachedJsonValue: anObject visited: IdentitySet new
]

{ #category : 'Serialization',
  #vaVisibility : 'private' }
McpStreamableHttpSession >> detachedJsonValue: anObject visited: visitedObjects [
	"Recursively copy JSON data while rejecting cycles and unsupported values.

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
	(visitedObjects includes: anObject) ifTrue: [self error: 'MCP session metadata contains a cycle'].
	(anObject isKindOf: KeyedCollection)
		ifTrue: [
			visitedObjects add: anObject.
			[
				detached := EsOrderedDictionary new.
				anObject keysAndValuesDo: [:key :value |
					key isString ifFalse: [self error: 'MCP session metadata keys must be strings'].
					detached
						at: key copy
						put: (self detachedJsonValue: value visited: visitedObjects)]]
							ensure: [visitedObjects remove: anObject ifAbsent: []].
			^detached].
	(anObject isKindOf: SequenceableCollection)
		ifTrue: [
			visitedObjects add: anObject.
			[
				detached :=
					anObject
						collect: [:value | self detachedJsonValue: value visited: visitedObjects]]
							ensure: [visitedObjects remove: anObject ifAbsent: []].
			^detached asArray].
	self error: 'MCP session metadata is not JSON-compatible'
]

{ #category : 'Resource Management' }
McpStreamableHttpSession >> endRequestAt: seconds [
	"Release one active request; the last release starts the idle interval.
	Arguments:
		seconds - <Number> current clock seconds.
	Answers:
		<McpStreamableHttpSession> the receiver."
	self activeRequestCount > 0
		ifFalse: [self error: 'MCP session request count underflow'].
	inFlight := inFlight - 1.
	inFlight = 0 ifTrue: [idleSince := seconds]

]

{ #category : 'Accessing' }
McpStreamableHttpSession >> id [
	"Answer a detached immutable session identifier.

	 Answers:
		<String>."

	^id copy
]

{ #category : 'Initialization',
  #vaVisibility : 'private' }
McpStreamableHttpSession >> initializeId: sessionId
	protocolVersion: aProtocolVersion
	clientInfo: implementationInfo
	capabilities: capabilityDeclaration [
	"Initialize immutable correlation and negotiated client metadata.

	 Arguments:
		sessionId - <String> opaque session identifier.
		aProtocolVersion - <String> negotiated protocol version.
		implementationInfo - <KeyedCollection> client information.
		capabilityDeclaration - <KeyedCollection> client capabilities.
	 Answers:
		<McpStreamableHttpSession> the receiver."

	(sessionId isString and: [sessionId isEmpty not])
		ifFalse: [self error: 'MCP session identifier must not be empty'].
	(aProtocolVersion isString and: [aProtocolVersion isEmpty not])
		ifFalse: [self error: 'MCP session protocol version must not be empty'].
	(implementationInfo isKindOf: KeyedCollection)
		ifFalse: [self error: 'MCP session client information must be keyed'].
	(capabilityDeclaration isKindOf: KeyedCollection)
		ifFalse: [self error: 'MCP session client capabilities must be keyed'].
	id := sessionId copy.
	protocolVersion := aProtocolVersion copy.
	clientInfo := self detachedJsonValue: implementationInfo.
	clientCapabilities := self detachedJsonValue: capabilityDeclaration.
	state := #initializing.
	^self
]

{ #category : 'Resource Management' }
McpStreamableHttpSession >> isIdleAt: seconds timeout: timeoutSeconds [
	"Test idle expiry, resetting the interval if the clock moves backward.
	Arguments:
		seconds - <Number> current clock seconds.
		timeoutSeconds - <Number | nil> positive idle timeout, nil disables.
	Answers:
		<Boolean>. Caller holds the owning transport's session mutex."
	self activeRequestCount > 0 ifTrue: [^false].
	(idleSince isNil or: [seconds < idleSince]) ifTrue: [idleSince := seconds].
	timeoutSeconds ifNil: [^false].
	^seconds - idleSince >= timeoutSeconds

]

{ #category : 'Session Management' }
McpStreamableHttpSession >> isInitializing [
	"Answer whether the initialized notification is still pending.

	 Answers:
		<Boolean>."

	^state == #initializing
]

{ #category : 'Session Management' }
McpStreamableHttpSession >> isReady [
	"Answer whether normal MCP operations may be dispatched.

	 Answers:
		<Boolean>."

	^state == #ready
]

{ #category : 'Session Management' }
McpStreamableHttpSession >> markReady [
	"Transition the session from initializing to ready.

	 Answers:
		<McpStreamableHttpSession>."

	self isInitializing ifFalse: [self error: 'MCP session is not awaiting initialization'].
	state := #ready.
	^self
]

{ #category : 'Accessing' }
McpStreamableHttpSession >> protocolVersion [
	"Answer a detached immutable negotiated protocol version.

	 Answers:
		<String>."

	^protocolVersion copy
]

{ #category : 'Session Management' }
McpStreamableHttpSession >> state [
	"Answer the lifecycle state.

	 Answers:
		<Symbol>."

	^state
]
