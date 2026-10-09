"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# McpLegacySseClientTransport

`McpLegacySseClientTransport` implements the legacy dual-endpoint Server-Sent
Events (SSE) client transport for MCP.

## Responsibilities

- Connect to an SSE endpoint via HTTP GET with `Accept: text/event-stream`.
- Parse incoming SSE events using `McpSseParser`.
- Discover and validate the target POST endpoint from the server's initial
  `endpoint` event, verifying origin match.
- Extract optional session ID from the endpoint query parameters.
- Dispatch outgoing JSON-RPC requests and notifications via HTTP POST.
- Correlate JSON-RPC responses arriving over the SSE stream to waiting
  client requests.
- Forward server notifications and server-initiated requests to the owning
  `McpClient`.

## Lifecycle and boundaries

Owned by an `McpClient`. The transport maintains a persistent HTTP connection
for the SSE event stream until closed. Outgoing POST requests create
short-lived HTTP exchanges.
"
Class {
	#name : 'McpLegacySseClientTransport',
	#superclass : 'McpClientTransport',
	#instVars : [
		'url',
		'postUrl',
		'sessionID',
		'httpClient',
		'streamSubscription',
		'pendingRequests',
		'pendingRequestsMutex',
		'endpointReceivedSemaphore',
		'requestTimeout',
		'isClosing',
		'receiveBuffer',
		'additionalHeaders',
		'eventParser'
	],
	#pools : [
		'McpJsonRpcConstants'
	],
	#category : 'McpHttpClientSubApp'
}

