"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# McpSseServerTransport

`McpSseServerTransport` implements the server-side dual-endpoint Server-Sent
Events (SSE) transport for MCP.

## Responsibilities

- Handle `GET /sse` by minting a session and returning an initial SSE stream
  carrying the `endpoint` discovery event.
- Handle `POST /messages` by validating the session ID, parsing JSON-RPC
  bodies, returning `202 Accepted` for notifications or dispatching requests
  to `McpJsonRpcDispatcher`.
- Handle `DELETE /messages` by removing active sessions with `204 No Content`.
- Enforce DNS rebinding protection via `allowedHosts` and validate origins.
- Enforce Bearer token authentication via `authSettings`.

## Lifecycle and boundaries

Owned by an `McpHttpServer`. Sessions remain active until closed by client
DELETE, transport teardown, or timeout.
"
Class {
	#name : 'McpSseServerTransport',
	#superclass : 'Object',
	#instVars : [
		'mcpServer',
		'dispatcher',
		'sessions',
		'sessionsMutex',
		'endpointPath',
		'sseEndpointPath',
		'allowedHosts',
		'allowedOrigins',
		'maximumRequestSize',
		'requestContextFactory',
		'authSettings'
	],
	#pools : [
		'McpJsonRpcConstants'
	],
	#category : 'McpHttpServerSubApp'
}

