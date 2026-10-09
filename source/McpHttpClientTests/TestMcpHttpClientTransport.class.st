"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# TestMcpHttpClientTransport

`TestMcpHttpClientTransport` verifies the Streamable HTTP client transport.

## Responsibilities

- Verify HTTP and MCP header ownership and isolation.
- Verify request, notification, response, and session contracts.
- Verify exchange-scoped SST ownership and deterministic cleanup.
- Verify JSON and buffered SSE validation boundaries.

## Lifecycle and boundaries

Each test owns an inspectable transport and scripted SST collaborator. Tests
perform no network access. The collaborator records every POST, DELETE, and
shutdown so physical exchange cleanup is deterministic and observable.
"
Class {
	#name : 'TestMcpHttpClientTransport',
	#superclass : 'TestCase',
	#instVars : [
		'transport',
		'httpClient'
	],
	#category : 'McpHttpClientTests'
}

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpHttpClientTransport >> establishSession: sessionIdentifier id: identifier [
	"Establish one transport session without negotiating the owning client."

	httpClient enqueueResponse: (self initializeResponseId: identifier session: sessionIdentifier).
	transport sendRequest: (self requestMethod: 'initialize' id: identifier) id: identifier.
	^self
]

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpHttpClientTransport >> headerNamed: fieldName in: headers [
	"Answer a header value by case-insensitive name, or nil."

	| existingName |

	existingName := headers keys detect: [:name | name sameAs: fieldName] ifNone: [nil].
	^existingName ifNil: [nil] ifNotNil: [headers at: existingName]
]

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpHttpClientTransport >> headerOccurrenceCount: fieldName in: headers [
	"Answer the count of case-insensitive occurrences of one header."

	^(headers keys select: [:name | name sameAs: fieldName]) size
]

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpHttpClientTransport >> initializeResponseId: identifier session: sessionIdentifier [
	"Answer a valid initialization response with an optional session ID."

	| result response serverInfo |

	serverInfo :=
		EsOrderedDictionary new
			at: 'name' put: 'scripted-server';
			at: 'version' put: '1.0';
			yourself.
	result :=
		EsOrderedDictionary new
			at: 'protocolVersion' put: McpClient supportedProtocolVersions first;
			at: 'capabilities' put: EsOrderedDictionary new;
			at: 'serverInfo' put: serverInfo;
			yourself.
	response :=
		self
			jsonResultResponseId: identifier
			result: result
			status: 200
			contentType: 'application/json'.
	sessionIdentifier ifNotNil: [response header at: 'MCP-Session-Id' put: sessionIdentifier].
	^response
]

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpHttpClientTransport >> jsonErrorResponseId: identifier code: code message: message data: data [
	"Answer an HTTP JSON-RPC error response."

	| error response |

	error :=
		EsOrderedDictionary new
			at: 'code' put: code;
			at: 'message' put: message;
			yourself.
	data ifNotNil: [error at: 'data' put: data].
	response :=
		EsOrderedDictionary new
			at: 'jsonrpc' put: '2.0';
			at: 'id' put: identifier;
			at: 'error' put: error;
			yourself.
	^self responseStatus: 200 contentType: 'application/json' jsonObject: response
]

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpHttpClientTransport >> jsonFromBytes: bytes [
	"Decode one UTF-8 JSON fixture."

	^McpJSONReader fromString: (UnicodeString utf8: bytes asByteArray)
]

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpHttpClientTransport >> jsonResultResponseId: identifier result: result status: statusCode contentType: contentType [
	"Answer an HTTP JSON-RPC result response."

	^self
		responseStatus: statusCode
		contentType: contentType
		jsonObject: (self jsonRpcResultId: identifier result: result)
]

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpHttpClientTransport >> jsonRpcResultId: identifier result: result [
	"Answer a JSON-RPC success response dictionary."

	^EsOrderedDictionary new
		at: 'jsonrpc' put: '2.0';
		at: 'id' put: identifier;
		at: 'result' put: result;
		yourself
]

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpHttpClientTransport >> lf [
	"Answer one line-feed string."

	^String with: Character lf
]

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpHttpClientTransport >> requestMethod: methodName id: identifier [
	"Answer a JSON-RPC request fixture."

	^EsOrderedDictionary new
		at: 'jsonrpc' put: '2.0';
		at: 'id' put: identifier;
		at: 'method' put: methodName;
		yourself
]

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpHttpClientTransport >> responseStatus: statusCode contentType: contentType contents: bytes [
	"Answer one scripted HTTP response."

	| header |

	header :=
		McpHttpClientTestResponseHeader new
			statusCode: statusCode;
			contentType: contentType;
			yourself.
	^McpHttpClientTestResponse new
		header: header;
		contents: bytes;
		yourself
]

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpHttpClientTransport >> responseStatus: statusCode contentType: contentType jsonObject: object [
	"Answer one scripted HTTP response containing encoded JSON."

	| json |

	json := String streamContents: [:stream | (McpJSONWriter on: stream) nextPut: object].
	^self responseStatus: statusCode contentType: contentType contents: json asUtf8Bytes
]

