"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# McpHttpClientTransport

`McpHttpClientTransport` implements client-side MCP Streamable HTTP
communication over SST.

## Responsibilities

- Format outbound JSON-RPC requests with modern routing headers (`MCP-Protocol-Version`, `Mcp-Method`, `Mcp-Name`).
- Attach `Authorization: Bearer <token>` when configured with static `bearerToken:` or dynamic `tokenProvider:`.
- Resolve host and port headers safely via `#hostport`.
- Parse JSON-RPC error responses on non-2xx HTTP status codes.
- Handle session recovery on HTTP 404 for legacy sessionful servers.

## Lifecycle and boundaries

Maintains isolated SST client exchanges across requests.
"
Class {
	#name : 'McpHttpClientTransport',
	#superclass : 'McpClientTransport',
	#instVars : [
		'url',
		'httpClient',
		'sessionID',
		'requestTimeout',
		'additionalHeaders',
		'bearerToken',
		'tokenProvider',
		'subscriptionClient',
		'subscriptionStream'
	],
	#category : 'McpHttpClientSubApp'
}

{ #category : 'Instance Creation' }
McpHttpClientTransport class >> url: aUrl [
	"Answer a transport configured for an HTTP or HTTPS MCP endpoint.

	 Arguments:
		aUrl - <String> or <SstHttpUrl> endpoint.
	 Answers:
		<McpHttpClientTransport>."

	^self new
		url: aUrl;
		yourself
]

{ #category : 'Configuration' }
McpHttpClientTransport >> additionalHeaders [
	"Answer detached persistent HTTP headers with their configured casing.

	 Answers:
		<KeyedCollection> header names and values."

	| snapshot |

	snapshot := EsOrderedDictionary new.
	additionalHeaders ifNotNil: [
		additionalHeaders keysAndValuesDo: [:name :value | snapshot at: name copy put: value copy]].
	^snapshot
]

{ #category : 'Configuration' }
McpHttpClientTransport >> additionalHeaders: aDictionary [
	"Validate and retain detached persistent HTTP headers.

	 Protocol-controlled names and case-insensitive duplicates are rejected.

	 Arguments:
		aDictionary - <KeyedCollection> header names and values, or nil.
	 Answers:
		<McpHttpClientTransport> the receiver."

	| snapshot |

	aDictionary ifNil: [
		additionalHeaders := EsOrderedDictionary new.
		^self].
	(aDictionary isKindOf: KeyedCollection)
		ifFalse: [self error: 'Additional headers must be a keyed collection'].
	snapshot := EsOrderedDictionary new.
	aDictionary keysAndValuesDo: [:headerName :headerValue | | existingName |
		self validateHeaderName: headerName value: headerValue.
		(self isProtocolControlledHeader: headerName)
			ifTrue: [self error: 'HTTP header is controlled by the MCP transport: ' , headerName].
		existingName := self existingNameFor: headerName in: snapshot.
		existingName ifNotNil: [self error: 'Duplicate HTTP header: ' , headerName].
		snapshot at: headerName copy put: headerValue copy].
	additionalHeaders := snapshot.
	^self
]

{ #category : 'Validation',
  #vaVisibility : 'private' }
McpHttpClientTransport >> baseMediaTypeFrom: contentType [
	"Answer a normalized base media type without parameters.

	 Arguments:
		contentType - <String> HTTP Content-Type value.
	 Answers:
		<String> lowercase base media type."

	| separator mediaType |

	(contentType isString and: [contentType isEmpty not])
		ifFalse: [self error: 'HTTP response Content-Type is invalid'].
	separator := contentType indexOf: $;.
	mediaType :=
		separator = 0 ifTrue: [contentType] ifFalse: [contentType copyFrom: 1 to: separator - 1].
	mediaType := mediaType trimBlanks asLowercase.
	mediaType isEmpty ifTrue: [self error: 'HTTP response Content-Type is invalid'].
	^mediaType
]

{ #category : 'Accessing' }
McpHttpClientTransport >> bearerToken [
	"Answer the static Bearer token, or nil.

	 Answers:
		<String> or nil."

	^bearerToken
]

{ #category : 'Accessing' }
McpHttpClientTransport >> bearerToken: aString [
	"Set the static Bearer token.

	 Arguments:
		aString - <String> or nil.
	 Answers:
		<McpHttpClientTransport> the receiver."

	bearerToken := aString.
	^self
]

{ #category : 'Header Construction' }
McpHttpClientTransport >> buildHeaders [
	"Answer detached HTTP headers controlled by the MCP transport.

	 Answers:
		<KeyedCollection> request headers."

	| headers token |

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
	additionalHeaders ifNotNil: [
		additionalHeaders
			keysAndValuesDo: [:name :value | self putHeaderName: name value: value into: headers]].
	token := self bearerToken.
	token ifNil: [
		self tokenProvider ifNotNil: [:provider | token := provider value]].
	token ifNotNil: [self putHeaderName: 'Authorization' value: 'Bearer ' , token into: headers].
	self putHeaderName: 'Accept' value: 'application/json, text/event-stream' into: headers.
	sessionID ifNotNil: [self putHeaderName: 'MCP-Session-ID' value: sessionID into: headers].
	(self client notNil and: [McpProtocolVersion isModern: self client protocolVersion])
		ifTrue: [
			self
				putHeaderName: 'MCP-Protocol-Version'
				value: self client protocolVersion
				into: headers].
	^headers
]

{ #category : 'Session Management',
  #vaVisibility : 'private' }
McpHttpClientTransport >> captureSessionFrom: response [
	"Capture and validate the first server session identifier.

	 This method is called only for a successful initialization response.

	 Arguments:
		response - <SstCommunicationMessage> HTTP response.
	 Answers:
		<McpHttpClientTransport> the receiver."

	| candidate |

	sessionID ifNotNil: [^self].
	candidate :=
		response header
			at: 'MCP-Session-Id'
			ifAbsent: [
				response header
					at: 'MCP-Session-ID'
					ifAbsent: [response header at: 'mcp-session-id' ifAbsent: [nil]]].
	candidate ifNil: [^self].
	(candidate isString and: [candidate isEmpty not])
		ifFalse: [self error: 'MCP session identifier is invalid'].
	(candidate allSatisfy: [:character | character codePoint between: 16r21 and: 16r7E])
		ifFalse: [self error: 'MCP session identifier must contain visible ASCII only'].
	sessionID := candidate copy.
	^self
]

{ #category : 'Starting and Stopping' }
McpHttpClientTransport >> close [
	"Reset cached state, terminate any active session, and cancel any active subscription stream.

	 Answers:
		<McpHttpClientTransport> the receiver."

	[self terminateSession] ensure: [
		subscriptionStream ifNotNil: [:s |
			[s cancel] on: Error do: [:e | nil].
			subscriptionStream := nil].
		subscriptionClient ifNotNil: [:c |
			[c shutDown] on: Error do: [:e | nil].
			subscriptionClient := nil].
		httpClient ifNotNil: [httpClient shutDown].
		httpClient := nil.
		sessionID := nil].
	^self
]

{ #category : 'Instance Creation',
  #vaVisibility : 'private' }
McpHttpClientTransport >> configuredHttpClientFor: endpointUrl [
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
		configuration negotiationTimeout: self requestTimeout;
			sendTimeout: self requestTimeout;
			receiveTimeout: self requestTimeout].
	^anHttpClient

]

{ #category : 'Execution',
  #vaVisibility : 'private' }
McpHttpClientTransport >> doSendListenRequest: requestDictionary id: requestId headers: requestHeaders [
	"Send a modern subscriptions/listen POST request with SSE streaming and
		process change events.

	 Arguments:
		requestDictionary - <KeyedCollection> JSON-RPC request.
		requestId - <String> or <Number> request identifier.
		requestHeaders - <KeyedCollection> validated headers, or nil.
	 Answers:
		<Object> validated JSON-RPC subscription acknowledgment result."

	| jsonString headers exchangeClient response stream ackSemaphore ackResult
	  receiveBuffer parser isDone |

	jsonString := String streamContents: [:s | (McpJSONWriter on: s) nextPut:
		requestDictionary].
	headers := self headersIncluding: requestHeaders.
	(self client notNil and: [McpProtocolVersion isModern: self client
		protocolVersion])
		ifTrue: [self putHeaderName: 'Mcp-Method' value: 'subscriptions/listen'
			into: headers].
	self putHeaderName: 'Accept' value: 'text/event-stream' into: headers.

	exchangeClient := self configuredHttpClientFor: self url.
	[response :=
		exchangeClient
			createAndSendRequestFor: self url
			typed: 'application/json'
			using: nil
			withHeaders: headers
			templateMessage: exchangeClient templateHttpPOSTMessage copy
			data: jsonString asUtf8Bytes
			assemblerPolicy: (exchangeClient newAssemblerPolicy streamContents:
				true)]
		on: Error do: [:failure | exchangeClient shutDown. failure pass].

	(response isSstError
		or: [(response respondsTo: #header) and: [response header statusCode >=
			300]])
			ifTrue: [
				exchangeClient shutDown.
				self error: 'HTTP Error on subscriptions/listen: ' , response
				printString].

	stream := response inputStream.
	stream ifNil: [
		exchangeClient shutDown.
		self error: 'No input stream on subscriptions/listen response'].

	subscriptionClient := exchangeClient.
	ackSemaphore := Semaphore new.
	ackResult := nil.
	receiveBuffer := #[].
	parser := McpSseParser new.
	isDone := false.

	subscriptionStream :=
		stream
			listen: [:chunk |
				receiveBuffer := parser
					parseAvailableBytes: (receiveBuffer , chunk asByteArray)
					do: [:event |
						event data isEmpty ifFalse: [| parsed |
							parsed := [McpJSONReader fromString: event data]
								on: Error do: [:e | nil].
							parsed ifNotNil: [| isAck |
								isAck :=
									((parsed at: 'method' ifAbsent: [nil]) = 'notifications/subscriptions/acknowledged'
										and: [| meta |
											meta := (parsed at: 'params' ifAbsent: [EsOrderedDictionary new]) at: '_meta' ifAbsent: [EsOrderedDictionary new].
											(meta at: 'io.modelcontextprotocol/subscriptionId' ifAbsent: [nil]) = requestId])
										or: [((parsed at: 'id' ifAbsent: [nil]) = requestId and: [ackResult isNil])].
								(isAck and: [ackResult isNil])
									ifTrue: [
										ackResult :=
											(parsed includesKey: 'result')
												ifTrue: [self validatedResultFrom: parsed id: requestId]
												ifFalse: [
													(parsed at: 'params' ifAbsent: [EsOrderedDictionary new])
														at: 'notifications'
														ifAbsent: [parsed at: 'params' ifAbsent: [EsOrderedDictionary new]]].
										ackSemaphore signal]
									ifFalse: [self client ifNotNil: [:c |
										c handleIncomingMessage: parsed]]]]]]
			onError: [:err |
				isDone
					ifFalse: [
						isDone := true.
						ackSemaphore signal]]
			onDone: [
				isDone
					ifFalse: [
						isDone := true.
						ackSemaphore signal]]
			cancelOnError: false.

	ackSemaphore wait.
	ackResult ifNil: [self error:
		'Failed to receive subscription acknowledgment'].
	^ackResult
]

{ #category : 'Protocol Operations',
  #vaVisibility : 'private' }
McpHttpClientTransport >> doSendRequest: requestDictionary id: requestId [
	"Send a JSON-RPC request without request-scoped HTTP headers.

	 Arguments:
		requestDictionary - <Dictionary> JSON-RPC request.
		requestId - <Object> request identifier.
	 Answers:
		<Object> JSON-RPC result."

	^self doSendRequest: requestDictionary id: requestId headers: nil
]

{ #category : 'Execution',
  #vaVisibility : 'private' }
McpHttpClientTransport >> doSendRequest: requestDictionary id: requestId headers: requestHeaders [
	"Send a request using a fresh SST exchange and recover stale sessions once.

	 An initialization request with a stale local session retries directly
	 after clearing that session, avoiding recursive connection locking.

	 Arguments:
		requestDictionary - <KeyedCollection> JSON-RPC request.
		requestId - <String> or <Number> request identifier.
		requestHeaders - <KeyedCollection> validated headers, or nil.
	 Answers:
		<Object> validated JSON-RPC result."

	| jsonString responseOrError response resultDictionary result contentType allowRetry done headers
	  isInitialize mediaType isJson |

	(requestDictionary isKindOf: KeyedCollection)
		ifFalse: [self error: 'MCP request must be a keyed collection'].
	(requestId isString or: [requestId isNumber])
		ifFalse: [self error: 'MCP request identifier is invalid'].
	url ifNil: [self error: 'MCP HTTP endpoint is not configured'].

	((requestDictionary at: 'method' ifAbsent: [nil]) = 'subscriptions/listen')
		ifTrue: [^self doSendListenRequest: requestDictionary id: requestId headers: requestHeaders].

	isInitialize := (requestDictionary at: 'method' ifAbsent: [nil]) = 'initialize'.
	jsonString :=
		String streamContents: [:stream | (McpJSONWriter on: stream) nextPut: requestDictionary].
	allowRetry := true.
	done := false.
	[done] whileFalse: [
		headers := self headersIncluding: requestHeaders.
		(self client notNil and: [McpProtocolVersion isModern: self client protocolVersion])
			ifTrue: [| method params |
				method := requestDictionary at: 'method' ifAbsent: [nil].
				method ifNotNil: [
					self putHeaderName: 'Mcp-Method' value: method into: headers.
					params := requestDictionary at: 'params' ifAbsent: [nil].
					(params isKindOf: KeyedCollection)
						ifTrue: [
							(#('tools/call' 'prompts/get') includes: method)
								ifTrue: [
									(params at: 'name' ifAbsent: [nil]) ifNotNil: [:n |
										self
											putHeaderName: 'Mcp-Name'
											value: (self encodeHeaderValue: n)
											into: headers]].
							method = 'resources/read'
								ifTrue: [
									(params at: 'uri' ifAbsent: [nil]) ifNotNil: [:u |
										self
											putHeaderName: 'Mcp-Name'
											value: (self encodeHeaderValue: u)
											into: headers]]]]].
		responseOrError :=
			self withHttpClientDo: [:exchangeClient |
				exchangeClient
					post: jsonString asUtf8Bytes
					typed: 'application/json'
					at: self url
					using: nil
					withHeaders: headers].
		response := self responseMessageFrom: responseOrError.
		(response header statusCode between: 300 and: 399)
			ifTrue: [self error: 'MCP HTTP redirect was not followed'].
		contentType := response header contentType.
		mediaType := contentType ifNotNil: [self baseMediaTypeFrom: contentType].
		isJson := mediaType notNil and: [mediaType sameAs: 'application/json'].
		response header statusCode >= 400
			ifTrue: [
				(response header statusCode = 404 and: [sessionID notNil and: [allowRetry]])
					ifTrue: [
						sessionID := nil.
						allowRetry := false.
						isInitialize
							ifFalse: [
								self client ifNil: [self error: 'MCP transport has no owning client'].
								self client markDisconnected.
								self client connectWithHeaders: requestHeaders]]
					ifFalse: [
						isJson
							ifTrue: [
								resultDictionary :=
									[
										self
											parseResponse: response contents
											contentType: contentType
											id: requestId]
												on: Error
												do: [:parseErr | nil].
								resultDictionary ifNotNil: [
									^self validatedResultFrom: resultDictionary id: requestId]].
						self error: 'HTTP Error: ' , response header status]]
			ifFalse: [done := true]].
	contentType ifNil: [self error: 'Missing Content-Type'].
	resultDictionary := self parseResponse: response contents contentType: contentType id: requestId.
	result := self validatedResultFrom: resultDictionary id: requestId.
	isInitialize ifTrue: [self captureSessionFrom: response].
	^result
]

{ #category : 'Header Construction',
  #vaVisibility : 'private' }
McpHttpClientTransport >> encodeHeaderValue: aString [
	"Encode a string value using the Base64 sentinel format =?base64?{value}?=
	 if it contains non-ASCII characters, control characters, leading/trailing whitespace,
	 or matches the sentinel prefix/suffix per SEP-2243.

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

{ #category : 'Validation',
  #vaVisibility : 'private' }
McpHttpClientTransport >> existingNameFor: headerName in: headers [
	"Answer the existing case-insensitive header name, or nil.

	 Arguments:
		headerName - <String> candidate HTTP header name.
		headers - <KeyedCollection> existing headers.
	 Answers:
		<String> or nil."

	^headers keys detect: [:existingName | existingName sameAs: headerName] ifNone: [nil]
]

{ #category : 'Configuration',
  #vaVisibility : 'private' }
McpHttpClientTransport >> headersIncluding: requestHeaders [
	"Merge scoped headers over persistent and protocol headers.

	 Header matching is case-insensitive, so a scoped credential replaces a
	 persistent credential regardless of its original casing.

	 Arguments:
		requestHeaders - <KeyedCollection> validated headers, or nil.
	 Answers:
		<KeyedCollection> merged request headers."

	| headers |

	headers := self buildHeaders.
	requestHeaders ifNotNil: [
		requestHeaders
			keysAndValuesDo: [:name :value | self putHeaderName: name value: value into: headers]].
	^headers
]

{ #category : 'Initialization',
  #vaVisibility : 'private' }
McpHttpClientTransport >> initialize [
	"Initialize detached headers, timeout, and empty session state.

	 Answers:
		<McpHttpClientTransport> the receiver."

	super initialize.
	additionalHeaders := EsOrderedDictionary new.
	requestTimeout := 60000.
	sessionID := nil.
	^self
]

{ #category : 'Validation',
  #vaVisibility : 'private' }
McpHttpClientTransport >> isProtocolControlledHeader: headerName [
	"Answer whether the MCP transport owns an HTTP header.

	 Arguments:
		headerName - <String> case-insensitive HTTP header name.
	 Answers:
		<Boolean>."

	^#('accept' 'connection' 'content-length' 'content-type' 'host' 'mcp-protocol-version'
	'mcp-session-id' 'mcp-method' 'mcp-name')
		includes: headerName asLowercase
]

{ #category : 'Parsing',
  #vaVisibility : 'private' }
McpHttpClientTransport >> parseResponse: responseBytes contentType: contentType id: requestId [
	"Parse JSON or buffered SSE and answer one correlated response.

	 Other SSE JSON-RPC messages are delivered to the owning client in
	 production order. Multiple responses for the request identifier are
	 rejected as ambiguous.

	 Arguments:
		responseBytes - <ByteArray> response entity bytes.
		contentType - <String> response media type.
		requestId - <String> or <Number> expected identifier.
	 Answers:
		<KeyedCollection> matching JSON-RPC response."

	| events matchingResponse responseString mediaType |

	responseBytes size > (10 * 1024 * 1024)
		ifTrue: [self error: 'Response body exceeded maximum size'].
	responseString := (UnicodeString utf8: responseBytes asByteArray) asString.
	mediaType := self baseMediaTypeFrom: contentType.
	mediaType = 'text/event-stream'
		ifTrue: [
			events := McpSseParser new parse: responseString.
			matchingResponse := nil.
			events do: [:event | | isResponse parsed |
				event data isEmpty
					ifFalse: [
						parsed := McpJSONReader fromString: event data.
						(parsed isKindOf: KeyedCollection)
							ifFalse: [self error: 'Invalid SSE message: expected an object'].
						(parsed at: 'jsonrpc' ifAbsent: [nil]) = '2.0'
							ifFalse: [self error: 'Invalid SSE message: invalid jsonrpc version'].
						isResponse :=
							((parsed includesKey: 'result') = (parsed includesKey: 'error')) not.
						(isResponse and: [(parsed at: 'id' ifAbsent: [nil]) = requestId])
							ifTrue: [
								matchingResponse
									ifNotNil: [self error: 'Duplicate correlated SSE response'].
								matchingResponse := parsed]
							ifFalse: [
								self client ifNotNil: [self client handleIncomingMessage: parsed]]]].
			matchingResponse ifNil: [self error: 'No matching JSON-RPC response found in SSE stream'].
			^matchingResponse].
	mediaType = 'application/json'
		ifFalse: [self error: 'Unsupported MCP response Content-Type: ' , mediaType].
	responseString isEmpty ifTrue: [self error: 'MCP JSON response body is empty'].
	^McpJSONReader fromString: responseString
]

{ #category : 'Configuration',
  #vaVisibility : 'private' }
McpHttpClientTransport >> putHeaderName: headerName value: headerValue into: headers [
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
McpHttpClientTransport >> requestTimeout [
	"Answer the SST negotiation, send, and receive timeout in milliseconds.

	 Answers:
		<Integer>."

	^requestTimeout ifNil: [60000]
]

{ #category : 'Accessing' }
McpHttpClientTransport >> requestTimeout: milliseconds [
	"Set the SST I/O timeout and rebuild an existing endpoint connection.

	 The timeout applies independently to connection negotiation, blocking
	 sends, and blocking receives. Changing it terminates any active session.

	 Arguments:
		milliseconds - <Integer> positive timeout in milliseconds.
	 Answers:
		<McpHttpClientTransport>."

	milliseconds isInteger ifFalse: [self error: 'Request timeout must be an integer'].
	milliseconds > 0 ifFalse: [self error: 'Request timeout must be positive'].
	requestTimeout := milliseconds.
	url ifNotNil: [self url: url].
	^self
]

{ #category : 'Formatting',
  #vaVisibility : 'private' }
McpHttpClientTransport >> responseMessageFrom: responseOrError [
	"Answer an HTTP response carried directly or by an SST receive error.

	 SST represents non-successful HTTP statuses as receive errors whose
	 error object is the received HTTP response. Communication failures do
	 not carry such a response and remain transport errors.

	 Arguments:
		responseOrError - <SstCommunicationMessage> or <SstError>.
	 Answers:
		<SstCommunicationMessage>."

	| errorObject |

	responseOrError isSstError ifFalse: [^responseOrError].
	errorObject := responseOrError errorObject.
	(errorObject isKindOf: SstCommunicationMessage) ifTrue: [^errorObject].
	self error: 'HTTP request failed: ' , responseOrError printString
]

{ #category : 'Protocol Operations' }
McpHttpClientTransport >> sendNotification: notification [
	"Send a notification using persistent transport headers.

	 Arguments:
		notification - <KeyedCollection> JSON-RPC notification.
	 Answers:
		<McpHttpClientTransport> the receiver."

	^self sendNotification: notification headers: nil
]

{ #category : 'Sending' }
McpHttpClientTransport >> sendNotification: notification headers: requestHeaders [
	"Send a notification in one isolated SST exchange.

	 Arguments:
		notification - <KeyedCollection> JSON-RPC notification.
		requestHeaders - <KeyedCollection> HTTP headers, or nil.
	 Answers:
		<McpHttpClientTransport> the receiver."

	| jsonString responseOrError response headers |

	(notification isKindOf: KeyedCollection)
		ifFalse: [self error: 'MCP notification must be a keyed collection'].
	url ifNil: [self error: 'MCP HTTP endpoint is not configured'].
	headers := self headersIncluding: (self validatedRequestHeadersFrom: requestHeaders).
	jsonString := String streamContents: [:stream | (McpJSONWriter on: stream) nextPut: notification].
	responseOrError :=
		self withHttpClientDo: [:exchangeClient |
			exchangeClient
				post: jsonString asUtf8Bytes
				typed: 'application/json'
				at: self url
				using: nil
				withHeaders: headers].
	response := self responseMessageFrom: responseOrError.
	response header statusCode = 202
		ifFalse: [self error: 'MCP notification was not accepted: ' , response header status].
	^self
]

{ #category : 'Protocol Operations' }
McpHttpClientTransport >> sendRequest: requestDictionary id: requestId [
	"Send a JSON-RPC request and answer its result.

	 Protocol errors retain their `McpJsonRpcError` code, message, and data.
	 Transport and implementation errors retain their original signal and
	 execution context.

	 Arguments:
		requestDictionary - <Dictionary> JSON-RPC request.
		requestId - <Object> request identifier.
	 Answers:
		<Object> JSON-RPC result."

	^self doSendRequest: requestDictionary id: requestId
]

{ #category : 'Protocol Operations' }
McpHttpClientTransport >> sendRequest: requestDictionary id: requestId headers: requestHeaders [
	"Send a JSON-RPC request with validated request-scoped HTTP headers.

	 The supplied headers may carry credentials such as `Authorization`, but
	 cannot replace fields owned by HTTP framing or the MCP transport.

	 Arguments:
		requestDictionary - <Dictionary> JSON-RPC request.
		requestId - <Object> request identifier.
		requestHeaders - <Dictionary> request-scoped HTTP headers or nil.
	 Answers:
		<Object> JSON-RPC result."

	^self
		doSendRequest: requestDictionary
		id: requestId
		headers: (self validatedRequestHeadersFrom: requestHeaders)
]

{ #category : 'Session Management' }
McpHttpClientTransport >> sessionID [
	"Answer a copy of the negotiated session identifier.

	 Answers:
		<String> or nil."

	sessionID ifNil: [^nil].
	^sessionID copy
]

{ #category : 'Accessing' }
McpHttpClientTransport >> supportsRequestHeaders [
	"Answer whether this transport supports request-scoped HTTP headers.

	 Answers:
		<Boolean>."

	^true
]

{ #category : 'Execution',
  #vaVisibility : 'private' }
McpHttpClientTransport >> terminateSession [
	"Terminate the logical MCP session in one isolated SST exchange.

	 Answers:
		<McpHttpClientTransport> the receiver."

	| responseOrError response statusCode |

	(sessionID isNil or: [url isNil]) ifTrue: [^self].
	responseOrError :=
		self withHttpClientDo: [:exchangeClient |
			exchangeClient delete: self url typed: nil using: nil withHeaders:
				self buildHeaders].
	response := self responseMessageFrom: responseOrError.
	statusCode := response header statusCode.
	(statusCode >= 300 and: [statusCode ~= 404 and: [statusCode ~= 405]])
		ifTrue: [self error: 'MCP session termination failed: ' , response
			header status].
	sessionID := nil.
	^self

]

{ #category : 'Accessing' }
McpHttpClientTransport >> tokenProvider [
	"Answer the dynamic token provider block, or nil.

	 Answers:
		<Block> or nil."

	^tokenProvider
]

{ #category : 'Accessing' }
McpHttpClientTransport >> tokenProvider: aBlock [
	"Set the dynamic token provider block.

	 Arguments:
		aBlock - <Block> or nil.
	 Answers:
		<McpHttpClientTransport> the receiver."

	tokenProvider := aBlock.
	^self
]

{ #category : 'Accessing' }
McpHttpClientTransport >> url [
	"Answer a copy of the configured MCP endpoint.

	 Answers:
		<SstHttpUrl> or nil."

	url ifNil: [^nil].
	^url copy
]

{ #category : 'Accessing' }
McpHttpClientTransport >> url: aUrl [
	"Validate and set the MCP endpoint using isolated SST configuration.

	 Changing the endpoint terminates the prior transport session and marks
	 its owning MCP client disconnected.

	 Arguments:
		aUrl - <String> or <SstHttpUrl> endpoint.
	 Answers:
		<McpHttpClientTransport>."

	| resolvedUrl scheme address |

	(aUrl isString or: [aUrl isKindOf: SstHttpUrl])
		ifFalse: [self error: 'MCP endpoint must be an HTTP or HTTPS URL'].
	resolvedUrl := aUrl sstAsUrl.
	(resolvedUrl isKindOf: SstHttpUrl)
		ifFalse: [self error: 'MCP endpoint must be an HTTP or HTTPS URL'].
	scheme := resolvedUrl scheme.
	(scheme notNil and: [(scheme sameAs: 'http') or: [scheme sameAs: 'https']])
		ifFalse: [self error: 'MCP endpoint must use HTTP or HTTPS'].
	address := resolvedUrl address.
	(address isString and: [address isEmpty not])
		ifFalse: [self error: 'MCP endpoint host is required'].

	self close.
	self client ifNotNil: [self client markDisconnected].
	url := resolvedUrl copy.
	httpClient := self configuredHttpClientFor: url.
	^self
]

{ #category : 'Validation',
  #vaVisibility : 'private' }
McpHttpClientTransport >> validateHeaderName: headerName value: headerValue [
	"Validate one HTTP field against token and line-safety requirements.

	 Arguments:
		headerName - <String> HTTP header name.
		headerValue - <String> HTTP header value.
	 Answers:
		<McpHttpClientTransport> the receiver."

	| tokenPunctuation |

	(headerName isString and: [headerValue isString])
		ifFalse: [self error: 'HTTP header names and values must be strings'].
	headerName isEmpty ifTrue: [self error: 'HTTP header name must not be empty'].
	tokenPunctuation := '!#$%&''*+-.^_`|~'.
	(headerName allSatisfy: [:character |
		character isAscii and: [character isAlphaNumeric or: [tokenPunctuation includes: character]]])
			ifFalse: [self error: 'HTTP header name contains an invalid character'].
	((headerValue includes: Character cr) or: [headerValue includes: Character lf])
		ifTrue: [self error: 'HTTP header value must not contain a line break'].
	^self
]

{ #category : 'Validation',
  #vaVisibility : 'private' }
McpHttpClientTransport >> validatedRequestHeadersFrom: requestHeaders [
	"Validate and detach request-scoped HTTP headers.

	 Arguments:
		requestHeaders - <KeyedCollection> headers, or nil.
	 Answers:
		<KeyedCollection> detached headers, or nil."

	| snapshot existingName |

	requestHeaders ifNil: [^nil].
	(requestHeaders isKindOf: KeyedCollection)
		ifFalse: [self error: 'Request headers must be a keyed collection'].
	snapshot := EsOrderedDictionary new.
	requestHeaders keysAndValuesDo: [:headerName :headerValue |
		self validateHeaderName: headerName value: headerValue.
		(self isProtocolControlledHeader: headerName)
			ifTrue: [self error: 'HTTP header is controlled by the MCP transport: ' , headerName].
		existingName := self existingNameFor: headerName in: snapshot.
		existingName ifNotNil: [self error: 'Duplicate HTTP header: ' , headerName].
		snapshot at: headerName copy put: headerValue copy].
	^snapshot
]

{ #category : 'Validation',
  #vaVisibility : 'private' }
McpHttpClientTransport >> validatedResultFrom: resultDictionary id: requestId [
	"Validate a JSON-RPC response and answer its result.

	 Arguments:
		resultDictionary - <Dictionary> decoded response.
		requestId - <Object> expected identifier.
	 Answers:
		<Object> JSON-RPC result."

	| errorDictionary responseId |

	(resultDictionary isKindOf: KeyedCollection)
		ifFalse: [self error: 'Invalid response: not a JSON object'].
	(resultDictionary at: 'jsonrpc' ifAbsent: [nil]) = '2.0'
		ifFalse: [self error: 'Invalid response: missing or incorrect jsonrpc version'].
	((resultDictionary includesKey: 'result') = (resultDictionary includesKey: 'error'))
		ifTrue: [self error: 'Invalid response: must contain exactly one of result or error'].
	responseId := resultDictionary at: 'id' ifAbsent: [nil].
	(resultDictionary includesKey: 'error')
		ifTrue: [
			(responseId notNil and: [responseId ~= requestId])
				ifTrue: [self error: 'Invalid response: ID mismatch'].
			errorDictionary := resultDictionary at: 'error'.
			(errorDictionary isKindOf: KeyedCollection)
				ifFalse: [self error: 'Invalid response: error is not an object'].
			(errorDictionary at: 'code' ifAbsent: [nil]) isInteger
				ifFalse: [self error: 'Invalid response: error code must be an integer'].
			(errorDictionary at: 'message' ifAbsent: [nil]) isString
				ifFalse: [self error: 'Invalid response: error message must be a string'].
			McpJsonRpcError
				signalCode: (errorDictionary at: 'code')
				message: (errorDictionary at: 'message')
				data: (errorDictionary at: 'data' ifAbsent: [nil])].
	responseId = requestId ifFalse: [self error: 'Invalid response: ID mismatch'].
	^resultDictionary at: 'result'
]

{ #category : 'Connection Lifecycle',
  #vaVisibility : 'private' }
McpHttpClientTransport >> withHttpClientDo: aBlock [
	"Evaluate aBlock with one SST client and always shut that client down.

	 A client prepared during endpoint configuration is consumed by the first
	 exchange. Later exchanges create their own client from the endpoint and
	 current timeout configuration.

	 Arguments:
		aBlock - <Block> accepting an <SstHttpClient>.
	 Answers:
		<Object> the block answer."

	| exchangeClient |

	url ifNil: [self error: 'MCP HTTP endpoint is not configured'].
	exchangeClient := httpClient.
	exchangeClient ifNil: [exchangeClient := self configuredHttpClientFor: url].
	httpClient := nil.
	^[aBlock cull: exchangeClient] ensure: [exchangeClient shutDown]
]