{ #category : 'Instance Creation' }
McpLegacySseClientTransport class >> url: aUrl [
	"Answer a new legacy SSE client transport configured for an SSE endpoint URL.

	 Arguments:
		aUrl - <String> or <SstHttpUrl> SSE endpoint URL.
	 Answers:
		<McpLegacySseClientTransport>."

	^self new
		url: aUrl;
		yourself
]

{ #category : 'Accessing' }
McpLegacySseClientTransport >> additionalHeaders [
	"Answer custom request headers.

	 Answers:
		<KeyedCollection>."

	additionalHeaders ifNil: [additionalHeaders := EsOrderedDictionary new].
	^additionalHeaders
]

{ #category : 'Accessing' }
McpLegacySseClientTransport >> additionalHeaders: aKeyedCollection [
	"Set custom request headers.

	 Arguments:
		aKeyedCollection - <KeyedCollection> or nil.
	 Answers:
		<McpLegacySseClientTransport> the receiver."

	additionalHeaders :=
		aKeyedCollection ifNil: [EsOrderedDictionary new] ifNotNil: [aKeyedCollection copy].
	^self
]

{ #category : 'Private',
  #vaVisibility : 'private' }
McpLegacySseClientTransport >> buildHeaders [
	"Answer detached HTTP headers for establishing the SSE connection.

	 Answers:
		<KeyedCollection> request headers."

	| headers |

	headers := EsOrderedDictionary new.
	url ifNotNil: [| rawHostport |
		rawHostport := [url hostport] on: Error do: [:e | nil].
		(rawHostport notNil
			and: [rawHostport size >= 9 and: [(rawHostport copyFrom: 1 to: 9) sameAs: '127.0.0.1']])
				ifTrue: [
					self
						putHeaderName: 'Host'
						value: ('localhost' , (rawHostport copyFrom: 10 to: rawHostport size))
						into: headers]].
	self additionalHeaders
		keysAndValuesDo: [:name :value | self putHeaderName: name value: value into: headers].
	self putHeaderName: 'Accept' value: 'text/event-stream' into: headers.
	self putHeaderName: 'Cache-Control' value: 'no-cache' into: headers.
	sessionID ifNotNil: [self putHeaderName: 'MCP-Session-ID' value: sessionID into: headers].
	^headers
]

{ #category : 'Connection Lifecycle' }
McpLegacySseClientTransport >> close [
	"Terminate the SSE stream, abort pending requests, and reset transport state.

	 Answers:
		<McpLegacySseClientTransport> the receiver."

	isClosing := true.
	streamSubscription ifNotNil: [
		[streamSubscription cancel] on: Error do: [:e | nil].
		streamSubscription := nil].
	httpClient ifNotNil: [
		[httpClient shutDown] on: Error do: [:e | nil].
		httpClient := nil].
	self terminatePendingRequestsWithReason: 'SSE transport closed'.
	postUrl := nil.
	sessionID := nil.
	receiveBuffer := #[].
	^self
]

{ #category : 'Instance Creation',
  #vaVisibility : 'private' }
McpLegacySseClientTransport >> configuredHttpClientFor: endpointUrl [
	"Answer an SST client with private MCP timeout configuration.

	 Arguments:
		endpointUrl - <SstHttpUrl> validated MCP endpoint.
	 Answers:
		<SstHttpClient>."

	| transportIdentifier anHttpClient configuration |

	transportIdentifier := endpointUrl localEndpointUrl transport.
	anHttpClient := McpOriginHttpClient forTransportScheme: transportIdentifier.
	anHttpClient isSstError ifTrue: [anHttpClient raise].
	configuration := anHttpClient configuration.
	configuration notNil ifTrue: [
		configuration negotiationTimeout: self requestTimeout * 1000;
			sendTimeout: self requestTimeout * 1000;
			receiveTimeout: self requestTimeout * 1000].
	^anHttpClient

]

{ #category : 'Execution',
  #vaVisibility : 'private' }
McpLegacySseClientTransport >> doPostMessage: jsonString headers: requestHeaders [
	"Post one JSON-RPC string to the discovered SSE POST endpoint.
	 If the POST response returns a direct JSON-RPC result (200 OK), dispatches
		 it immediately."

	| targetUrl headers exchangeClient responseOrError response parsedResp |

	targetUrl := self postUrl.
	targetUrl ifNil: [self error: 'No SSE endpoint URL available for POST'].
	headers := self headersIncluding: requestHeaders.
	exchangeClient := self configuredHttpClientFor: targetUrl.
	[
		responseOrError :=
			exchangeClient
				post: jsonString asUtf8Bytes
				typed: 'application/json'
				at: targetUrl
				using: nil
				withHeaders: headers.
		(responseOrError respondsTo: #header)
			ifFalse: [self error: 'POST failed: ' , responseOrError
				printString].
		response := responseOrError.
		response header statusCode >= 300
			ifTrue: [
				self error:
					'HTTP Error ' , response header status ,
				' posting message to SSE endpoint'].
		(response header statusCode = 200 and: [response contents notEmpty])
			ifTrue: [
				parsedResp :=
					[McpJSONReader fromString:
						(UnicodeString utf8: response contents asByteArray)]
						on: Exception
						do: [:e | e exitWith: nil].
				parsedResp ifNotNil: [self handleIncomingJson: parsedResp]]]
					ensure: [exchangeClient shutDown].
	^self

]

{ #category : 'Execution' }
McpLegacySseClientTransport >> ensureConnected [
	"Establish the SSE stream if not already running, and await the endpoint
		event.

	 Answers:
		<McpLegacySseClientTransport> the receiver."

	| streamResponse stream timerProcess timedOut |

	self isRunning ifTrue: [^self].
	isClosing := false.
	httpClient := self configuredHttpClientFor: self url.
	[
		streamResponse := httpClient get: self url typed: nil using: nil
			withHeaders: self buildHeaders streaming: true.
		streamResponse isSstError ifTrue: [streamResponse raise].
		streamResponse header statusCode >= 300
			ifTrue: [self error: 'MCP SSE opening request failed']
	] on: Error do: [:failure |
		httpClient shutDown.
		httpClient := nil.
		failure pass].
	(streamResponse respondsTo: #header)
		ifTrue: [
			streamResponse header statusCode >= 400
				ifTrue: [
					self error:
						'HTTP Error ' , streamResponse header status ,
				' establishing SSE connection']].
	(streamResponse respondsTo: #isStreamed)
		ifTrue: [
			streamResponse isStreamed
				ifTrue: [
					stream := streamResponse inputStream.
					streamSubscription :=
						stream
							listen: [:chunk | self handleStreamChunk: chunk]
							onError: [:err | self handleStreamError: err]
							onDone: [self handleStreamDone]
							cancelOnError: false]
				ifFalse: [streamResponse contents ifNotNil: [:body | self
				handleStreamChunk: body]]]
		ifFalse: [
			(streamResponse respondsTo: #contents)
				ifTrue: [streamResponse contents ifNotNil: [:body | self
				handleStreamChunk: body]]].
	timedOut := false.
	timerProcess :=
		[
			(Delay forSeconds: self requestTimeout) wait.
			timedOut := true.
			endpointReceivedSemaphore signal]
				forkAt: Processor userBackgroundPriority.
	endpointReceivedSemaphore wait.
	timerProcess terminate.
	(timedOut and: [self postUrl isNil])
		ifTrue: [
			self close.
			self error: 'Timed out waiting for SSE endpoint event'].
	^self

]

{ #category : 'Accessing' }
McpLegacySseClientTransport >> eventParser [
	"Answer the parser used for decoding SSE event frames.

	 Answers:
		<McpSseParser>."

	eventParser ifNil: [eventParser := McpSseParser new].
	^eventParser
]

{ #category : 'Private',
  #vaVisibility : 'private' }
McpLegacySseClientTransport >> existingNameFor: aHeaderName in: aHeaderDictionary [
	"Answer the matching key in aHeaderDictionary, ignoring casing.

	 Arguments:
		aHeaderName - <String> target header name.
		aHeaderDictionary - <KeyedCollection> headers dictionary.
	 Answers:
		<String> or nil."

	aHeaderDictionary keysDo: [:each | (each sameAs: aHeaderName) ifTrue: [^each]].
	^nil
]

{ #category : 'Stream Handling' }
McpLegacySseClientTransport >> extractSessionIdFrom: aString [
	"Extract the session ID from an endpoint query string if present.

	 Arguments:
		aString - <String> endpoint URL string.
	 Answers:
		<String> or nil."

	| marker idx endIdx |

	marker := 'session_id='.
	idx := aString indexOfSubCollection: marker startingAt: 1.
	idx = 0
		ifTrue: [
			marker := 'sessionId='.
			idx := aString indexOfSubCollection: marker startingAt: 1].
	idx = 0 ifTrue: [^nil].
	idx := idx + marker size.
	endIdx := aString indexOf: $& startingAt: idx.
	endIdx = 0 ifTrue: [endIdx := aString size + 1].
	^aString copyFrom: idx to: endIdx - 1
]

{ #category : 'Message Dispatching' }
McpLegacySseClientTransport >> handleIncomingJson: aDictionary [
	"Dispatch a decoded JSON-RPC message to pending requests or client handlers.

	 Arguments:
		aDictionary - <KeyedCollection> decoded JSON message.
	 Answers:
		<McpLegacySseClientTransport> the receiver."

	| id isResponse |

	(aDictionary isKindOf: KeyedCollection) ifFalse: [^self].
	(aDictionary at: 'jsonrpc' ifAbsent: [nil]) = '2.0' ifFalse: [^self].
	id := aDictionary at: 'id' ifAbsent: [nil].
	isResponse := (aDictionary includesKey: 'result') or: [aDictionary includesKey: 'error'].
	(isResponse and: [id notNil])
		ifTrue: [self resolvePendingRequest: id with: aDictionary]
		ifFalse: [self client ifNotNil: [:c | c handleIncomingMessage: aDictionary]].
	^self
]

{ #category : 'Stream Handling' }
McpLegacySseClientTransport >> handleSseEvent: anEvent [
	"Dispatch a parsed SSE event based on its type.

	 Arguments:
		anEvent - <McpSseEvent> parsed event.
	 Answers:
		<McpLegacySseClientTransport> the receiver."

	| eventType eventData parsedJson |

	eventType := anEvent type.
	eventData := anEvent data.
	eventType = 'endpoint'
		ifTrue: [
			self postUrl: (self resolveEndpointUrl: eventData).
			self sessionID: (self extractSessionIdFrom: eventData).
			endpointReceivedSemaphore signal.
			^self].
	(eventType = 'message' and: [eventData isEmpty not])
		ifTrue: [
			parsedJson := [McpJSONReader fromString: eventData] on: Error do: [:e | nil].
			parsedJson ifNotNil: [self handleIncomingJson: parsedJson].
			^self].
	^self
]

{ #category : 'Stream Handling' }
McpLegacySseClientTransport >> handleStreamChunk: aByteArrayOrString [
	"Process incoming bytes or raw byte string chunks from the SSE stream.

	 Arguments:
		aByteArrayOrString - <ByteArray> or <String> stream chunk.
	 Answers:
		<McpLegacySseClientTransport> the receiver."

	| chunkBytes |

	chunkBytes :=
		aByteArrayOrString isByteArray
			ifTrue: [aByteArrayOrString]
			ifFalse: [
				(aByteArrayOrString respondsTo: #asByteArray)
					ifTrue: [aByteArrayOrString asByteArray]
					ifFalse: [aByteArrayOrString asUtf8Bytes]].
	receiveBuffer ifNil: [receiveBuffer := #[]].
	receiveBuffer := self eventParser
		parseAvailableBytes: receiveBuffer , chunkBytes
		do: [:event | self handleSseEvent: event].
	^self
]

{ #category : 'Stream Handling' }
McpLegacySseClientTransport >> handleStreamDone [
	"Handle the closure of the underlying SSE stream."

	streamSubscription := nil.
	postUrl := nil.
	(isClosing not and: [pendingRequests notEmpty])
		ifTrue: [self terminatePendingRequestsWithReason: 'SSE connection closed by server'].
	^self
]

{ #category : 'Stream Handling' }
McpLegacySseClientTransport >> handleStreamError: anError [
	"Handle an error raised on the underlying SSE stream.

	 Arguments:
		anError - <Error> stream exception.
	 Answers:
		<McpLegacySseClientTransport> the receiver."

	streamSubscription := nil.
	postUrl := nil.
	isClosing
		ifFalse: [
			self terminatePendingRequestsWithReason: 'SSE connection error: ' , anError messageText].
	^self
]

{ #category : 'Private',
  #vaVisibility : 'private' }
McpLegacySseClientTransport >> headersIncluding: requestHeaders [
	"Answer headers for outgoing POST requests merged with scoped request headers.

	 Arguments:
		requestHeaders - <KeyedCollection> or nil.
	 Answers:
		<KeyedCollection> merged headers."

	| headers |

	headers := self buildHeaders.
	self putHeaderName: 'Content-Type' value: 'application/json' into: headers.
	self putHeaderName: 'Accept' value: 'application/json, text/event-stream' into: headers.
	requestHeaders ifNotNil: [
		requestHeaders keysAndValuesDo: [:k :v | self putHeaderName: k value: v into: headers]].
	^headers
]

{ #category : 'Initialization',
  #vaVisibility : 'private' }
McpLegacySseClientTransport >> initialize [
	"Initialize SSE client transport defaults.

	 Answers:
		<McpLegacySseClientTransport> the receiver."

	super initialize.
	requestTimeout := 30.
	isClosing := false.
	receiveBuffer := #[].
	pendingRequests := Dictionary new.
	pendingRequestsMutex := Semaphore forMutualExclusion.
	endpointReceivedSemaphore := Semaphore new.
	eventParser := McpSseParser new.
	additionalHeaders := EsOrderedDictionary new.
	^self
]

{ #category : 'Accessing' }
McpLegacySseClientTransport >> isRunning [
	"Answer whether the SSE stream connection is currently active and established.

	 Answers:
		<Boolean>."

	^httpClient notNil and: [isClosing not and: [streamSubscription notNil and: [postUrl notNil]]]
]

{ #category : 'Accessing' }
McpLegacySseClientTransport >> postUrl [
	"Answer the discovered POST endpoint URL.

	 Answers:
		<SstHttpUrl> or nil."

	^postUrl
]

{ #category : 'Accessing' }
McpLegacySseClientTransport >> postUrl: aUrl [
	"Set the discovered POST endpoint URL.

	 Arguments:
		aUrl - <SstHttpUrl> or nil.
	 Answers:
		<McpLegacySseClientTransport> the receiver."

	postUrl := aUrl.
	^self
]

{ #category : 'Private',
  #vaVisibility : 'private' }
McpLegacySseClientTransport >> putHeaderName: headerName value: headerValue into: headers [
	"Replace a header using case-insensitive name matching.

	 Arguments:
		headerName - <String> HTTP header name.
		headerValue - <String> HTTP header value.
		headers - <KeyedCollection> destination headers.
	 Answers:
		<KeyedCollection> destination headers."

	| existingName strKey strVal |

	existingName := self existingNameFor: headerName in: headers.
	existingName ifNotNil: [headers removeKey: existingName].
	strKey := (headerName asEsString ifNil: [headerName asString]) copy.
	strVal :=
		headerValue
			ifNil: ['']
			ifNotNil: [
				(headerValue respondsTo: #asEsString)
					ifTrue: [headerValue asEsString ifNil: [headerValue asString]]
					ifFalse: [headerValue asString]].
	headers at: strKey put: strVal copy.
	^headers
]

{ #category : 'Accessing' }
McpLegacySseClientTransport >> requestTimeout [
	"Answer the request timeout in seconds.

	 Answers:
		<Integer> seconds."

	^requestTimeout
]

{ #category : 'Accessing' }
McpLegacySseClientTransport >> requestTimeout: anInteger [
	"Set the request timeout in seconds.

	 Arguments:
		anInteger - <Integer> timeout in seconds.
	 Answers:
		<McpLegacySseClientTransport> the receiver."

	(anInteger isInteger and: [anInteger > 0])
		ifFalse: [self error: 'Request timeout must be a positive integer'].
	requestTimeout := anInteger.
	^self
]

{ #category : 'Stream Handling' }
McpLegacySseClientTransport >> resolveEndpointUrl: anEndpointString [
	"Resolve an endpoint URL string from the SSE endpoint event against self url.
	 Verifies that the origin matches self url.

	 Arguments:
		anEndpointString - <String> relative or absolute endpoint URL.
	 Answers:
		<SstHttpUrl> validated target endpoint."

	| resolved endpointStr basePath lastSlash |

	endpointStr := anEndpointString trimBlanks.
	endpointStr isEmpty ifTrue: [self error: 'Empty SSE endpoint URL received'].
	((endpointStr beginsWithSubCollection: 'http://')
		or: [endpointStr beginsWithSubCollection: 'https://'])
			ifTrue: [resolved := endpointStr sstAsUrl]
			ifFalse: [
				(endpointStr beginsWithSubCollection: '/')
					ifTrue: [resolved := (url scheme , '://' , url hostport , endpointStr) sstAsUrl]
					ifFalse: [
						basePath := url path.
						basePath isEmpty ifTrue: [basePath := '/'].
						basePath last = $/
							ifFalse: [
								lastSlash := basePath lastIndexOf: $/.
								basePath :=
									lastSlash > 0
										ifTrue: [basePath copyFrom: 1 to: lastSlash]
										ifFalse: ['/']].
						resolved :=
							(url scheme , '://' , url hostport , basePath , endpointStr) sstAsUrl]].
	((resolved scheme sameAs: url scheme) and: [resolved hostport sameAs: url hostport])
		ifFalse: [self error: 'SSE endpoint origin does not match connection origin: ' , endpointStr].
	^resolved
]

{ #category : 'Message Dispatching' }
McpLegacySseClientTransport >> resolvePendingRequest: requestId with: aResponseDictionary [
	"Fulfill one pending request with its correlated response message.

	 Arguments:
		requestId - <String> or <Integer> request identifier.
		aResponseDictionary - <KeyedCollection> response message.
	 Answers:
		<McpLegacySseClientTransport> the receiver."

	pendingRequestsMutex critical: [
		pendingRequests
			at: requestId
			ifPresent: [:entry |
				entry at: #response put: aResponseDictionary.
				entry at: #completed put: true.
				(entry at: #semaphore) signal]].
	^self
]

{ #category : 'Protocol Operations' }
McpLegacySseClientTransport >> sendNotification: notificationDictionary [
	"Send one JSON-RPC notification without request-scoped headers.

	 Arguments:
		notificationDictionary - <KeyedCollection> JSON-RPC notification.
	 Answers:
		<McpLegacySseClientTransport> the receiver."

	^self sendNotification: notificationDictionary headers: nil
]

{ #category : 'Protocol Operations' }
McpLegacySseClientTransport >> sendNotification: notificationDictionary headers: requestHeaders [
	"Send one JSON-RPC notification to the discovered SSE POST endpoint.

	 Arguments:
		notificationDictionary - <KeyedCollection> JSON-RPC notification.
		requestHeaders - <KeyedCollection> transport headers, or nil.
	 Answers:
		<McpLegacySseClientTransport> the receiver."

	| jsonString |

	(notificationDictionary isKindOf: KeyedCollection)
		ifFalse: [self error: 'MCP notification must be a keyed collection'].
	self ensureConnected.
	jsonString :=
		String streamContents: [:stream | (McpJSONWriter on: stream) nextPut: notificationDictionary].
	self doPostMessage: jsonString headers: requestHeaders.
	^self
]

{ #category : 'Protocol Operations' }
McpLegacySseClientTransport >> sendRequest: requestDictionary id: requestId [
	"Send one JSON-RPC request without request-scoped headers.

	 Arguments:
		requestDictionary - <KeyedCollection> JSON-RPC request.
		requestId - <String> or <Integer> request identifier.
	 Answers:
		<Object> decoded result."

	^self sendRequest: requestDictionary id: requestId headers: nil
]

{ #category : 'Protocol Operations' }
McpLegacySseClientTransport >> sendRequest: requestDictionary id: requestId headers: requestHeaders [
	"Send a JSON-RPC request to the discovered SSE POST endpoint and await its response.

	 Arguments:
		requestDictionary - <KeyedCollection> JSON-RPC request.
		requestId - <String> or <Integer> request identifier.
		requestHeaders - <KeyedCollection> transport headers, or nil.
	 Answers:
		<Object> decoded result."

	| jsonString entry semaphore timerProcess response result |

	(requestDictionary isKindOf: KeyedCollection)
		ifFalse: [self error: 'MCP request must be a keyed collection'].
	(requestId isString or: [requestId isInteger])
		ifFalse: [self error: 'MCP request identifier is invalid'].
	self ensureConnected.
	jsonString :=
		String streamContents: [:stream | (McpJSONWriter on: stream) nextPut: requestDictionary].
	semaphore := Semaphore new.
	entry := Dictionary new.
	entry
		at: #semaphore put: semaphore;
		at: #response put: nil;
		at: #completed put: false;
		at: #timedOut put: false;
		at: #errorReason put: nil.
	pendingRequestsMutex critical: [pendingRequests at: requestId put: entry].
	timerProcess :=
		[
			(Delay forSeconds: self requestTimeout) wait.
			pendingRequestsMutex critical: [
				pendingRequests
					at: requestId
					ifPresent: [:pending |
						(pending at: #completed)
							ifFalse: [
								pending at: #timedOut put: true.
								(pending at: #semaphore) signal]]]]
									forkAt: Processor userBackgroundPriority.
	[
		self doPostMessage: jsonString headers: requestHeaders.
		semaphore wait.
		timerProcess terminate.
		(entry at: #timedOut)
			ifTrue: [self error: 'MCP SSE request timed out: ' , requestId printString].
		(entry at: #errorReason) ifNotNil: [:reason | self error: reason].
		response := entry at: #response.
		response ifNil: [
			self error: 'MCP SSE request completed without a response: ' , requestId printString].
		result := self validatedResultFrom: response id: requestId.
		^result]
			ensure: [
				timerProcess terminate.
				pendingRequestsMutex critical: [pendingRequests removeKey: requestId ifAbsent: [nil]]]
]

{ #category : 'Accessing' }
McpLegacySseClientTransport >> sessionID [
	"Answer the extracted session identifier, or nil.

	 Answers:
		<String> or nil."

	^sessionID
]

{ #category : 'Accessing' }
McpLegacySseClientTransport >> sessionID: aString [
	"Set the session identifier.

	 Arguments:
		aString - <String> or nil.
	 Answers:
		<McpLegacySseClientTransport> the receiver."

	sessionID := aString.
	^self
]

{ #category : 'Accessing' }
McpLegacySseClientTransport >> supportsRequestHeaders [
	"Answer whether this transport accepts request-scoped headers.

	 Answers:
		<Boolean>."

	^true
]

{ #category : 'Connection Lifecycle' }
McpLegacySseClientTransport >> terminatePendingRequestsWithReason: aReason [
	"Reject all unfulfilled requests with an explanatory reason.

	 Arguments:
		aReason - <String> failure explanation.
	 Answers:
		<McpLegacySseClientTransport> the receiver."

	pendingRequestsMutex critical: [
		pendingRequests do: [:entry |
			(entry at: #completed)
				ifFalse: [
					entry at: #errorReason put: aReason.
					(entry at: #semaphore) signal]].
		pendingRequests := Dictionary new].
	^self
]

{ #category : 'Accessing' }
McpLegacySseClientTransport >> url [
	"Answer the configured SSE endpoint URL.

	 Answers:
		<SstHttpUrl> or nil."

	^url
]

{ #category : 'Accessing' }
McpLegacySseClientTransport >> url: aUrl [
	"Validate and set the SSE endpoint URL.

	 Arguments:
		aUrl - <String> or <SstHttpUrl> SSE endpoint URL.
	 Answers:
		<McpLegacySseClientTransport> the receiver."

	| resolvedUrl scheme address |

	(aUrl isString or: [aUrl isKindOf: SstHttpUrl])
		ifFalse: [self error: 'SSE endpoint must be an HTTP or HTTPS URL'].
	resolvedUrl := aUrl sstAsUrl.
	(resolvedUrl isKindOf: SstHttpUrl)
		ifFalse: [self error: 'SSE endpoint must be an HTTP or HTTPS URL'].
	scheme := resolvedUrl scheme.
	(scheme notNil and: [(scheme sameAs: 'http') or: [scheme sameAs: 'https']])
		ifFalse: [self error: 'SSE endpoint must use HTTP or HTTPS'].
	address := resolvedUrl address.
	(address isString and: [address isEmpty not])
		ifFalse: [self error: 'SSE endpoint host is required'].

	self close.
	self client ifNotNil: [self client markDisconnected].
	url := resolvedUrl copy.
	^self
]

{ #category : 'Private',
  #vaVisibility : 'private' }
McpLegacySseClientTransport >> validatedResultFrom: responseDictionary id: requestId [
	"Validate that a response matches JSON-RPC 2.0 and extract the result or signal an error.

	 Arguments:
		responseDictionary - <KeyedCollection> decoded response.
		requestId - <String> or <Integer> request identifier.
	 Answers:
		<Object> decoded result."

	| error code message data |

	(responseDictionary isKindOf: KeyedCollection)
		ifFalse: [self error: 'Malformed JSON-RPC response'].
	(responseDictionary includesKey: 'error')
		ifTrue: [
			error := responseDictionary at: 'error'.
			(error isKindOf: KeyedCollection)
				ifTrue: [
					code := error at: 'code' ifAbsent: [McpJsonRpcInternalErrorCode].
					message := error at: 'message' ifAbsent: ['Unknown error'].
					data := error at: 'data' ifAbsent: [nil].
					McpJsonRpcError signalCode: code message: message data: data].
			self error: 'Invalid MCP error payload'].
	^responseDictionary at: 'result' ifAbsent: [nil]
]