{ #category : 'Initialization' }
TestMcpHttpClientTransport >> setUp [
	"Create a transport configured with a scripted HTTP client."

	super setUp.
	httpClient := McpScriptedHttpClient new.
	transport := McpInspectableHttpClientTransport new.
	transport scriptedHttpClient: httpClient.
	transport url: 'http://example.test/mcp'
]

{ #category : 'Copying' }
TestMcpHttpClientTransport >> testAdditionalHeadersAreDetached [
	"Persistent headers are isolated at assignment and access boundaries."

	| source value returned |

	value := 'Bearer original' copy.
	source := EsOrderedDictionary with: 'Authorization' -> value.
	transport additionalHeaders: source.
	value at: 8 put: $X.
	source at: 'Authorization' put: 'changed'.
	self assert: (transport additionalHeaders at: 'Authorization') equals: 'Bearer original'.
	returned := transport additionalHeaders.
	returned at: 'Authorization' put: 'returned change'.
	self assert: (transport additionalHeaders at: 'Authorization') equals: 'Bearer original'
]

{ #category : 'Header Tests' }
TestMcpHttpClientTransport >> testAdditionalHeadersMayBeCleared [
	"Clearing caller headers retains only the required Accept header."

	transport additionalHeaders: (EsOrderedDictionary with: 'X-Trace' -> 'trace-1').
	transport additionalHeaders: nil.
	self assert: transport additionalHeaders isEmpty.
	self assert: transport buildHeaders size equals: 1.
	self
		assert: (self headerNamed: 'Accept' in: transport buildHeaders)
		equals: 'application/json, text/event-stream'
]

{ #category : 'Validation' }
TestMcpHttpClientTransport >> testAdditionalHeadersRejectInvalidNamesAndValues [
	"Header names are tokens and names and values must be strings."

	self should: [transport additionalHeaders: (EsOrderedDictionary with: 1 -> 'value')] raise: Error.
	self
		should: [transport additionalHeaders: (EsOrderedDictionary with: 'X-Trace' -> 1)]
		raise: Error.
	self
		should: [transport additionalHeaders: (EsOrderedDictionary with: '' -> 'value')]
		raise: Error.
	self
		should: [transport additionalHeaders: (EsOrderedDictionary with: 'Bad Header' -> 'value')]
		raise: Error.
	self
		should: [transport additionalHeaders: (EsOrderedDictionary with: 'Bad:Header' -> 'value')]
		raise: Error
]

{ #category : 'Validation' }
TestMcpHttpClientTransport >> testAdditionalHeadersRejectUnsafeOrControlledFields [
	"Persistent headers reject duplicates, framing fields, and line breaks."

	| headers |

	headers :=
		EsOrderedDictionary new
			at: 'X-Trace' put: 'first';
			at: 'x-trace' put: 'second';
			yourself.
	self should: [transport additionalHeaders: headers] raise: Error.
	self
		should: [
			transport additionalHeaders: (EsOrderedDictionary with: 'accept' -> 'application/json')]
		raise: Error.
	self
		should: [
			transport additionalHeaders:
				(EsOrderedDictionary with: 'X-Unsafe' -> ('one' , self lf , 'two'))]
		raise: Error
]

{ #category : 'Validation' }
TestMcpHttpClientTransport >> testAllProtocolControlledHeadersAreRejected [
	"Caller headers cannot replace HTTP framing or MCP protocol fields."

	#('Accept' 'Connection' 'Content-Length' 'Content-Type' 'Host' 'MCP-Protocol-Version'
	'MCP-Session-ID')
		do: [:name |
			self
				should: [transport additionalHeaders: (EsOrderedDictionary with: name -> 'value')]
				raise: Error]
]

{ #category : 'Header Tests' }
TestMcpHttpClientTransport >> testBuildHeadersIncludesRequiredAcceptOnlyBeforeNegotiation [
	"An uninitialized transport sends the required POST Accept header."

	| headers |

	headers := transport buildHeaders.
	self assert: headers size equals: 1.
	self
		assert: (self headerNamed: 'Accept' in: headers)
		equals: 'application/json, text/event-stream'.
	self assert: (self headerNamed: 'Connection' in: headers) equals: nil.
	self assert: (self headerNamed: 'MCP-Session-Id' in: headers) equals: nil.
	self assert: (self headerNamed: 'MCP-Protocol-Version' in: headers) equals: nil
]

{ #category : 'Protocol Operations' }
TestMcpHttpClientTransport >> testCallToolEmitsMcpParamHeadersForAnnotatedParameters [
	"Calling a tool with parameters annotated with x-mcp-header emits Mcp-Param-* HTTP headers."

	| client toolSchema properties result post headers |

	client := McpClient modern.
	client transport: transport.
	client priorDiscover: (
		EsOrderedDictionary new
			at: 'capabilities' put: (EsOrderedDictionary with: 'tools' -> EsOrderedDictionary new);
			at: 'supportedVersions' put: #('2026-07-28');
			yourself).
	client connect.

	properties :=
		EsOrderedDictionary new
			at: 'region'
				put: (
					EsOrderedDictionary new
						at: 'type' put: 'string';
						at: 'x-mcp-header' put: 'Region';
						yourself);
			at: 'query'
				put: (EsOrderedDictionary with: 'type' -> 'string');
			yourself.
	toolSchema :=
		EsOrderedDictionary new
			at: 'type' put: 'object';
			at: 'properties' put: properties;
			at: 'required' put: #('region' 'query');
			yourself.
	client knownToolSchemas at: 'execute_sql' put: toolSchema.
	client knownToolOutputSchemas at: 'execute_sql' put: nil.

	httpClient enqueueResponse: (
		self
			jsonResultResponseId: 1
			result: (
				EsOrderedDictionary new
					at: 'resultType' put: 'complete';
					at: 'content' put: (Array with: (EsOrderedDictionary with: 'type' -> 'text' with: 'text' -> '1 row'));
					at: 'isError' put: false;
					yourself)
			status: 200
			contentType: 'application/json').

	result :=
		client
			callTool: 'execute_sql'
			arguments: (
				EsOrderedDictionary new
					at: 'region' put: 'us-west1';
					at: 'query' put: 'SELECT 1';
					yourself).

	self assert: httpClient posts size equals: 1.
	post := httpClient posts first.
	headers := post at: 'headers'.
	self assert: (self headerNamed: 'Mcp-Method' in: headers) equals: 'tools/call'.
	self assert: (self headerNamed: 'Mcp-Name' in: headers) equals: 'execute_sql'.
	self assert: (self headerNamed: 'Mcp-Param-Region' in: headers) equals: 'us-west1'
]

{ #category : 'Lifecycle Tests' }
TestMcpHttpClientTransport >> testChangingEndpointTerminatesPriorSession [
	"Changing the URL terminates both prior HTTP exchanges cleanly."

	self establishSession: 'endpoint-session' id: 60.
	httpClient enqueueResponse: (self responseStatus: 200 contentType: nil contents: #()).
	transport url: 'https://other.example.test/mcp'.
	self assert: httpClient deletes size equals: 1.
	self assert: httpClient shutdownCount equals: 2.
	self assert: transport sessionID equals: nil
]

{ #category : 'Lifecycle Tests' }
TestMcpHttpClientTransport >> testCloseAcceptsMissingSessionStatus [
	"A missing server session still closes both HTTP exchanges cleanly."

	self establishSession: 'missing-session' id: 40.
	httpClient enqueueResponse: (self responseStatus: 404 contentType: nil contents: #()).
	transport close.
	self assert: httpClient deletes size equals: 1.
	self assert: httpClient shutdownCount equals: 2.
	self assert: transport sessionID equals: nil
]

{ #category : 'Lifecycle Tests' }
TestMcpHttpClientTransport >> testCloseAcceptsTerminationUnsupportedStatus [
	"An unsupported DELETE still closes both HTTP exchanges cleanly."

	self establishSession: 'unsupported-delete' id: 41.
	httpClient enqueueResponse: (self responseStatus: 405 contentType: nil contents: #()).
	transport close.
	self assert: httpClient deletes size equals: 1.
	self assert: httpClient shutdownCount equals: 2.
	self assert: transport sessionID equals: nil
]

{ #category : 'Lifecycle Tests' }
TestMcpHttpClientTransport >> testCloseCleansUpWhenTerminationFails [
	"A failed DELETE still shuts down its exchange and clears state."

	self establishSession: 'failing-delete' id: 42.
	httpClient enqueueResponse: (self responseStatus: 500 contentType: nil contents: #()).
	self should: [transport close] raise: Error.
	self assert: httpClient deletes size equals: 1.
	self assert: httpClient shutdownCount equals: 2.
	self assert: transport sessionID equals: nil
]

{ #category : 'Lifecycle Tests' }
TestMcpHttpClientTransport >> testCloseTerminatesActiveSessionAndShutsDown [
	"Close isolates initialization and DELETE in separate SST exchanges."

	| response deleteHeaders |

	response :=
		self
			jsonResultResponseId: 1
			result: EsOrderedDictionary new
			status: 200
			contentType: 'application/json'.
	response header at: 'MCP-Session-Id' put: 'session-1'.
	httpClient enqueueResponse: response.
	transport sendRequest: (self requestMethod: 'initialize' id: 1) id: 1.
	httpClient enqueueResponse: (self responseStatus: 200 contentType: nil contents: #()).
	transport close.
	self assert: httpClient deletes size equals: 1.
	deleteHeaders := httpClient deletes first at: 'headers'.
	self assert: (self headerNamed: 'MCP-Session-Id' in: deleteHeaders) equals: 'session-1'.
	self assert: httpClient shutdownCount equals: 2.
	self assert: transport sessionID equals: nil
]

{ #category : 'Session Management' }
TestMcpHttpClientTransport >> testCloseWithoutSessionSkipsDelete [
	"Closing without an active session shuts SST down without DELETE."

	transport close.
	self assert: httpClient deletes isEmpty.
	self assert: httpClient shutdownCount equals: 1.
	self assert: transport sessionID equals: nil
]

{ #category : 'Lifecycle Tests' }
TestMcpHttpClientTransport >> testConnectUsesSeparateSstExchanges [
	"Initialization and its notification each shut down their SST exchange."

	| client |

	client := McpClient new.
	client transport: transport.
	httpClient enqueueResponse: (self initializeResponseId: 1 session: 'handshake-session').
	httpClient enqueueResponse: (self responseStatus: 202 contentType: nil contents: #()).
	client connect.
	self assert: client isConnected.
	self assert: httpClient posts size equals: 2.
	self assert: httpClient shutdownCount equals: 2.
	self
		assert: (self headerNamed: 'MCP-Session-Id' in: (httpClient posts second at: 'headers'))
		equals: 'handshake-session'
]

{ #category : 'Configuration' }
TestMcpHttpClientTransport >> testDefaultRequestTimeout [
	"The default timeout is sixty seconds for each SST I/O phase."

	self assert: transport requestTimeout equals: 60000
]

{ #category : 'Validation' }
TestMcpHttpClientTransport >> testEmptyAndNonObjectJsonResponsesAreRejected [
	"A request response must decode to one JSON-RPC object."

	httpClient
		enqueueResponse: (self responseStatus: 200 contentType: 'application/json' contents: #()).
	self should: [transport sendRequest: (self requestMethod: 'ping' id: 61) id: 61] raise: Error.
	httpClient enqueueResponse:
		(self responseStatus: 200 contentType: 'application/json' contents: '[]' asUtf8Bytes).
	self should: [transport sendRequest: (self requestMethod: 'ping' id: 62) id: 62] raise: Error
]

{ #category : 'Session Management' }
TestMcpHttpClientTransport >> testExpiredSessionDuringInitializeRetriesDirectly [
	"A stale initialize request retries without a nested client handshake."

	| result posts firstHeaders retryHeaders |

	self establishSession: 'old-initialize-session' id: 43.
	httpClient enqueueResponse: (self responseStatus: 404 contentType: nil contents: #()).
	httpClient enqueueResponse: (self initializeResponseId: 44 session: 'new-initialize-session').
	result := transport sendRequest: (self requestMethod: 'initialize' id: 44) id: 44.
	self assert: (result at: 'protocolVersion') equals: McpClient supportedProtocolVersions first.
	self assert: transport sessionID equals: 'new-initialize-session'.
	posts := httpClient posts.
	self assert: posts size equals: 3.
	firstHeaders := (posts at: 2) at: 'headers'.
	retryHeaders := (posts at: 3) at: 'headers'.
	self
		assert: (self headerNamed: 'MCP-Session-Id' in: firstHeaders)
		equals: 'old-initialize-session'.
	self assert: (self headerNamed: 'MCP-Session-Id' in: retryHeaders) equals: nil
]

{ #category : 'Session Management' }
TestMcpHttpClientTransport >> testExpiredSessionReinitializesAndRetriesRequestOnce [
	"A stale non-initialize request performs one complete new handshake."

	| client scoped result posts firstHeaders initializeHeaders notificationHeaders retryHeaders
	  initializeRequest notification |

	client := McpClient new.
	client transport: transport.
	self establishSession: 'old-session' id: 45.
	httpClient enqueueResponse: (self responseStatus: 404 contentType: nil contents: #()).
	httpClient enqueueResponse: (self initializeResponseId: 1 session: 'new-session').
	httpClient enqueueResponse: (self responseStatus: 202 contentType: nil contents: #()).
	httpClient enqueueResponse: (
		self
			jsonResultResponseId: 46
			result: (EsOrderedDictionary with: 'recovered' -> true)
			status: 200
			contentType: 'application/json').
	scoped := EsOrderedDictionary with: 'Authorization' -> 'Bearer scoped'.
	result := transport sendRequest: (self requestMethod: 'ping' id: 46) id: 46 headers: scoped.
	self assert: (result at: 'recovered') equals: true.
	self assert: client isConnected.
	self assert: transport sessionID equals: 'new-session'.
	posts := httpClient posts.
	self assert: posts size equals: 5.
	firstHeaders := (posts at: 2) at: 'headers'.
	initializeHeaders := (posts at: 3) at: 'headers'.
	notificationHeaders := (posts at: 4) at: 'headers'.
	retryHeaders := (posts at: 5) at: 'headers'.
	self assert: (self headerNamed: 'MCP-Session-Id' in: firstHeaders) equals: 'old-session'.
	self assert: (self headerNamed: 'MCP-Session-Id' in: initializeHeaders) equals: nil.
	self assert: (self headerNamed: 'MCP-Session-Id' in: notificationHeaders) equals: 'new-session'.
	self assert: (self headerNamed: 'MCP-Session-Id' in: retryHeaders) equals: 'new-session'.
	#(2 3 4 5) do: [:index |
		self
			assert: (self headerNamed: 'Authorization' in: ((posts at: index) at: 'headers'))
			equals: 'Bearer scoped'].
	initializeRequest := self jsonFromBytes: ((posts at: 3) at: 'body').
	notification := self jsonFromBytes: ((posts at: 4) at: 'body').
	self assert: (initializeRequest at: 'method') equals: 'initialize'.
	self assert: (notification at: 'method') equals: 'notifications/initialized'
]

{ #category : 'Session Management' }
TestMcpHttpClientTransport >> testInitializationCapturesVisibleAsciiSessionIdentifier [
	"A successful initialization may establish one visible-ASCII session ID."

	| response result headers |

	response :=
		self
			jsonResultResponseId: 1
			result: (EsOrderedDictionary with: 'ok' -> true)
			status: 200
			contentType: 'application/json; charset=utf-8'.
	response header at: 'mcp-session-id' put: 'session_ABC-123'.
	httpClient enqueueResponse: response.
	result := transport sendRequest: (self requestMethod: 'initialize' id: 1) id: 1.
	self assert: (result at: 'ok') equals: true.
	self assert: transport sessionID equals: 'session_ABC-123'.
	headers := transport buildHeaders.
	self assert: (self headerNamed: 'MCP-Session-Id' in: headers) equals: 'session_ABC-123'
]

{ #category : 'Validation' }
TestMcpHttpClientTransport >> testInitializationRejectsInvalidSessionIdentifier [
	"Initialization rejects session IDs outside visible ASCII."

	| response |

	response :=
		self
			jsonResultResponseId: 1
			result: EsOrderedDictionary new
			status: 200
			contentType: 'application/json'.
	response header at: 'MCP-Session-Id' put: 'bad session'.
	httpClient enqueueResponse: response.
	self should: [transport sendRequest: (self requestMethod: 'initialize' id: 1) id: 1] raise: Error.
	self assert: transport sessionID equals: nil
]

{ #category : 'Validation' }
TestMcpHttpClientTransport >> testInvalidRequestTimeoutsAreRejected [
	"Request timeouts must be positive integers."

	self should: [transport requestTimeout: 0] raise: Error.
	self should: [transport requestTimeout: -1] raise: Error.
	self should: [transport requestTimeout: 1.5] raise: Error.
	self should: [transport requestTimeout: '1000'] raise: Error
]

{ #category : 'Validation' }
TestMcpHttpClientTransport >> testInvalidUrlsAreRejected [
	"Only HTTP or HTTPS endpoints with a host may configure the transport."

	self should: [transport url: 42] raise: Error.
	self should: [transport url: 'file:///tmp/mcp'] raise: Error.
	self should: [transport url: 'http:///mcp'] raise: Error
]

{ #category : 'Protocol Operations' }
TestMcpHttpClientTransport >> testJsonResponseReturnsCorrelatedResult [
	"A JSON response with media-type parameters returns its result."

	| result post parsedRequest |

	httpClient enqueueResponse: (
		self
			jsonResultResponseId: 7
			result: (EsOrderedDictionary with: 'value' -> 'ok')
			status: 200
			contentType: 'Application/JSON; charset=UTF-8').
	result := transport sendRequest: (self requestMethod: 'ping' id: 7) id: 7.
	self assert: (result at: 'value') equals: 'ok'.
	self assert: httpClient posts size equals: 1.
	post := httpClient posts first.
	self assert: (post at: 'mediaType') equals: 'application/json'.
	parsedRequest := self jsonFromBytes: (post at: 'body').
	self assert: (parsedRequest at: 'jsonrpc') equals: '2.0'.
	self assert: (parsedRequest at: 'id') equals: 7.
	self assert: (parsedRequest at: 'method') equals: 'ping'
]

{ #category : 'Protocol Errors' }
TestMcpHttpClientTransport >> testJsonRpcErrorResponsePreservesProtocolError [
	"A JSON-RPC error response signals its code, message, and detached data."

	| errorData response captured |

	errorData := EsOrderedDictionary with: 'retryable' -> false.
	response := self jsonErrorResponseId: 8 code: -32602 message: 'Invalid params' data: errorData.
	httpClient enqueueResponse: response.
	captured := nil.
	[transport sendRequest: (self requestMethod: 'tools/call' id: 8) id: 8]
		on: McpJsonRpcError
		do: [:error |
			captured := error.
			error return].
	self assert: captured notNil.
	self assert: captured code equals: -32602.
	self assert: captured messageText equals: 'Invalid params'.
	self assert: (captured data at: 'retryable') equals: false
]

{ #category : 'Validation' }
TestMcpHttpClientTransport >> testMalformedJsonRpcResponsesAreRejected [
	"Response correlation and result/error exclusivity are mandatory."

	| wrongId ambiguous |

	wrongId := self jsonRpcResultId: 99 result: EsOrderedDictionary new.
	httpClient enqueueResponse:
		(self responseStatus: 200 contentType: 'application/json' jsonObject: wrongId).
	self should: [transport sendRequest: (self requestMethod: 'ping' id: 9) id: 9] raise: Error.
	ambiguous := self jsonRpcResultId: 10 result: EsOrderedDictionary new.
	ambiguous
		at: 'error'
		put: (
			EsOrderedDictionary new
				at: 'code' put: -32603;
				at: 'message' put: 'error';
				yourself).
	httpClient enqueueResponse:
		(self responseStatus: 200 contentType: 'application/json' jsonObject: ambiguous).
	self should: [transport sendRequest: (self requestMethod: 'ping' id: 10) id: 10] raise: Error
]

{ #category : 'Session Management' }
TestMcpHttpClientTransport >> testNonInitializationResponseCannotEstablishSession [
	"Only the response to initialize may establish transport session state."

	| response |

	response :=
		self
			jsonResultResponseId: 11
			result: EsOrderedDictionary new
			status: 200
			contentType: 'application/json'.
	response header at: 'MCP-Session-Id' put: 'unexpected-session'.
	httpClient enqueueResponse: response.
	transport sendRequest: (self requestMethod: 'ping' id: 11) id: 11.
	self assert: transport sessionID equals: nil
]

{ #category : 'Session Management' }
TestMcpHttpClientTransport >> testNonNotFoundErrorDoesNotRecoverSession [
	"Only HTTP 404 triggers stale-session recovery."

	self establishSession: 'retained-session' id: 48.
	httpClient enqueueResponse: (self responseStatus: 500 contentType: nil contents: #()).
	self should: [transport sendRequest: (self requestMethod: 'ping' id: 49) id: 49] raise: Error.
	self assert: httpClient posts size equals: 2.
	self assert: transport sessionID equals: 'retained-session'
]

{ #category : 'Session Management' }
TestMcpHttpClientTransport >> testNotFoundWithoutSessionIsNotRetried [
	"HTTP 404 without an active session is an immediate transport error."

	httpClient enqueueResponse: (self responseStatus: 404 contentType: nil contents: #()).
	self should: [transport sendRequest: (self requestMethod: 'ping' id: 47) id: 47] raise: Error.
	self assert: httpClient posts size equals: 1.
	self assert: transport sessionID equals: nil
]

{ #category : 'Protocol Operations' }
TestMcpHttpClientTransport >> testNotificationRequiresAcceptedStatus [
	"A notification succeeds only when the server answers HTTP 202."

	| notification post parsedNotification |

	notification :=
		EsOrderedDictionary new
			at: 'jsonrpc' put: '2.0';
			at: 'method' put: 'notifications/initialized';
			yourself.
	httpClient enqueueResponse: (self responseStatus: 202 contentType: nil contents: #()).
	self assert: (transport sendNotification: notification) == transport.
	post := httpClient posts first.
	parsedNotification := self jsonFromBytes: (post at: 'body').
	self assert: (parsedNotification at: 'method') equals: 'notifications/initialized'.
	httpClient enqueueResponse: (self responseStatus: 200 contentType: nil contents: #()).
	self should: [transport sendNotification: notification] raise: Error
]

{ #category : 'Validation' }
TestMcpHttpClientTransport >> testOversizedResponseIsRejected [
	"A buffered response cannot exceed the ten-megabyte safety limit."

	| bytes |

	bytes := ByteArray new: (10 * 1024 * 1024) + 1.
	httpClient
		enqueueResponse: (self responseStatus: 200 contentType: 'application/json' contents: bytes).
	self should: [transport sendRequest: (self requestMethod: 'ping' id: 63) id: 63] raise: Error
]

{ #category : 'Validation' }
TestMcpHttpClientTransport >> testRequestAndNotificationShapesAreValidated [
	"Outbound messages, identifiers, and endpoint state are validated."

	| request notification unconfigured |

	request := self requestMethod: 'ping' id: 64.
	notification :=
		EsOrderedDictionary new
			at: 'jsonrpc' put: '2.0';
			at: 'method' put: 'notifications/initialized';
			yourself.
	self should: [transport sendRequest: 'ping' id: 64] raise: Error.
	self should: [transport sendRequest: request id: nil] raise: Error.
	self should: [transport sendRequest: request id: true] raise: Error.
	self should: [transport sendNotification: 'notice'] raise: Error.
	self assert: httpClient posts isEmpty.
	unconfigured := McpInspectableHttpClientTransport new.
	self should: [unconfigured sendNotification: notification] raise: Error
]

{ #category : 'Copying' }
TestMcpHttpClientTransport >> testRequestScopedHeadersAreDetached [
	"A request snapshots scoped header names and values before sending."

	| source value sentHeaders |

	value := 'Bearer original' copy.
	source := EsOrderedDictionary with: 'Authorization' -> value.
	httpClient enqueueResponse: (
		self
			jsonResultResponseId: 65
			result: EsOrderedDictionary new
			status: 200
			contentType: 'application/json').
	transport sendRequest: (self requestMethod: 'ping' id: 65) id: 65 headers: source.
	value at: 8 put: $X.
	source at: 'Authorization' put: 'changed'.
	sentHeaders := httpClient posts first at: 'headers'.
	self assert: (self headerNamed: 'Authorization' in: sentHeaders) equals: 'Bearer original'
]

{ #category : 'Authentication' }
TestMcpHttpClientTransport >> testRequestScopedHeadersOverridePersistentHeaders [
	"Scoped credentials replace persistent values case-insensitively."

	| persistent scoped postHeaders |

	persistent := EsOrderedDictionary with: 'Authorization' -> 'Bearer old'.
	scoped := EsOrderedDictionary with: 'authorization' -> 'Bearer new'.
	transport additionalHeaders: persistent.
	httpClient enqueueResponse: (
		self
			jsonResultResponseId: 12
			result: EsOrderedDictionary new
			status: 200
			contentType: 'application/json').
	transport sendRequest: (self requestMethod: 'ping' id: 12) id: 12 headers: scoped.
	postHeaders := httpClient posts first at: 'headers'.
	self assert: (self headerNamed: 'Authorization' in: postHeaders) equals: 'Bearer new'.
	self assert: (self headerOccurrenceCount: 'Authorization' in: postHeaders) equals: 1
]

{ #category : 'Validation' }
TestMcpHttpClientTransport >> testRequestScopedHeadersRejectUnsafeFields [
	"Scoped headers enforce duplicate, line, and controlled-field rules."

	| request duplicates |

	request := self requestMethod: 'ping' id: 66.
	duplicates :=
		EsOrderedDictionary new
			at: 'X-Trace' put: 'one';
			at: 'x-trace' put: 'two';
			yourself.
	self should: [transport sendRequest: request id: 66 headers: duplicates] raise: Error.
	self
		should: [
			transport
				sendRequest: request
				id: 66
				headers: (EsOrderedDictionary with: 'Content-Type' -> 'text/plain')]
		raise: Error.
	self
		should: [
			transport
				sendRequest: request
				id: 66
				headers: (EsOrderedDictionary with: 'X-Unsafe' -> ('one' , self lf , 'two'))]
		raise: Error.
	self assert: httpClient posts isEmpty
]

{ #category : 'Session Management' }
TestMcpHttpClientTransport >> testSessionRecoveryAttemptsOnlyOnce [
	"A second 404 is reported instead of starting another handshake."

	| client |

	client := McpClient new.
	client transport: transport.
	self establishSession: 'first-session' id: 50.
	httpClient enqueueResponse: (self responseStatus: 404 contentType: nil contents: #()).
	httpClient enqueueResponse: (self initializeResponseId: 1 session: 'second-session').
	httpClient enqueueResponse: (self responseStatus: 202 contentType: nil contents: #()).
	httpClient enqueueResponse: (self responseStatus: 404 contentType: nil contents: #()).
	self should: [transport sendRequest: (self requestMethod: 'ping' id: 51) id: 51] raise: Error.
	self assert: httpClient posts size equals: 5
]

{ #category : 'Validation' }
TestMcpHttpClientTransport >> testSseResponseRejectsDuplicateCorrelatedResponses [
	"An SSE entity cannot contain two responses for one request ID."

	| sse |

	sse :=
		'data: {"jsonrpc":"2.0","id":14,"result":{}}' , self lf , self lf ,
			'data: {"jsonrpc":"2.0","id":14,"result":{}}' , self lf , self lf.
	httpClient enqueueResponse:
		(self responseStatus: 200 contentType: 'text/event-stream' contents: sse asUtf8Bytes).
	self should: [transport sendRequest: (self requestMethod: 'ping' id: 14) id: 14] raise: Error
]

{ #category : 'Validation' }
TestMcpHttpClientTransport >> testSseResponseRequiresCorrelatedResponse [
	"An SSE entity must eventually contain the requested response."

	| sse |

	sse := 'data: {"jsonrpc":"2.0","method":"notifications/progress"}' , self lf , self lf.
	httpClient enqueueResponse:
		(self responseStatus: 200 contentType: 'text/event-stream' contents: sse asUtf8Bytes).
	self should: [transport sendRequest: (self requestMethod: 'ping' id: 15) id: 15] raise: Error
]

{ #category : 'Protocol Operations' }
TestMcpHttpClientTransport >> testSseResponseRoutesNotificationAndReturnsCorrelatedResult [
	"SSE notifications are routed before the correlated response is returned."

	| client capturedParameters sse result |

	client := McpClient new.
	client transport: transport.
	client
		onNotification: 'notifications/resources/list_changed'
		do: [:parameters | capturedParameters := parameters].
	sse :=
		'id: prime' , self lf , 'data:' , self lf , self lf , 'data: {"jsonrpc":"2.0","method":' ,
			'"notifications/resources/list_changed","params":{"n":1}}' , self lf , self lf ,
			'data: {"jsonrpc":"2.0","id":13,"result":{"ok":true}}' , self lf , self lf.
	httpClient enqueueResponse: (
		self
			responseStatus: 200
			contentType: 'text/event-stream; charset=utf-8'
			contents: sse asUtf8Bytes).
	result := transport sendRequest: (self requestMethod: 'ping' id: 13) id: 13.
	self assert: (capturedParameters at: 'n') equals: 1.
	self assert: (result at: 'ok') equals: true
]

{ #category : 'Configuration' }
TestMcpHttpClientTransport >> testTimeoutChangeRebuildsConfiguredEndpoint [
	"Changing the timeout closes SST and rebuilds the configured endpoint."

	transport requestTimeout: 2500.
	self assert: transport requestTimeout equals: 2500.
	self assert: httpClient shutdownCount equals: 1.
	self assert: transport sessionID equals: nil
]

{ #category : 'Validation' }
TestMcpHttpClientTransport >> testUnsupportedOrMissingContentTypeIsRejected [
	"Request responses require JSON or event-stream Content-Type."

	| response |

	response := self responseStatus: 200 contentType: 'text/plain' contents: 'not MCP' asUtf8Bytes.
	httpClient enqueueResponse: response.
	self should: [transport sendRequest: (self requestMethod: 'ping' id: 16) id: 16] raise: Error.
	response := self responseStatus: 200 contentType: nil contents: #().
	httpClient enqueueResponse: response.
	self should: [transport sendRequest: (self requestMethod: 'ping' id: 17) id: 17] raise: Error
]