{ #category : 'Instance Creation' }
McpSseServerTransport class >> new [
	"Answer a new initialized SSE server transport.

	 Answers:
		<McpSseServerTransport>."

	^super new initialize
]

{ #category : 'Accessing' }
McpSseServerTransport >> allowedHosts [
	"Answer allowed Host header values for DNS rebinding protection.

	 Answers:
		<Set> of <String>."

	allowedHosts ifNil: [allowedHosts := Set new].
	^allowedHosts
]

{ #category : 'Accessing' }
McpSseServerTransport >> allowedHosts: aCollection [
	"Set allowed Host header values for DNS rebinding protection.

	 Arguments:
		aCollection - <Collection> of <String>.
	 Answers:
		<McpSseServerTransport> the receiver."

	allowedHosts := aCollection asSet.
	^self
]

{ #category : 'Accessing' }
McpSseServerTransport >> allowedOrigins [
	"Answer allowed Origin header values.

	 Answers:
		<Set> of <String>."

	allowedOrigins ifNil: [allowedOrigins := Set new].
	^allowedOrigins
]

{ #category : 'Accessing' }
McpSseServerTransport >> allowedOrigins: aCollection [
	"Set allowed Origin header values.

	 Arguments:
		aCollection - <Collection> of <String>.
	 Answers:
		<McpSseServerTransport> the receiver."

	allowedOrigins := aCollection asSet.
	^self
]

{ #category : 'Accessing' }
McpSseServerTransport >> authSettings [
	"Answer the OAuth authentication settings, or nil."

	^authSettings
]

{ #category : 'Configuration' }
McpSseServerTransport >> authSettings: anAuthSettings [
	"Set the OAuth authentication settings.

	 Arguments:
		anAuthSettings - <McpAuthSettings> or nil.
	 Answers:
		<McpSseServerTransport> the receiver."

	anAuthSettings ifNotNil: [anAuthSettings validateConfiguration].
	authSettings := anAuthSettings.
	^self

]

{ #category : 'Starting and Stopping' }
McpSseServerTransport >> close [
	"Close all active sessions and release resources.

	 Answers:
		<McpSseServerTransport> the receiver."

	| allSessions |

	sessionsMutex critical: [
		allSessions := sessions values copy.
		sessions := Dictionary new].
	allSessions do: [:session | self closeSession: session].
	^self
]

{ #category : 'Session Management' }
McpSseServerTransport >> closeSession: aSession [
	"Mark a session as closed and wake up its SSE writer.

	 Arguments:
		aSession - <KeyedCollection> session entry.
	 Answers:
		<McpSseServerTransport> the receiver."

	| mutex queueSem |

	aSession ifNil: [^self].
	mutex := aSession at: 'queueMutex' ifAbsent: [nil].
	queueSem := aSession at: 'queueSemaphore' ifAbsent: [nil].
	mutex ifNotNil: [mutex critical: [aSession at: 'closed' put: true]].
	queueSem ifNotNil: [queueSem signal].
	(aSession at: 'completion' ifAbsent: [nil]) ifNotNil: [:sem | sem signal].
	^self
]

{ #category : 'Session Management' }
McpSseServerTransport >> createSession [
	"Create and register a new SSE session entry with synchronized outbound queue.

	 Answers:
		<KeyedCollection> session entry."

	| sessionId entry |

	sessionId := UUID new printString.
	entry :=
		EsOrderedDictionary new
			at: 'id' put: sessionId;
			at: 'created' put: Time totalSeconds;
			at: 'queue' put: OrderedCollection new;
			at: 'queueMutex' put: Semaphore forMutualExclusion;
			at: 'queueSemaphore' put: Semaphore new;
			at: 'closed' put: false;
			yourself.
	sessionsMutex critical: [sessions at: sessionId put: entry].
	^entry
]

{ #category : 'Accessing' }
McpSseServerTransport >> dispatcher [
	"Answer the JSON-RPC dispatcher for this transport.

	 Answers:
		<McpJsonRpcDispatcher>."

	dispatcher ifNil: [
		dispatcher :=
			McpJsonRpcDispatcher new
				server: self mcpServer;
				yourself].
	^dispatcher
]

{ #category : 'Accessing' }
McpSseServerTransport >> dispatcher: aDispatcher [
	"Set the JSON-RPC dispatcher for this transport.

	 Arguments:
		aDispatcher - <McpJsonRpcDispatcher>.
	 Answers:
		<McpSseServerTransport> the receiver."

	dispatcher := aDispatcher.
	^self
]

{ #category : 'Accessing' }
McpSseServerTransport >> endpointPath [
	"Answer the message POST endpoint path.

	 Answers:
		<String>."

	^endpointPath
]

{ #category : 'Accessing' }
McpSseServerTransport >> endpointPath: aString [
	"Set the message POST endpoint path.

	 Arguments:
		aString - <String> endpoint path.
	 Answers:
		<McpSseServerTransport> the receiver."

	(aString isString and: [aString isEmpty not])
		ifFalse: [self error: 'Endpoint path must be a nonempty string'].
	endpointPath := aString copy.
	^self
]

{ #category : 'Message Handling' }
McpSseServerTransport >> enqueueMessage: aMessageDictionary forSession: aSession [
	"Enqueue one JSON-RPC message dictionary for delivery over the session's SSE stream.

	 Arguments:
		aMessageDictionary - <KeyedCollection> JSON-RPC message.
		aSession - <KeyedCollection> session entry.
	 Answers:
		<Boolean> true if enqueued, false if session is closed."

	| mutex queueSem isClosed queue |

	aSession ifNil: [^false].
	mutex := aSession at: 'queueMutex' ifAbsent: [nil].
	mutex ifNil: [^false].
	queueSem := aSession at: 'queueSemaphore' ifAbsent: [nil].
	queueSem ifNil: [^false].
	queue := aSession at: 'queue' ifAbsent: [nil].
	queue ifNil: [^false].

	mutex critical: [
		isClosed := aSession at: 'closed' ifAbsent: [false].
		isClosed ifTrue: [^false].
		queue add: aMessageDictionary].
	queueSem signal.
	^true
]

{ #category : 'Message Handling' }
McpSseServerTransport >> handleDeleteSessionRequest: aRequest [
	"Terminate an active SSE session.

	 Arguments:
		aRequest - <SstHttpServletRequest>.
	 Answers:
		<String> empty response."

	| sessionId removed |

	sessionId := self sessionIdFrom: aRequest.
	sessionId ifNil: [
		aRequest header responseHeader
			status: '400 Bad Request';
			contentLength: 0.
		^''].

	removed := self removeSessionNamed: sessionId.
	removed ifNil: [
		aRequest header responseHeader
			status: '404 Not Found';
			contentLength: 0.
		^''].

	aRequest header responseHeader
		status: '204 No Content';
		contentLength: 0.
	^''
]

{ #category : 'Message Handling' }
McpSseServerTransport >> handlePostMessageRequest: aRequest [
	"Process one client message posted to the SSE message endpoint.
	 Dispatches requests and queues the response on the session's SSE stream.
	 Acknowledges client with HTTP 202 Accepted.

	 Arguments:
		aRequest - <SstHttpServletRequest>.
	 Answers:
		<String> HTTP 202 Accepted response entity."

	| validationResult sessionId session parsedMessage dispatcherResponse |

	validationResult := self validateOriginFor: aRequest.
	validationResult ifNotNil: [^validationResult].
	validationResult := self validateHostFor: aRequest.
	validationResult ifNotNil: [^validationResult].
	validationResult := self validateAuthenticationFor: aRequest.
	validationResult ifNotNil: [^validationResult].

	sessionId := self sessionIdFrom: aRequest.
	sessionId ifNil: [
		aRequest header responseHeader
			status: '400 Bad Request';
			contentLength: 0.
		^''].

	session := self sessionNamed: sessionId ifAbsent: [nil].
	session ifNil: [
		aRequest header responseHeader
			status: '404 Not Found';
			contentLength: 0.
		^''].

	parsedMessage := self parseRequestBody: aRequest.
	parsedMessage ifNil: [^''].
	(parsedMessage isKindOf: KeyedCollection)
		ifFalse: [
			aRequest header responseHeader
				status: '400 Bad Request';
				contentLength: 0.
			^''].

	(parsedMessage includesKey: 'id')
		ifTrue: [
			dispatcherResponse := self dispatcher dispatch: parsedMessage.
			dispatcherResponse
				ifNotNil: [self enqueueMessage: dispatcherResponse forSession: session]]
		ifFalse: [self dispatcher dispatch: parsedMessage].

	aRequest header responseHeader
		status: '202 Accepted';
		at: 'Connection' put: 'keep-alive';
		contentLength: 0.
	^''
]

{ #category : 'Message Handling' }
McpSseServerTransport >> handleSseGetRequest: aRequest [
	"Establish an SSE connection, mint a session, and answer the initial endpoint event.

	 Arguments:
		aRequest - <SstHttpServletRequest>.
	 Answers:
		<String> initial SSE event stream payload."

	| validationResult session endpointPayload lf |

	validationResult := self validateOriginFor: aRequest.
	validationResult ifNotNil: [^validationResult].
	validationResult := self validateHostFor: aRequest.
	validationResult ifNotNil: [^validationResult].
	validationResult := self validateAuthenticationFor: aRequest.
	validationResult ifNotNil: [^validationResult].

	session := self createSession.
	lf := String with: Character lf.
	endpointPayload :=
		'event: endpoint' , lf , 'data: ' , self endpointPath , '?session_id=' , (session at: 'id') ,
			lf , lf.

	(aRequest isKindOf: SstHttpServletRequest)
		ifTrue: [
			aRequest header responseHeader
				status: '200 OK';
				contentType: 'text/event-stream';
				at: 'Cache-Control' put: 'no-cache, no-transform';
				at: 'Connection' put: 'keep-alive'.
			^[:connection |
				self streamSseSession: session on: connection initialPayload: endpointPayload]].

	aRequest header responseHeader
		status: '200 OK';
		contentType: 'text/event-stream';
		at: 'Cache-Control' put: 'no-cache, no-transform';
		at: 'Connection' put: 'keep-alive';
		contentLength: endpointPayload asUtf8Bytes size.
	^endpointPayload
]

{ #category : 'Initialization',
  #vaVisibility : 'private' }
McpSseServerTransport >> initialize [
	"Initialize SSE server transport defaults and mutexes.

	 Answers:
		<McpSseServerTransport> the receiver."

	super initialize.
	sessions := Dictionary new.
	sessionsMutex := Semaphore forMutualExclusion.
	endpointPath := '/messages'.
	sseEndpointPath := '/sse'.
	maximumRequestSize := 4 * 1024 * 1024.
	allowedHosts := Set new.
	allowedOrigins := Set new.
	^self
]

{ #category : 'Validation',
  #vaVisibility : 'private' }
McpSseServerTransport >> isAllowedHost: aHostString [
	"Answer whether aHostString matches the configured allowedHosts.

	 Arguments:
		aHostString - <String> or nil, HTTP Host header value.
	 Answers:
		<Boolean>."

	| normalizedHost |

	self allowedHosts isEmpty ifTrue: [^true].
	(self allowedHosts includes: '*') ifTrue: [^true].
	normalizedHost := aHostString ifNil: [''].
	(self allowedHosts includes: normalizedHost) ifTrue: [^true].
	(normalizedHost includes: $:)
		ifTrue: [| hostWithoutPort |
			hostWithoutPort := normalizedHost copyFrom: 1 to: (normalizedHost indexOf: $:) - 1.
			(self allowedHosts includes: hostWithoutPort) ifTrue: [^true]].
	^false
]

{ #category : 'Validation',
  #vaVisibility : 'private' }
McpSseServerTransport >> isAllowedOrigin: origin [
	"Answer whether an Origin matches the configured allowlist.

	 HTTP Origin scheme and host names are case-insensitive.

	 Arguments:
		origin - <String> request Origin value.
	 Answers:
		<Boolean>."

	allowedOrigins isEmpty ifTrue: [^false].
	^allowedOrigins anySatisfy: [:allowedOrigin | allowedOrigin sameAs: origin]
]

{ #category : 'Accessing' }
McpSseServerTransport >> maximumRequestSize [
	"Answer maximum allowable request payload size in bytes.

	 Answers:
		<Integer> bytes."

	maximumRequestSize ifNil: [maximumRequestSize := 4 * 1024 * 1024].
	^maximumRequestSize
]

{ #category : 'Accessing' }
McpSseServerTransport >> maximumRequestSize: anInteger [
	"Set maximum allowable request payload size in bytes.

	 Arguments:
		anInteger - <Integer> bytes.
	 Answers:
		<McpSseServerTransport> the receiver."

	(anInteger isInteger and: [anInteger > 0])
		ifFalse: [self error: 'Maximum request size must be a positive integer'].
	maximumRequestSize := anInteger.
	^self
]

{ #category : 'Accessing' }
McpSseServerTransport >> mcpServer [
	"Answer the owning MCP server.

	 Answers:
		<McpServer> or nil."

	^mcpServer
]

{ #category : 'Accessing' }
McpSseServerTransport >> mcpServer: aServer [
	"Set the owning MCP server.

	 Arguments:
		aServer - <McpServer>.
	 Answers:
		<McpSseServerTransport> the receiver."

	mcpServer := aServer.
	dispatcher := nil.
	^self
]

{ #category : 'Message Handling',
  #vaVisibility : 'private' }
McpSseServerTransport >> parseRequestBody: aRequest [
	"Decode and parse a bounded UTF-8 JSON request body.

	 Arguments:
		aRequest - <SstHttpServletRequest>.
	 Answers:
		<Object> decoded JSON value, or nil on error."

	| bodyBytes bodyString parsedRequest |

	bodyBytes := aRequest contents asByteArray.
	bodyBytes size > self maximumRequestSize
		ifTrue: [
			aRequest header responseHeader
				status: '413 Payload Too Large';
				contentLength: 0.
			^nil].
	bodyString := (UnicodeString utf8: bodyBytes) asString.
	[parsedRequest := McpJSONReader fromString: bodyString]
		on: Error
		do: [:parseError |
			aRequest header responseHeader
				status: '400 Bad Request';
				contentLength: 0.
			^nil].
	^parsedRequest
]

{ #category : 'Session Management' }
McpSseServerTransport >> removeSessionNamed: aSessionId [
	"Deregister an active session by identifier and terminate its SSE writer.

	 Arguments:
		aSessionId - <String> session identifier.
	 Answers:
		<KeyedCollection> removed session entry or nil."

	| session |

	sessionsMutex critical: [session := sessions removeKey: aSessionId ifAbsent: [nil]].
	session ifNotNil: [self closeSession: session].
	^session
]

{ #category : 'Accessing' }
McpSseServerTransport >> requestContextFactory [
	"Answer the optional block building request contexts.

	 Answers:
		<Block> or nil."

	^requestContextFactory
]

{ #category : 'Accessing' }
McpSseServerTransport >> requestContextFactory: aBlock [
	"Set the optional block building request contexts.

	 Arguments:
		aBlock - <Block> or nil.
	 Answers:
		<McpSseServerTransport> the receiver."

	requestContextFactory := aBlock.
	^self
]

{ #category : 'Session Management' }
McpSseServerTransport >> sessionIdFrom: aRequest [
	"Extract the session identifier from a request's query parameters or headers.

	 Arguments:
		aRequest - <SstHttpServletRequest>.
	 Answers:
		<String> or nil."

	| headerVal uri marker idx endIdx |

	headerVal := aRequest getHeader: 'MCP-Session-ID'.
	headerVal ifNil: [headerVal := aRequest getHeader: 'mcp-session-id'].
	headerVal ifNotNil: [^headerVal trimBlanks].

	uri := aRequest getRequestUri.
	uri ifNil: [^nil].
	marker := 'session_id='.
	idx := uri indexOfSubCollection: marker startingAt: 1.
	idx = 0
		ifTrue: [
			marker := 'sessionId='.
			idx := uri indexOfSubCollection: marker startingAt: 1].
	idx = 0 ifTrue: [^nil].
	idx := idx + marker size.
	endIdx := uri indexOf: $& startingAt: idx.
	endIdx = 0 ifTrue: [endIdx := uri size + 1].
	^(uri copyFrom: idx to: endIdx - 1) trimBlanks
]

{ #category : 'Session Management' }
McpSseServerTransport >> sessionNamed: aSessionId ifAbsent: aBlock [
	"Retrieve an active session by identifier.

	 Arguments:
		aSessionId - <String> session identifier.
		aBlock - <Block> evaluation fallback.
	 Answers:
		<KeyedCollection> session entry or fallback result."

	sessionsMutex critical: [^sessions at: aSessionId ifAbsent: aBlock]
]

{ #category : 'Accessing' }
McpSseServerTransport >> sseEndpointPath [
	"Answer the SSE GET endpoint path.

	 Answers:
		<String>."

	^sseEndpointPath
]

{ #category : 'Accessing' }
McpSseServerTransport >> sseEndpointPath: aString [
	"Set the SSE GET endpoint path.

	 Arguments:
		aString - <String> SSE path.
	 Answers:
		<McpSseServerTransport> the receiver."

	(aString isString and: [aString isEmpty not])
		ifFalse: [self error: 'SSE path must be a nonempty string'].
	sseEndpointPath := aString copy.
	^self
]

{ #category : 'Message Handling',
  #vaVisibility : 'private' }
McpSseServerTransport >> streamSseSession: session on: connection initialPayload: endpointPayload [
	"Stream initial SSE endpoint event, then continuously drain and deliver outbound messages for the session.

	 Arguments:
		session - <KeyedCollection> active SSE session.
		connection - <SstHttpConnection> active HTTP connection.
		endpointPayload - <String> endpoint event payload.
	 Answers:
		nil."

	| queueSem queueMutex queue lf bus busSubscription isClosed messagesToSend frame stream |

	stream := connection stream.
	lf := String with: Character lf.
	queueSem := session at: 'queueSemaphore'.
	queueMutex := session at: 'queueMutex'.
	queue := session at: 'queue'.

	[
		[
			stream
				nextPutAll: endpointPayload asUtf8Bytes asString;
				flush.

			bus := self mcpServer ifNotNil: [:srv | srv subscriptionBus].
			busSubscription :=
				bus ifNotNil: [
					bus
						subscribe: (
							EsOrderedDictionary
								with: 'tools' -> true
								with: 'prompts' -> true
								with: 'resources' -> true)
						callback: [:notifMethod :notifParams |
							self
								enqueueMessage: (
									EsOrderedDictionary new
										at: 'jsonrpc' put: '2.0';
										at: 'method' put: notifMethod;
										at: 'params' put: notifParams;
										yourself)
								forSession: session]].

			[
				isClosed := false.
				messagesToSend := OrderedCollection new.
				queueMutex critical: [
					isClosed := session at: 'closed' ifAbsent: [false].
					messagesToSend addAll: queue.
					queue removeAll].

				messagesToSend do: [:msg |
					frame :=
						'event: message' , lf , 'data: ' ,
							(String streamContents: [:s | (McpJSONWriter on: s) nextPut: msg]) , lf ,
							lf.
					stream nextPutAll: frame asUtf8Bytes asString].
				messagesToSend isEmpty ifFalse: [stream flush].

				isClosed
					ifTrue: [true]
					ifFalse: [
						queueSem wait.
						false]]
							whileFalse]
								on: Error
								do: [:err | self closeSession: session]]
									ensure: [
										bus ifNotNil: [
											busSubscription
												ifNotNil: [bus unsubscribe: busSubscription]].
										self removeSessionNamed: (session at: 'id' ifAbsent: [''])].
	^nil
]

{ #category : 'Validation',
  #vaVisibility : 'private' }
McpSseServerTransport >> validateAuthenticationFor: aRequest [
	"Enforce Bearer authentication when authSettings is configured and enabled.
	 Answers an error response string, or nil when valid.

	 Arguments:
		aRequest - <SstHttpServletRequest>.
	 Answers:
		<String> or nil."

	| authHeader token principal |

	(self authSettings isNil or: [self authSettings enabled not]) ifTrue: [^nil].

	authHeader := aRequest getHeader: 'Authorization'.
	authHeader ifNil: [authHeader := aRequest getHeader: 'authorization'].
	(authHeader isNil or: [(authHeader beginsWithSubCollection: 'Bearer ') not])
		ifTrue: [
			aRequest header responseHeader
				status: '401 Unauthorized';
				at: 'WWW-Authenticate'
					put: 'Bearer error="invalid_token", error_description="Bearer token required"';
				contentLength: 0.
			^''].

	token := (authHeader copyFrom: 8 to: authHeader size) trimBlanks.
	principal := self authSettings validateToken: token.
	principal ifNil: [
		aRequest header responseHeader
			status: '401 Unauthorized';
			at: 'WWW-Authenticate'
				put: 'Bearer error="invalid_token", error_description="Invalid or expired token"';
			contentLength: 0.
		^''].

	^nil
]

{ #category : 'Validation',
  #vaVisibility : 'private' }
McpSseServerTransport >> validateHostFor: aRequest [
	"Validate the Host header against the configured allowlist.

	 Arguments:
		aRequest - <SstHttpServletRequest>.
	 Answers:
		<String> error response, or nil when the host is valid."

	| hostHeader |

	self allowedHosts isEmpty ifTrue: [^nil].
	hostHeader := aRequest getHeader: 'Host'.
	hostHeader ifNil: [hostHeader := aRequest getHeader: 'host'].
	(self isAllowedHost: hostHeader)
		ifFalse: [
			aRequest header responseHeader
				status: '403 Forbidden';
				contentLength: 0.
			^''].
	^nil
]

{ #category : 'Validation',
  #vaVisibility : 'private' }
McpSseServerTransport >> validateOriginFor: aRequest [
	"Validate the optional Origin header against the configured allowlist.

	 Arguments:
		aRequest - <SstHttpServletRequest>.
	 Answers:
		<String> error response, or nil when the origin is valid."

	| origin |

	origin := aRequest getHeader: 'Origin'.
	origin ifNotNil: [
		(self isAllowedOrigin: origin)
			ifFalse: [
				aRequest header responseHeader
					status: '403 Forbidden';
					contentLength: 0.
				^'']].
	^nil
]
