"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# McpStreamableHttpTransport

`McpStreamableHttpTransport` manages Streamable HTTP exchanges across modern
sessionless and legacy session-based protocol eras.

## Responsibilities

- Handle `POST`, `GET`, and `DELETE` requests with representation validation.
- Enforce Host and Origin allowlists for DNS rebinding protection.
- Enforce Bearer token authentication via `authSettings`.
- Validate SEP-2243 parameter routing headers (`Mcp-Method`, `Mcp-Name`, `Mcp-Param-*`).
- Manage session lifecycle for pre-2026 clients.

## Lifecycle and boundaries

Owned by `McpHttpServer`. Thread-safe concurrent request dispatching.
"
Class {
	#name : 'McpStreamableHttpTransport',
	#superclass : 'McpHttpServerTransport',
	#instVars : [
		'sessions',
		'sessionMutex',
		'sessionIdleTimeout',
		'maxSessions',
		'sessionClock',
		'maintenanceProcess',
		'maintenanceStop',
		'pendingInitializations'
	],
	#pools : [
		'McpJsonRpcConstants'
	],
	#category : 'McpHttpServerSubApp'
}

{ #category : 'Instance Creation' }
McpStreamableHttpTransport class >> new [
	"Answer a transport initialized with secure defaults and empty sessions."

	^super new initialize
]

{ #category : 'Validation',
  #vaVisibility : 'private' }
McpStreamableHttpTransport >> acceptHeader: acceptHeader includesMediaType: requiredMediaType [
	"Answer whether Accept contains an exact base media type.

	 Parameters on a media range are ignored. Wildcards and token prefixes do
	 not satisfy an explicitly required MCP representation.

	 Arguments:
		acceptHeader - <String> comma-separated HTTP media ranges.
		requiredMediaType - <String> required base media type.
	 Answers:
		<Boolean>."

	acceptHeader isString ifFalse: [^false].
	^(acceptHeader subStrings: $,) anySatisfy: [:range | | mediaType separator |
		mediaType := range trimBlanks.
		separator := mediaType indexOf: $;.
		separator > 0 ifTrue: [mediaType := (mediaType copyFrom: 1 to: separator - 1) trimBlanks].
		mediaType sameAs: requiredMediaType]
]

{ #category : 'Resource Management' }
McpStreamableHttpTransport >> beginResponseForSessionNamed: identifier [
	"Pin a retained session during actual HTTP entity delivery.
	Arguments:
		identifier - <String | nil> response or request session identifier.
	Answers:
		<McpStreamableHttpSession | nil> pinned session."
	identifier ifNil: [^nil].
	^sessionMutex critical: [| session |
		session := sessions at: identifier ifAbsent: [nil].
		session ifNotNil: [session beginRequestAt: sessionClock value].
		session]

]

{ #category : 'Execution' }
McpStreamableHttpTransport >> capacityResponseFor: request [
	"Return the upstream JSON-RPC internal-error envelope with HTTP 503.
	Arguments:
		request - <SstHttpServletRequest> opening request.
	Answers:
		<String> JSON-RPC error body with a null request identifier."
	| payload json |
	payload := self dispatcher formatError: McpJsonRpcInternalErrorCode
		message: 'Too many open sessions' id: nil data: nil.
	json := String streamContents: [:out |
		(McpJSONWriter on: out) nextPut: payload].
	request header responseHeader status: '503 Service Unavailable';
		contentType: 'application/json'; contentLength: json asUtf8Bytes size.
	^json

]

{ #category : 'Resource Management' }
McpStreamableHttpTransport >> close [
	"Stop idle maintenance and discard retained sessions.
	Call after the listener has stopped admitting requests.
	Answers:
		<McpStreamableHttpTransport> the receiver."
	| processToStop |
	sessionMutex critical: [
		maintenanceStop := true.
		processToStop := maintenanceProcess.
		maintenanceProcess := nil.
		sessions removeAll].
	processToStop ifNotNil: [processToStop terminate]

]

{ #category : 'Resource Management' }
McpStreamableHttpTransport >> createSessionForProtocolVersion: protocolVersion
	clientInfo: implementationInfo
	capabilities: capabilityDeclaration [
	"Create and retain a session with negotiated client metadata.

	 Arguments:
		protocolVersion - <String> negotiated protocol version.
		implementationInfo - <KeyedCollection> client information.
		capabilityDeclaration - <KeyedCollection> client capabilities.
	 Answers:
		<McpStreamableHttpSession> retained session."

	| session |

	session :=
		McpStreamableHttpSession
			id: UUID new asString
			protocolVersion: protocolVersion
			clientInfo: implementationInfo
			capabilities: capabilityDeclaration.
	sessionMutex critical: [
		self expireIdleSessionsLocked.
		(maxSessions notNil and: [sessions size + pendingInitializations >=
			maxSessions])
			ifTrue: [^nil].
		session beginRequestAt: sessionClock value.
		session endRequestAt: sessionClock value.
		sessions at: session id put: session].
	^session

]

{ #category : 'Validation',
  #vaVisibility : 'private' }
McpStreamableHttpTransport >> decodeHeaderValue: aHeaderString [
	"Decode a header value if it uses the Base64 sentinel format =?base64?{value}?=.

	 Arguments:
		aHeaderString - <String> or nil.
	 Answers:
		<String> or nil."

	| b64 payloadBytes |

	aHeaderString ifNil: [^nil].
	(aHeaderString size >= 11 and: [
		(aHeaderString beginsWithSubCollection: '=?base64?')
			and: [(aHeaderString copyFrom: aHeaderString size - 1 to: aHeaderString size) = '?=']])
				ifFalse: [^aHeaderString].
	b64 := aHeaderString copyFrom: 10 to: aHeaderString size - 2.
	payloadBytes := [Base64Coder current decodeAsByteArray: b64] on: Error do: [:e | ^aHeaderString].
	^[(UnicodeString utf8: payloadBytes) asString] on: Error do: [:e | payloadBytes asString]
]

{ #category : 'Formatting',
  #vaVisibility : 'private' }
McpStreamableHttpTransport >> encodeHeaderValue: aString [
	"Encode a string value using the Base64 sentinel format =?base64?{value}?=
	 if it contains non-ASCII characters, control characters, leading/trailing whitespace,
	 or matches the sentinel prefix/suffix.

	 Arguments:
		aString - <String>.
	 Answers:
		<String> plain ASCII or sentinel-encoded header value."

	| str needsEncoding b64 |

	aString ifNil: [^''].
	str := aString isString ifTrue: [aString] ifFalse: [aString printString].
	str isEmpty ifTrue: [^''].
	needsEncoding :=
		(str first = $  or: [str last = $ ]) or: [
			(str anySatisfy: [:c | c codePoint < 16r20 or: [c codePoint > 16r7E]]) or: [
				(str size >= 11 and: [
					(str beginsWithSubCollection: '=?base64?')
						and: [(str copyFrom: str size - 1 to: str size) = '?=']])]].
	needsEncoding ifFalse: [^(str asEsString ifNil: [str asString])].
	b64 := (Base64Coder current encode: str asUtf8Bytes) asString.
	^'=?base64?' , b64 , '?='
]

{ #category : 'Resource Management' }
McpStreamableHttpTransport >> endResponseForSession: session [
	"Release a delivery pin after successful or failed entity writing.
	Arguments:
		session - <McpStreamableHttpSession | nil> pin returned by begin.
	Answers:
		<McpStreamableHttpTransport> the receiver."
	session ifNotNil: [
		sessionMutex critical: [session endRequestAt: sessionClock value]]

]

{ #category : 'Resource Management' }
McpStreamableHttpTransport >> expireIdleSessions [
	"Remove expired idle sessions without expiring work in progress.
	Answers:
		<Integer> number of sessions removed."
	^sessionMutex critical: [self expireIdleSessionsLocked]

]

{ #category : 'Resource Management',
  #vaVisibility : 'private' }
McpStreamableHttpTransport >> expireIdleSessionsLocked [
	"Reap under sessionMutex, using one clock sample for this pass.
	Answers:
		<Integer> expired session count."
	| now expired |
	now := sessionClock value.
	expired := OrderedCollection new.
	sessions keysAndValuesDo: [:identifier :session |
		(session isIdleAt: now timeout: sessionIdleTimeout)
			ifTrue: [expired add: identifier]].
	expired do: [:identifier | sessions removeKey: identifier].
	^expired size

]

{ #category : 'Formatting',
  #vaVisibility : 'private' }
McpStreamableHttpTransport >> formatAcceptedResponseFor: aRequest [
	"Format an empty 202 Accepted response.

	 Arguments:
		aRequest - <SstHttpServletRequest>.
	 Answers:
		<String>."

	aRequest header responseHeader
		status: '202 Accepted';
		contentLength: 0.
	^''
]

{ #category : 'Formatting',
  #vaVisibility : 'private' }
McpStreamableHttpTransport >> formatHeaderMismatchErrorFor: aRequest message: parsedRequest header: aHeaderName [
	"Format a 400 Bad Request response with JSON-RPC error -32020 HeaderMismatch."

	| id errorResponse jsonResponse |

	id :=
		(parsedRequest isKindOf: KeyedCollection)
			ifTrue: [parsedRequest at: 'id' ifAbsent: [nil]]
			ifFalse: [nil].
	errorResponse :=
		self dispatcher
			formatError: -32020
			message: 'Header mismatch for ' , aHeaderName
			id: id
			data: nil.
	jsonResponse :=
		String streamContents: [:stream | (McpJSONWriter on: stream) nextPut: errorResponse].
	aRequest header responseHeader
		status: '400 Bad Request';
		contentType: 'application/json';
		contentLength: jsonResponse asUtf8Bytes size.
	^jsonResponse
]

{ #category : 'Formatting',
  #vaVisibility : 'private' }
McpStreamableHttpTransport >> formatParseErrorFor: aRequest [
	"Format a JSON-RPC parse-error response.

	 Arguments:
		aRequest - <SstHttpServletRequest>.
	 Answers:
		<String>."

	| err response json |

	err := EsOrderedDictionary new.
	err at: 'code' put: McpJsonRpcParseErrorCode.
	err at: 'message' put: 'Parse error'.
	response := EsOrderedDictionary new.
	response at: 'jsonrpc' put: '2.0'.
	response at: 'id' put: nil.
	response at: 'error' put: err.
	json := String streamContents: [:stream | (McpJSONWriter on: stream) nextPut: response].
	aRequest header responseHeader
		status: '400 Bad Request';
		contentType: 'application/json';
		contentLength: json asUtf8Bytes size.
	^json
]

{ #category : 'Formatting',
  #vaVisibility : 'private' }
McpStreamableHttpTransport >> formatSuccessResponseFor: aRequest payload: dispatcherResponse [
	"Format a JSON-RPC response as UTF-8 JSON with HTTP status 200.

	 Arguments:
		aRequest - <SstHttpServletRequest>.
		dispatcherResponse - <Object>.
	 Answers:
		<String>."

	| jsonResponse |

	jsonResponse :=
		String streamContents: [:stream | (McpJSONWriter on: stream) nextPut: dispatcherResponse].
	aRequest header responseHeader
		status: '200 OK';
		contentType: 'application/json';
		contentLength: jsonResponse asUtf8Bytes size.
	^jsonResponse
]

{ #category : 'Formatting',
  #vaVisibility : 'private' }
McpStreamableHttpTransport >> formatUnsupportedProtocolVersionErrorFor: aRequest message: parsedRequest requested: aVersionString [
	"Format a 400 Bad Request response with JSON-RPC error -32022 UnsupportedProtocolVersion."

	| id errorData errorResponse jsonResponse supported |

	id :=
		(parsedRequest isKindOf: KeyedCollection)
			ifTrue: [parsedRequest at: 'id' ifAbsent: [nil]]
			ifFalse: [nil].
	supported :=
		self dispatcher server
			ifNotNil: [:s | s supportedProtocolVersions]
			ifNil: [McpProtocolVersion supportedProtocolVersions].
	errorData :=
		EsOrderedDictionary new
			at: 'supported' put: supported;
			at: 'requested' put: aVersionString;
			yourself.
	errorResponse :=
		self dispatcher
			formatError: -32022
			message: 'Unsupported protocol version'
			id: id
			data: errorData.
	jsonResponse :=
		String streamContents: [:stream | (McpJSONWriter on: stream) nextPut: errorResponse].
	aRequest header responseHeader
		status: '400 Bad Request';
		contentType: 'application/json';
		contentLength: jsonResponse asUtf8Bytes size.
	^jsonResponse
]

{ #category : 'Execution' }
McpStreamableHttpTransport >> handleDeleteRequest: aRequest [
	"Terminate the identified MCP Streamable HTTP session.

	 Arguments:
		aRequest - <SstHttpServletRequest>.
	 Answers:
		<String> empty HTTP response entity."

	| validationResult session removedSession |

	validationResult := self validateHostFor: aRequest.
	validationResult ifNotNil: [^validationResult].
	validationResult := self validateOriginFor: aRequest.
	validationResult ifNotNil: [^validationResult].
	validationResult := self validateAuthenticationFor: aRequest.
	validationResult ifNotNil: [^validationResult].
	session := self sessionForRequest: aRequest.
	session ifNil: [^''].
	validationResult := self validateProtocolVersionFor: aRequest session: session.
	validationResult ifNotNil: [^validationResult].
	removedSession := self removeSessionNamed: session id.
	removedSession ifNil: [
		aRequest header responseHeader
			status: '404 Not Found';
			contentLength: 0.
		^''].
	aRequest header responseHeader
		status: '204 No Content';
		contentLength: 0.
	^''
]

{ #category : 'Execution' }
McpStreamableHttpTransport >> handleGetRequest: aRequest [
	"Reject unsupported standalone SSE streams after validating Origin.

	 Arguments:
		aRequest - <SstHttpServletRequest>.
	 Answers:
		<String> empty HTTP response entity."

	| validationResult |

	validationResult := self validateHostFor: aRequest.
	validationResult ifNotNil: [^validationResult].
	validationResult := self validateOriginFor: aRequest.
	validationResult ifNotNil: [^validationResult].
	validationResult := self validateAuthenticationFor: aRequest.
	validationResult ifNotNil: [^validationResult].
	aRequest header responseHeader
		status: '405 Method Not Allowed';
		contentLength: 0.
	aRequest header responseHeader at: 'Allow' put: 'POST, DELETE'.
	^''
]

{ #category : 'Execution' }
McpStreamableHttpTransport >> handleInitializeRequest: aRequest message: parsedRequest [
	"Reserve capacity before dispatch, pin the opening, and roll back failures.
	Arguments:
		aRequest - <SstHttpServletRequest> HTTP request.
		parsedRequest - <KeyedCollection> initialize message.
	Answers:
		<String> serialized response, or HTTP 503 when capacity is full."
	| dispatcherResponse result parameters session completed reserved body |
	((self sessionIdFrom: aRequest) notNil or: [
		(parsedRequest includesKey: 'id') not]) ifTrue: [
			aRequest header responseHeader
				status: '400 Bad Request'; contentLength: 0.
			^''].
	self reserveSessionSlot ifFalse: [^self capacityResponseFor: aRequest].
	reserved := true.
	session := nil.
	completed := false.
	[
		dispatcherResponse := self dispatcher dispatch: parsedRequest.
		(dispatcherResponse includesKey: 'error') ifTrue: [
			^self formatSuccessResponseFor: aRequest payload:
				dispatcherResponse].
		result := dispatcherResponse at: 'result'.
		parameters := parsedRequest at: 'params'.
		session := McpStreamableHttpSession id: UUID new asString
			protocolVersion: (result at: 'protocolVersion')
			clientInfo: (parameters at: 'clientInfo')
			capabilities: (parameters at: 'capabilities').
		sessionMutex critical: [
			session beginRequestAt: sessionClock value.
			sessions at: session id put: session.
			pendingInitializations := pendingInitializations - 1.
			reserved := false].
		aRequest header responseHeader at: 'MCP-Session-Id' put: session id.
		body := self formatSuccessResponseFor: aRequest payload:
			dispatcherResponse.
		completed := true.
		^body
	] ensure: [
		sessionMutex critical: [
			reserved ifTrue: [pendingInitializations := pendingInitializations -
				1].
			session ifNotNil: [
				session activeRequestCount > 0 ifTrue: [
					session endRequestAt: sessionClock value].
				completed ifFalse: [sessions removeKey: session id ifAbsent:
				[]]]]]

]

{ #category : 'Message Handling',
  #vaVisibility : 'private' }
McpStreamableHttpTransport >> handleModernPostRequest: aRequest message: parsedRequest [
	"Dispatch one modern sessionless message with routing and param header validation.

	 Arguments:
		aRequest - <SstHttpServletRequest> HTTP request.
		parsedRequest - <KeyedCollection> decoded JSON-RPC message.
	 Answers:
		<String> or <Block> HTTP response entity."

	| requestContext dispatcherResponse routingError paramError metaError isListen hasProgress accept |

	(parsedRequest isKindOf: KeyedCollection)
		ifFalse: [
			aRequest header responseHeader
				status: '400 Bad Request';
				contentLength: 0.
			^''].
	routingError := self validateRoutingHeadersFor: aRequest message: parsedRequest.
	routingError ifNotNil: [^routingError].
	paramError := self validateMcpParamHeadersFor: aRequest message: parsedRequest.
	paramError ifNotNil: [^paramError].
	metaError := self validateModernMetaFor: aRequest message: parsedRequest.
	metaError ifNotNil: [^metaError].
	(parsedRequest includesKey: 'id')
		ifFalse: [
			requestContext := self modernRequestContextFor: aRequest message: parsedRequest.
			self dispatcher dispatch: parsedRequest context: requestContext.
			aRequest header responseHeader
				status: '202 Accepted';
				contentLength: 0.
			^''].

	isListen := (parsedRequest at: 'method' ifAbsent: [nil]) = 'subscriptions/listen'.
	(isListen and: [aRequest isKindOf: SstHttpServletRequest])
		ifTrue: [
			aRequest header responseHeader
				status: '200 OK';
				contentType: 'text/event-stream; charset=utf-8';
				at: 'Cache-Control' put: 'no-cache';
				at: 'Connection' put: 'keep-alive'.
			^[:connection |
				self streamSubscriptionsListen: parsedRequest on: connection request: aRequest]].

	hasProgress := false.
	(parsedRequest isKindOf: KeyedCollection)
		ifTrue: [
			(parsedRequest at: 'params' ifAbsent: [nil]) ifNotNil: [:p |
				(p isKindOf: KeyedCollection)
					ifTrue: [
						(p at: '_meta' ifAbsent: [nil]) ifNotNil: [:m |
							(m isKindOf: KeyedCollection)
								ifTrue: [
									(m includesKey: 'progressToken') ifTrue: [hasProgress := true]]].
						(p includesKey: 'progressToken') ifTrue: [hasProgress := true]]]].

	accept := aRequest getHeader: 'Accept'.
	(hasProgress and: [self acceptHeader: accept includesMediaType: 'text/event-stream'])
		ifTrue: [
			aRequest header responseHeader
				status: '200 OK';
				contentType: 'text/event-stream; charset=utf-8';
				at: 'Cache-Control' put: 'no-cache';
				at: 'Connection' put: 'keep-alive'.
			^[:connection |
				self
					streamToolCallWithProgress: parsedRequest
					on: connection
					request: aRequest
					session: nil]].

	requestContext := self modernRequestContextFor: aRequest message: parsedRequest.
	dispatcherResponse := self dispatcher dispatch: parsedRequest context: requestContext.
	dispatcherResponse ifNil: [^self formatAcceptedResponseFor: aRequest].
	^self formatSuccessResponseFor: aRequest payload: dispatcherResponse
]

{ #category : 'Execution' }
McpStreamableHttpTransport >> handlePostRequest: aRequest [
	"Process one MCP message over the Streamable HTTP POST endpoint.

	 Successful initialization creates a server session. Every later message
	 must identify that session, use its negotiated protocol version, and
	 respect its initialization state.
	 Modern protocol versions (2026-07-28+) are sessionless.

	 Arguments:
		aRequest - <SstHttpServletRequest>.
	 Answers:
		<String> HTTP response entity."

	| parsedRequest validationResult session protocolVersion |

	validationResult := self validateHeadersFor: aRequest.
	validationResult ifNotNil: [^validationResult].
	validationResult := self validateAuthenticationFor: aRequest.
	validationResult ifNotNil: [^validationResult].
	parsedRequest := self parseRequestBody: aRequest.
	(parsedRequest isKindOf: String) ifTrue: [^parsedRequest].
	validationResult := self validateProtocolVersionFor: aRequest parsedRequest:
		parsedRequest.
	validationResult ifNotNil: [^validationResult].

	protocolVersion := aRequest getHeader: 'MCP-Protocol-Version'.
	protocolVersion ifNil: [protocolVersion := aRequest getHeader:
		'mcp-protocol-version'].
	(McpProtocolVersion isModern: protocolVersion)
		ifTrue: [^self handleModernPostRequest: aRequest message:
			parsedRequest].

	(self isInitializeRequest: parsedRequest)
		ifTrue: [^self handleInitializeRequest: aRequest message:
			parsedRequest].

	session := self sessionForRequest: aRequest.
	session ifNil: [^''].
	validationResult := self validateProtocolVersionFor: aRequest session:
		session.
	validationResult ifNotNil: [^validationResult].
	^self withSession: session request: aRequest do: [
		self handleSessionMessage: parsedRequest request: aRequest session:
			session]

]

{ #category : 'Message Handling',
  #vaVisibility : 'private' }
McpStreamableHttpTransport >> handleSessionMessage: parsedRequest request: aRequest session: session [
	"Dispatch one message with session lifecycle and request context.

	 Arguments:
		parsedRequest - <KeyedCollection> decoded JSON-RPC message.
		aRequest - <SstHttpServletRequest> HTTP request.
		session - <McpStreamableHttpSession> identified session.
	 Answers:
		<String> HTTP response entity."

	| method dispatcherResponse errorResponse requestContext hasProgress accept |

	method :=
		(parsedRequest isKindOf: KeyedCollection)
			ifTrue: [parsedRequest at: 'method' ifAbsent: [nil]]
			ifFalse: [nil].
	requestContext := self requestContextFor: aRequest session: session.
	(session isInitializing and: [method = 'notifications/initialized'])
		ifTrue: [
			(parsedRequest includesKey: 'id')
				ifTrue: [
					aRequest header responseHeader
						status: '400 Bad Request';
						contentLength: 0.
					^''].
			dispatcherResponse := self dispatcher dispatch: parsedRequest context: requestContext.
			dispatcherResponse
				ifNotNil: [^self formatSuccessResponseFor: aRequest payload: dispatcherResponse].
			self markSessionReady: session.
			^self formatAcceptedResponseFor: aRequest].
	(session isInitializing and: [method notNil and: [method ~= 'ping']])
		ifTrue: [
			(parsedRequest includesKey: 'id')
				ifFalse: [
					aRequest header responseHeader
						status: '400 Bad Request';
						contentLength: 0.
					^''].
			errorResponse :=
				self dispatcher
					formatError: McpServerNotInitializedErrorCode
					message: 'Server not initialized'
					id: (parsedRequest at: 'id')
					data: nil.
			^self formatSuccessResponseFor: aRequest payload: errorResponse].

	hasProgress := false.
	(parsedRequest isKindOf: KeyedCollection)
		ifTrue: [
			(parsedRequest at: 'params' ifAbsent: [nil]) ifNotNil: [:p |
				(p isKindOf: KeyedCollection)
					ifTrue: [
						(p at: '_meta' ifAbsent: [nil]) ifNotNil: [:m |
							(m isKindOf: KeyedCollection)
								ifTrue: [
									(m includesKey: 'progressToken') ifTrue: [hasProgress := true]]].
						(p includesKey: 'progressToken') ifTrue: [hasProgress := true]]]].

	accept := aRequest getHeader: 'Accept'.
	(hasProgress and: [self acceptHeader: accept includesMediaType: 'text/event-stream'])
		ifTrue: [
			aRequest header responseHeader
				status: '200 OK';
				contentType: 'text/event-stream; charset=utf-8';
				at: 'Cache-Control' put: 'no-cache';
				at: 'Connection' put: 'keep-alive'.
			^[:connection |
				self
					streamToolCallWithProgress: parsedRequest
					on: connection
					request: aRequest
					session: session]].

	dispatcherResponse := self dispatcher dispatch: parsedRequest context: requestContext.
	dispatcherResponse ifNil: [^self formatAcceptedResponseFor: aRequest].
	^self formatSuccessResponseFor: aRequest payload: dispatcherResponse
]

{ #category : 'Initialization',
  #vaVisibility : 'private' }
McpStreamableHttpTransport >> initialize [
	"Initialize origin and host policies, session storage, and request limits.

	 Answers:
		<McpStreamableHttpTransport> the receiver."

	super initialize.
	allowedOrigins := Set new.
	allowedHosts := Set new.
	sessions := Dictionary new.
	sessionMutex := Semaphore forMutualExclusion.
	maximumRequestSize := 10 * 1024 * 1024.
	requestContextFactory := nil.
	sessionIdleTimeout := 1800.
	maxSessions := 10000.
	sessionClock := [DateAndTime now asUnixTime].
	pendingInitializations := 0.
	maintenanceStop := false.
	^self

]

{ #category : 'Accessing',
  #vaVisibility : 'private' }
McpStreamableHttpTransport >> isInitializeRequest: parsedRequest [
	"Answer whether a decoded message is an initialize request.

	 Arguments:
		parsedRequest - <Object> decoded JSON value.
	 Answers:
		<Boolean>."

	^(parsedRequest isKindOf: KeyedCollection)
		and: [(parsedRequest at: 'method' ifAbsent: [nil]) = 'initialize']
]

{ #category : 'Session Management',
  #vaVisibility : 'private' }
McpStreamableHttpTransport >> markSessionReady: session [
	"Atomically transition a retained session to ready.

	 Arguments:
		session - <McpStreamableHttpSession> retained session.
	 Answers:
		<McpStreamableHttpSession>."

	sessionMutex critical: [
		(sessions at: session id ifAbsent: [nil]) == session
			ifFalse: [self error: 'MCP session expired during initialization'].
		session markReady].
	^session
]

{ #category : 'Accessing' }
McpStreamableHttpTransport >> maxSessions [
	"Answer the maximum retained legacy sessions; nil disables the limit.
	Answers:
		<Number | nil> configured limit."
	^maxSessions

]

{ #category : 'Configuration' }
McpStreamableHttpTransport >> maxSessions: limit [
	"Set the maximum retained legacy sessions; nil disables it.
	Arguments:
		limit - <Number | nil> positive finite limit.
	Answers:
		<McpStreamableHttpTransport> the receiver."
	(limit isNil or: [(limit isInteger and: [limit > 0])])
		ifFalse: [self error: 'Invalid maxSessions'].
	sessionMutex critical: [maxSessions := limit]

]

{ #category : 'Session Management',
  #vaVisibility : 'private' }
McpStreamableHttpTransport >> modernRequestContextFor: aRequest message: parsedRequest [
	"Build and validate request-scoped state for one modern (sessionless) message.

	 Arguments:
		aRequest - <SstHttpServletRequest> HTTP request.
		parsedRequest - <KeyedCollection> parsed JSON-RPC message.
	 Answers:
		<McpServerRequestContext> validated request context."

	| context params meta |

	context :=
		requestContextFactory
			ifNil: [McpServerRequestContext new]
			ifNotNil: [requestContextFactory value: aRequest value: nil].
	(context isKindOf: McpServerRequestContext)
		ifFalse: [self error: 'MCP request-context factory returned an invalid context'].
	context transportRequest: aRequest.
	context protocolVersion: '2026-07-28'.
	params :=
		(parsedRequest isKindOf: KeyedCollection)
			ifTrue: [parsedRequest at: 'params' ifAbsent: [nil]]
			ifFalse: [nil].
	(params isKindOf: KeyedCollection)
		ifTrue: [
			meta := params at: '_meta' ifAbsent: [nil].
			(meta isKindOf: KeyedCollection)
				ifTrue: [
					(meta at: 'io.modelcontextprotocol/clientInfo' ifAbsent: [nil])
						ifNotNil: [:info | context clientInfo: info].
					(meta at: 'io.modelcontextprotocol/clientCapabilities' ifAbsent: [nil])
						ifNotNil: [:caps | context clientCapabilities: caps].
					(meta at: 'io.modelcontextprotocol/logLevel' ifAbsent: [nil])
						ifNotNil: [:level | context logLevel: level]]].
	context validate.
	^context
]

{ #category : 'Parsing',
  #vaVisibility : 'private' }
McpStreamableHttpTransport >> parseRequestBody: aRequest [
	"Decode and parse a bounded UTF-8 JSON request body.

	 Arguments:
		aRequest - <SstHttpServletRequest>.
	 Answers:
		<Object> decoded JSON value, or a formatted error response."

	| bodyBytes bodyString parsedRequest |

	bodyBytes := aRequest contents asByteArray.
	bodyBytes size > self maximumRequestSize
		ifTrue: [
			aRequest header responseHeader
				status: '413 Payload Too Large';
				contentLength: 0.
			^''].
	bodyString := (UnicodeString utf8: bodyBytes) asString.
	[parsedRequest := McpJSONReader fromString: bodyString]
		on: NeoJSONParseError
		do: [:parseError | ^self formatParseErrorFor: aRequest].
	^parsedRequest
]

{ #category : 'Session Management',
  #vaVisibility : 'private' }
McpStreamableHttpTransport >> removeSessionNamed: sessionId [
	"Remove and answer a session, or answer nil when it is unknown.

	 Arguments:
		sessionId - <String> opaque session identifier.
	 Answers:
		<McpStreamableHttpSession> or nil."

	^sessionMutex critical: [sessions removeKey: sessionId ifAbsent: [nil]]
]

{ #category : 'Accessing',
  #vaVisibility : 'private' }
McpStreamableHttpTransport >> requestContextFor: aRequest session: session [
	"Build and validate request-scoped state for one session message.

	 Arguments:
		aRequest - <SstHttpServletRequest> HTTP request.
		session - <McpStreamableHttpSession> identified session.
	 Answers:
		<McpServerRequestContext> validated request context."

	| context |

	context :=
		requestContextFactory
			ifNil: [McpServerRequestContext new]
			ifNotNil: [requestContextFactory value: aRequest value: session].
	(context isKindOf: McpServerRequestContext)
		ifFalse: [self error: 'MCP request-context factory returned an invalid context'].
	context
		session: session;
		transportRequest: aRequest;
		validate.
	^context
]

{ #category : 'Resource Management',
  #vaVisibility : 'private' }
McpStreamableHttpTransport >> reserveSessionSlot [
	"Atomically reserve admission before dispatching initialization.
	Answers:
		<Boolean> false when the configured limit has been reached."
	^sessionMutex critical: [
		self expireIdleSessionsLocked.
		(maxSessions notNil and: [
			sessions size + pendingInitializations >= maxSessions])
			ifTrue: [false]
			ifFalse: [pendingInitializations := pendingInitializations + 1.
				true]]

]

{ #category : 'Configuration' }
McpStreamableHttpTransport >> sessionClock: clockBlock [
	"Install a deterministic or monotonic clock before creating sessions.
	Arguments:
		clockBlock - <Block> zero arguments, answers seconds as a Number.
	Answers:
		<McpStreamableHttpTransport> the receiver."
	(clockBlock isBlock and: [clockBlock numArgs = 0])
		ifFalse: [self error: 'Session clock must be a zero-argument block'].
	sessionMutex critical: [
		(sessions isEmpty and: [pendingInitializations = 0])
			ifFalse: [self error:
				'Set the session clock before creating sessions'].
		sessionClock := clockBlock]

]

{ #category : 'Accessing' }
McpStreamableHttpTransport >> sessionCount [
	"Answer retained session count after synchronously expiring idle entries.
	Answers:
		<Integer> current session count."
	^sessionMutex critical: [self expireIdleSessionsLocked. sessions size]

]

{ #category : 'Session Management',
  #vaVisibility : 'private' }
McpStreamableHttpTransport >> sessionForRequest: aRequest [
	"Answer the identified server session and configure failures on response.

	 A missing session produces HTTP 400. An unknown or expired session
	 produces HTTP 404 so the client can begin a new initialization exchange.

	 Arguments:
		aRequest - <SstHttpServletRequest>.
	 Answers:
		<McpStreamableHttpSession> or nil."

	| sessionId session |

	sessionId := self sessionIdFrom: aRequest.
	(sessionId isString and: [sessionId isEmpty not])
		ifFalse: [
			aRequest header responseHeader
				status: '400 Bad Request';
				contentLength: 0.
			^nil].
	session := self sessionNamed: sessionId ifAbsent: [nil].
	session ifNil: [
		aRequest header responseHeader
			status: '404 Not Found';
			contentLength: 0].
	^session
]

{ #category : 'Session Management',
  #vaVisibility : 'private' }
McpStreamableHttpTransport >> sessionIdFrom: aRequest [
	"Answer the case-insensitive MCP session header value.

	 Arguments:
		aRequest - <SstHttpServletRequest>.
	 Answers:
		<String> or nil."

	| sessionId |

	sessionId := aRequest getHeader: 'MCP-Session-Id'.
	sessionId ifNil: [sessionId := aRequest getHeader: 'mcp-session-id'].
	^sessionId
]

{ #category : 'Accessing' }
McpStreamableHttpTransport >> sessionIdleTimeout [
	"Answer the idle timeout in seconds; nil disables the limit.
	Answers:
		<Number | nil> configured limit."
	^sessionIdleTimeout

]

{ #category : 'Configuration' }
McpStreamableHttpTransport >> sessionIdleTimeout: limit [
	"Set the idle timeout in seconds; nil disables it.
	Arguments:
		limit - <Number | nil> positive finite limit.
	Answers:
		<McpStreamableHttpTransport> the receiver."
	(limit isNil or: [(limit isNumber and: [limit > 0 and: [limit asFloat
		isFinite]])])
		ifFalse: [self error: 'Invalid sessionIdleTimeout'].
	sessionMutex critical: [sessionIdleTimeout := limit]

]

{ #category : 'Resource Management',
  #vaVisibility : 'private' }
McpStreamableHttpTransport >> sessionNamed: sessionId ifAbsent: absentBlock [
	"Answer a session without exposing mutable session storage.

	 Arguments:
		sessionId - <String> opaque session identifier.
		absentBlock - <Block> evaluated when the session is unknown.
	 Answers:
		<McpStreamableHttpSession> or the absent-block result."

	| session found |

	found := true.
	sessionMutex critical: [self expireIdleSessionsLocked. session := sessions
		at: sessionId ifAbsent: [found := false]].
	^found ifTrue: [session] ifFalse: [absentBlock value]

]

{ #category : 'Resource Management' }
McpStreamableHttpTransport >> startSessionMaintenance [
	"Start one owned idle sweep process for a hosted transport.
	At most one second separates background sweeps. Request lookup and
	admission also expire sessions synchronously at the exact clock boundary.
	Answers:
		<McpStreamableHttpTransport> the receiver."
	sessionMutex critical: [
		maintenanceProcess ifNotNil: [^self].
		maintenanceStop := false.
		maintenanceProcess := [
			[maintenanceStop] whileFalse: [
				(Delay forSeconds: 1) wait.
				maintenanceStop ifFalse: [self expireIdleSessions]]
		] forkAt: Processor userBackgroundPriority]

]

{ #category : 'Message Handling',
  #vaVisibility : 'private' }
McpStreamableHttpTransport >> streamSubscriptionsListen: parsedRequest on: connection request: aRequest [
	"Stream subscriptions/listen SSE frames and forward subscriptionBus events.

	 Arguments:
		parsedRequest - <KeyedCollection> decoded JSON-RPC request.
		connection - <SstHttpConnection> active HTTP connection.
		aRequest - <SstHttpServletRequest> original servlet request.
	 Answers:
		nil."

	| requestId params filter bus completion subscription lf frame streamMutex ackResult ackParams ackMessage |

	requestId := parsedRequest at: 'id' ifAbsent: [nil].
	params := parsedRequest at: 'params' ifAbsent: [EsOrderedDictionary new].
	filter :=
		(params isKindOf: KeyedCollection)
			ifTrue: [params at: 'notifications' ifAbsent: [EsOrderedDictionary new]]
			ifFalse: [EsOrderedDictionary new].

	lf := String with: Character lf.
	streamMutex := Semaphore forMutualExclusion.

	ackResult :=
		self dispatcher
			dispatchMethod: 'subscriptions/listen'
			params: params
			id: requestId
			context: nil.

	ackParams := EsOrderedDictionary new.
	requestId ifNotNil: [
		ackParams
			at: '_meta'
			put: (EsOrderedDictionary with: 'io.modelcontextprotocol/subscriptionId' -> requestId)].
	ackParams
		at: 'notifications'
		put: (
			(ackResult isKindOf: KeyedCollection)
				ifTrue: [ackResult at: 'notifications' ifAbsent: [ackResult]]
				ifFalse: [EsOrderedDictionary new]).

	ackMessage :=
		EsOrderedDictionary new
			at: 'jsonrpc' put: '2.0';
			at: 'method' put: 'notifications/subscriptions/acknowledged';
			at: 'params' put: ackParams;
			yourself.

	frame :=
		'event: message' , lf , 'data: ' , (
			String streamContents: [:s | (McpJSONWriter on: s) nextPut: ackMessage]) , lf , lf.

	[
		streamMutex critical: [
			connection stream
				nextPutAll: frame asUtf8Bytes asString;
				flush]]
					on: Error
					do: [:e | ^nil].

	bus := self dispatcher server ifNotNil: [:srv | srv subscriptionBus].
	bus ifNil: [^nil].

	completion := Semaphore new.
	subscription :=
		bus
			subscribe: filter
			callback: [:notifMethod :notifParams | | notifFrame effectiveParams meta |
				effectiveParams :=
					(notifParams isKindOf: KeyedCollection)
						ifTrue: [notifParams copy]
						ifFalse: [EsOrderedDictionary new].
				requestId ifNotNil: [
					meta := effectiveParams at: '_meta' ifAbsentPut: [EsOrderedDictionary new].
					(meta isKindOf: KeyedCollection)
						ifTrue: [meta at: 'io.modelcontextprotocol/subscriptionId' put: requestId]].
				notifFrame :=
					'event: message' , lf , 'data: ' , (
						String streamContents: [:s |
							(McpJSONWriter on: s) nextPut: (
								EsOrderedDictionary new
									at: 'jsonrpc' put: '2.0';
									at: 'method' put: notifMethod;
									at: 'params' put: effectiveParams;
									yourself)]) , lf , lf.
				[
					streamMutex critical: [
						connection stream
							nextPutAll: notifFrame asUtf8Bytes asString;
							flush]]
								on: Error
								do: [:err | completion signal]].

	[completion wait] ensure: [bus unsubscribe: subscription].
	^nil
]

{ #category : 'Message Handling',
  #vaVisibility : 'private' }
McpStreamableHttpTransport >> streamToolCallWithProgress: parsedRequest on: connection request: aRequest session: sessionOrNil [
	"Stream SSE progress notifications and final response for a tool call.

	 Arguments:
		parsedRequest - <KeyedCollection> decoded JSON-RPC request.
		connection - <SstHttpConnection> active HTTP connection.
		aRequest - <SstHttpServletRequest> original servlet request.
		sessionOrNil - <McpStreamableHttpSession> or nil.
	 Answers:
		nil."

	| requestContext lf streamMutex dispatcherResponse |

	lf := String with: Character lf.
	streamMutex := Semaphore forMutualExclusion.

	[
		streamMutex critical: [
			connection stream
				nextPutAll: (':' , lf , lf) asUtf8Bytes asString;
				flush]
	] on: Error do: [:e | ^nil].

	requestContext :=
		sessionOrNil
			ifNotNil: [self requestContextFor: aRequest session: sessionOrNil]
			ifNil: [self modernRequestContextFor: aRequest message: parsedRequest].

	requestContext progressReporter: [:progressParams | | notifFrame notifMsg |
		notifMsg :=
			EsOrderedDictionary new
				at: 'jsonrpc' put: '2.0';
				at: 'method' put: 'notifications/progress';
				at: 'params' put: progressParams;
				yourself.
		notifFrame :=
			'event: message' , lf , 'data: ' , (
				String streamContents: [:s | (McpJSONWriter on: s) nextPut: notifMsg]) , lf , lf.
		[
			streamMutex critical: [
				connection stream
					nextPutAll: notifFrame asUtf8Bytes asString;
					flush]
		] on: Error do: [:e | nil]].

	dispatcherResponse :=
		self dispatcher dispatch: parsedRequest context: requestContext.

	dispatcherResponse ifNotNil: [| respFrame |
		respFrame :=
			'event: message' , lf , 'data: ' , (
				String streamContents: [:s | (McpJSONWriter on: s) nextPut: dispatcherResponse]) , lf , lf.
		[
			streamMutex critical: [
				connection stream
					nextPutAll: respFrame asUtf8Bytes asString;
					flush]
		] on: Error do: [:e | nil]].

	^nil
]

{ #category : 'Validation',
  #vaVisibility : 'private' }
McpStreamableHttpTransport >> validateHeadersFor: aRequest [
	"Validate Streamable HTTP headers required for a POST request.

	 Arguments:
		aRequest - <SstHttpServletRequest>.
	 Answers:
		<String> error response, or nil when the headers are valid."

	| validationResult accept contentType mediaType protocolVersion isModern methodHeader |

	validationResult := self validateHostFor: aRequest.
	validationResult ifNotNil: [^validationResult].
	validationResult := self validateOriginFor: aRequest.
	validationResult ifNotNil: [^validationResult].
	protocolVersion := aRequest getHeader: 'MCP-Protocol-Version'.
	protocolVersion ifNil: [protocolVersion := aRequest getHeader: 'mcp-protocol-version'].
	isModern := McpProtocolVersion isModern: protocolVersion.
	accept := aRequest getHeader: 'Accept'.
	methodHeader := aRequest getHeader: 'Mcp-Method'.
	methodHeader ifNil: [methodHeader := aRequest getHeader: 'mcp-method'].
	(isModern and: [methodHeader = 'subscriptions/listen'])
		ifTrue: [
			(self acceptHeader: accept includesMediaType: 'text/event-stream')
				ifFalse: [
					aRequest header responseHeader
						status: '406 Not Acceptable';
						contentLength: 0.
					^'']].
	(isModern
		ifTrue: [
			(self acceptHeader: accept includesMediaType: 'application/json')
				or: [self acceptHeader: accept includesMediaType: 'text/event-stream']]
		ifFalse: [
			(self acceptHeader: accept includesMediaType: 'application/json')
				and: [self acceptHeader: accept includesMediaType: 'text/event-stream']])
					ifFalse: [
						aRequest header responseHeader
							status: '400 Bad Request';
							contentLength: 0.
						^''].
	contentType := aRequest getContentType.
	contentType isString
		ifFalse: [
			aRequest header responseHeader
				status: '400 Bad Request';
				contentLength: 0.
			^''].
	mediaType := contentType.
	(mediaType includes: $;)
		ifTrue: [mediaType := (mediaType copyFrom: 1 to: (mediaType indexOf: $;) - 1) trimBlanks].
	(mediaType sameAs: 'application/json')
		ifFalse: [
			aRequest header responseHeader
				status: '400 Bad Request';
				contentLength: 0.
			^''].
	^nil
]

{ #category : 'Validation',
  #vaVisibility : 'private' }
McpStreamableHttpTransport >> validateMcpParamHeadersFor: aRequest message: parsedRequest [
	"Validate Mcp-Param-* headers against tool call arguments per SEP-2243.
	 Decodes Base64 sentinel headers and applies numerical equality for integer/number parameters.

	 Arguments:
		aRequest - <SstHttpServletRequest> HTTP request.
		parsedRequest - <KeyedCollection> decoded JSON-RPC message.
	 Answers:
		<String> error response, or nil when valid."

	| toolName tool arguments inputSchema properties |

	(parsedRequest isKindOf: KeyedCollection) ifFalse: [^nil].
	(parsedRequest at: 'method' ifAbsent: [nil]) = 'tools/call' ifFalse: [^nil].
	arguments :=
		(parsedRequest at: 'params' ifAbsent: [EsOrderedDictionary new])
			at: 'arguments'
			ifAbsent: [EsOrderedDictionary new].
	toolName :=
		(parsedRequest at: 'params' ifAbsent: [EsOrderedDictionary new]) at: 'name' ifAbsent: [nil].
	toolName ifNil: [^nil].
	tool := self dispatcher server toolRegistry toolNamed: toolName ifAbsent: [nil].
	tool ifNil: [^nil].
	inputSchema := tool inputSchema.
	(inputSchema isKindOf: KeyedCollection) ifFalse: [^nil].
	properties := inputSchema at: 'properties' ifAbsent: [nil].
	(properties isKindOf: KeyedCollection) ifFalse: [^nil].

	properties keysAndValuesDo: [:propName :propDef |
		(propDef isKindOf: KeyedCollection)
			ifTrue: [
				(propDef at: 'x-mcp-header' ifAbsent: [nil]) ifNotNil: [:headerToken | | token
					  headerName headerVal bodyVal decodedVal isMatching |
					token := headerToken isString ifTrue: [headerToken] ifFalse: [propName].
					headerName := 'Mcp-Param-' , token.
					headerVal := aRequest getHeader: headerName.
					headerVal ifNil: [headerVal := aRequest getHeader: headerName asLowercase].
					bodyVal :=
						(arguments isKindOf: KeyedCollection)
							ifTrue: [arguments at: propName ifAbsent: [nil]]
							ifFalse: [nil].
					(headerVal isNil and: [bodyVal notNil])
						ifTrue: [
							^self
								formatHeaderMismatchErrorFor: aRequest
								message: parsedRequest
								header: headerName].
					(headerVal notNil and: [bodyVal isNil])
						ifTrue: [
							^self
								formatHeaderMismatchErrorFor: aRequest
								message: parsedRequest
								header: headerName].
					(headerVal notNil and: [bodyVal notNil])
						ifTrue: [
							decodedVal := self decodeHeaderValue: headerVal.
							isMatching :=
								bodyVal isNumber
									ifTrue: [
										([decodedVal asNumber] on: Error do: [:e | nil]) = bodyVal]
									ifFalse: [
										bodyVal isBoolean
											ifTrue: [
												decodedVal sameAs:
													(bodyVal ifTrue: ['true'] ifFalse: ['false'])]
											ifFalse: [
												decodedVal = (
													bodyVal isString
														ifTrue: [bodyVal]
														ifFalse: [bodyVal printString])]].
							isMatching
								ifFalse: [
									^self
										formatHeaderMismatchErrorFor: aRequest
										message: parsedRequest
										header: headerName]]]]].
	^nil
]

{ #category : 'Validation',
  #vaVisibility : 'private' }
McpStreamableHttpTransport >> validateModernMetaFor: aRequest message: parsedRequest [
	"Validate required _meta fields for modern requests per MCP 2026-07-28."

	| params meta hasProto hasCaps id errorResponse jsonResponse |

	(parsedRequest includesKey: 'id') ifFalse: [^nil].

	params :=
		(parsedRequest isKindOf: KeyedCollection)
			ifTrue: [parsedRequest at: 'params' ifAbsent: [nil]]
			ifFalse: [nil].
	meta :=
		(params isKindOf: KeyedCollection)
			ifTrue: [params at: '_meta' ifAbsent: [nil]]
			ifFalse: [nil].
	hasProto :=
		(meta isKindOf: KeyedCollection)
			and: [meta includesKey: 'io.modelcontextprotocol/protocolVersion'].
	hasCaps :=
		(meta isKindOf: KeyedCollection)
			and: [meta includesKey: 'io.modelcontextprotocol/clientCapabilities'].
	(hasProto and: [hasCaps]) ifTrue: [^nil].

	id :=
		(parsedRequest isKindOf: KeyedCollection)
			ifTrue: [parsedRequest at: 'id' ifAbsent: [nil]]
			ifFalse: [nil].
	errorResponse :=
		self dispatcher
			formatError: McpJsonRpcInvalidParamsCode
			message: 'Invalid params: missing required _meta fields'
			id: id
			data: nil.
	jsonResponse :=
		String streamContents: [:stream | (McpJSONWriter on: stream) nextPut: errorResponse].
	aRequest header responseHeader
		status: '400 Bad Request';
		contentType: 'application/json';
		contentLength: jsonResponse asUtf8Bytes size.
	^jsonResponse
]

{ #category : 'Validation',
  #vaVisibility : 'private' }
McpStreamableHttpTransport >> validateProtocolVersionFor: aRequest parsedRequest: parsedRequest [
	"Validate the Streamable HTTP protocol-version header.

	 Initialization declares its version in the JSON-RPC request. When no
	 version is otherwise known, Streamable HTTP requires the March 2025
	 compatibility version.

	 Arguments:
		aRequest - <SstHttpServletRequest>.
		parsedRequest - <Dictionary>.
	 Answers:
		<String> error response, or nil when the version is valid."

	| isInitialization protocolVersion |

	isInitialization :=
		(parsedRequest isKindOf: KeyedCollection)
			and: [(parsedRequest at: 'method' ifAbsent: ['']) = 'initialize'].
	isInitialization
		ifFalse: [
			protocolVersion := aRequest getHeader: 'MCP-Protocol-Version'.
			protocolVersion ifNil: [protocolVersion := aRequest getHeader: 'mcp-protocol-version'].
			protocolVersion ifNil: [protocolVersion := '2025-03-26'].
			(self dispatcher server supportedProtocolVersions includes: protocolVersion)
				ifFalse: [
					^self
						formatUnsupportedProtocolVersionErrorFor: aRequest
						message: parsedRequest
						requested: protocolVersion]].

	^nil
]

{ #category : 'Validation',
  #vaVisibility : 'private' }
McpStreamableHttpTransport >> validateProtocolVersionFor: aRequest session: session [
	"Validate that any supplied protocol version is supported by the server.

	 Arguments:
		aRequest - <SstHttpServletRequest>.
		session - <McpStreamableHttpSession>.
	 Answers:
		<String> error response, or nil when the version is valid."

	| protocolVersion |

	protocolVersion := aRequest getHeader: 'MCP-Protocol-Version'.
	protocolVersion ifNil: [protocolVersion := aRequest getHeader: 'mcp-protocol-version'].
	(protocolVersion notNil
		and: [(self dispatcher server supportedProtocolVersions includes: protocolVersion) not])
			ifTrue: [
				^self
					formatUnsupportedProtocolVersionErrorFor: aRequest
					message: nil
					requested: protocolVersion].
	^nil
]

{ #category : 'Validation',
  #vaVisibility : 'private' }
McpStreamableHttpTransport >> validateRoutingHeadersFor: aRequest message: parsedRequest [
	"Validate standard MCP request headers (MCP-Protocol-Version, Mcp-Method, Mcp-Name) per SEP-2243."

	| methodHeader method nameHeader expectedName decodedName protocolHeader bodyVersion |

	method :=
		(parsedRequest isKindOf: KeyedCollection)
			ifTrue: [parsedRequest at: 'method' ifAbsent: [nil]]
			ifFalse: [nil].

	(parsedRequest includesKey: 'id') ifFalse: [^nil].

	protocolHeader := aRequest getHeader: 'MCP-Protocol-Version'.
	protocolHeader ifNil: [protocolHeader := aRequest getHeader: 'mcp-protocol-version'].
	bodyVersion := nil.
	(parsedRequest at: 'params' ifAbsent: [nil]) ifNotNil: [:p |
		(p isKindOf: KeyedCollection) ifTrue: [
			(p at: '_meta' ifAbsent: [nil]) ifNotNil: [:m |
				(m isKindOf: KeyedCollection) ifTrue: [
					bodyVersion := m at: 'io.modelcontextprotocol/protocolVersion' ifAbsent: [nil]]]]].
	(bodyVersion notNil and: [protocolHeader ~= bodyVersion])
		ifTrue: [
			^self
				formatHeaderMismatchErrorFor: aRequest
				message: parsedRequest
				header: 'MCP-Protocol-Version'].

	methodHeader := aRequest getHeader: 'Mcp-Method'.
	methodHeader ifNil: [methodHeader := aRequest getHeader: 'mcp-method'].
	(methodHeader isNil or: [method isNil or: [methodHeader ~= method]])
		ifTrue: [
			^self
				formatHeaderMismatchErrorFor: aRequest
				message: parsedRequest
				header: 'Mcp-Method'].

	nameHeader := aRequest getHeader: 'Mcp-Name'.
	nameHeader ifNil: [nameHeader := aRequest getHeader: 'mcp-name'].
	(#('tools/call' 'prompts/get' 'resources/read') includes: method)
		ifTrue: [
			nameHeader ifNil: [
				^self
					formatHeaderMismatchErrorFor: aRequest
					message: parsedRequest
					header: 'Mcp-Name'].
			decodedName := self decodeHeaderValue: nameHeader.
			(#('tools/call' 'prompts/get') includes: method)
				ifTrue: [
					expectedName :=
						(parsedRequest at: 'params' ifAbsent: [EsOrderedDictionary new])
							at: 'name'
							ifAbsent: [nil]].
			method = 'resources/read'
				ifTrue: [
					expectedName :=
						(parsedRequest at: 'params' ifAbsent: [EsOrderedDictionary new])
							at: 'uri'
							ifAbsent: [nil]].
			(expectedName isNil or: [decodedName ~= expectedName])
				ifTrue: [
					^self
						formatHeaderMismatchErrorFor: aRequest
						message: parsedRequest
						header: 'Mcp-Name']]
		ifFalse: [
			nameHeader ifNotNil: [
				decodedName := self decodeHeaderValue: nameHeader.
				(#('tools/call' 'prompts/get') includes: method)
					ifTrue: [
						expectedName :=
							(parsedRequest at: 'params' ifAbsent: [EsOrderedDictionary new])
								at: 'name'
								ifAbsent: [nil].
						(expectedName notNil and: [decodedName ~= expectedName])
							ifTrue: [
								^self
									formatHeaderMismatchErrorFor: aRequest
									message: parsedRequest
									header: 'Mcp-Name']].
				method = 'resources/read'
					ifTrue: [
						expectedName :=
							(parsedRequest at: 'params' ifAbsent: [EsOrderedDictionary new])
								at: 'uri'
								ifAbsent: [nil].
						(expectedName notNil and: [decodedName ~= expectedName])
							ifTrue: [
								^self
									formatHeaderMismatchErrorFor: aRequest
									message: parsedRequest
									header: 'Mcp-Name']]]].
	^nil
]

{ #category : 'Resource Management',
  #vaVisibility : 'private' }
McpStreamableHttpTransport >> withSession: session request: request do: operation [
	"Pin a still-retained session for one synchronous HTTP response.
	Arguments:
		session - <McpStreamableHttpSession> candidate.
		request - <SstHttpServletRequest> request receiving an expiry error.
		operation - <Block> zero arguments, performs dispatch and encoding.
	Answers:
		<String> HTTP response body."
	| retained |
	retained := sessionMutex critical: [
		self expireIdleSessionsLocked.
		(sessions at: session id ifAbsent: [nil]) == session
			ifTrue: [session beginRequestAt: sessionClock value. true]
			ifFalse: [false]].
	retained ifFalse: [
		request header responseHeader status: '404 Not Found'; contentLength: 0.
		^''].
	^[operation value] ensure: [
		sessionMutex critical: [session endRequestAt: sessionClock value]]

]
