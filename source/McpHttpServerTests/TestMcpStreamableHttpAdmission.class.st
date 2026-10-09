"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# TestMcpStreamableHttpAdmission

`TestMcpStreamableHttpAdmission` verifies Streamable HTTP request handling for
both modern sessionless and legacy sessionful exchanges.

## Responsibilities

- Verify Origin, media-type, size, and protocol-version boundaries.
- Verify sessionless modern POST dispatch without requiring `MCP-Session-Id`.
- Verify legacy initialization, session readiness, and session termination.
- Verify modern parameter header validation (`x-mcp-header` / `Mcp-Param-*`)
  and routing headers (`Mcp-Method`, `Mcp-Name`).
- Verify modern `subscriptions/listen` requires `Accept: text/event-stream`.
- Verify tool listing and invocation across the HTTP boundary.

## Test isolation

Tests use offline request fixtures with real protocol and tool collaborators.
They start no listener, open no sockets, create no background work, and share
no mutable state.
"
Class {
	#name : 'TestMcpStreamableHttpAdmission',
	#superclass : 'TestCase',
	#instVars : [
		'transport',
		'protocolServer'
	],
	#category : 'McpHttpServerTests'
}

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpStreamableHttpAdmission >> assertHttpJsonExchange: exchange id: expectedIdentifier [
	"Assert common HTTP and JSON-RPC response invariants."

	| request body response |

	request := exchange at: 'request'.
	body := exchange at: 'body'.
	response := exchange at: 'response'.
	self assert: request header responseHeader status equals: '200 OK'.
	self assert: request header responseHeader contentType equals: 'application/json'.
	self assert: request header responseHeader contentLength equals: body asUtf8Bytes size.
	self assert: response size equals: 3.
	self assert: (response at: 'jsonrpc') equals: '2.0'.
	self assert: (response at: 'id') equals: expectedIdentifier
]

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpStreamableHttpAdmission >> deleteRequestForSession: session [
	"Answer a DELETE request carrying one session and protocol version."

	^McpHttpServerTestRequest new
		headerAt: 'MCP-Session-Id' put: session id;
		headerAt: 'MCP-Protocol-Version' put: session protocolVersion;
		yourself
]

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpStreamableHttpAdmission >> initializeMessageId: identifier [
	"Answer one valid JSON-RPC initialize message."

	| parameters clientInfo capabilities |

	clientInfo :=
		EsOrderedDictionary new
			at: 'name' put: 'test-client';
			at: 'version' put: '1.0';
			yourself.
	capabilities := EsOrderedDictionary with: 'roots' -> EsOrderedDictionary new.
	parameters :=
		EsOrderedDictionary new
			at: 'protocolVersion' put: protocolServer supportedHandshakeProtocolVersions first;
			at: 'capabilities' put: capabilities;
			at: 'clientInfo' put: clientInfo;
			yourself.
	^EsOrderedDictionary new
		at: 'jsonrpc' put: '2.0';
		at: 'id' put: identifier;
		at: 'method' put: 'initialize';
		at: 'params' put: parameters;
		yourself
]

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpStreamableHttpAdmission >> jsonRpcMessageMethod: methodName id: identifier [
	"Answer a JSON-RPC request or notification message."

	| message |

	message :=
		EsOrderedDictionary new
			at: 'jsonrpc' put: '2.0';
			at: 'method' put: methodName;
			at: 'params' put: EsOrderedDictionary new;
			yourself.
	identifier ifNotNil: [message at: 'id' put: identifier].
	^message
]

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpStreamableHttpAdmission >> jsonStringFor: object [
	"Encode one JSON-compatible fixture."

	^String streamContents: [:stream | (McpJSONWriter on: stream) nextPut: object]
]

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpStreamableHttpAdmission >> performInitializationId: identifier [
	"Perform initialization and answer its request, body, ID, and session."

	| request body sessionId session |

	request := self requestForMessage: (self initializeMessageId: identifier).
	body := transport handlePostRequest: request.
	sessionId :=
		request header responseHeader
			at: 'MCP-Session-Id'
			ifAbsent: [self error: 'Initialization did not return a session ID'].
	session :=
		transport
			sessionNamed: sessionId
			ifAbsent: [self error: 'Initialization session was not retained'].
	^EsOrderedDictionary new
		at: 'request' put: request;
		at: 'body' put: body;
		at: 'sessionId' put: sessionId;
		at: 'session' put: session;
		yourself
]

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpStreamableHttpAdmission >> pingJsonId: identifier [
	"Answer one encoded JSON-RPC ping request."

	| request |

	request :=
		EsOrderedDictionary new
			at: 'jsonrpc' put: '2.0';
			at: 'id' put: identifier;
			at: 'method' put: 'ping';
			yourself.
	^String streamContents: [:stream | (McpJSONWriter on: stream) nextPut: request]
]

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpStreamableHttpAdmission >> readySessionId: identifier [
	"Initialize a session, send the required notification, and answer it."

	| exchange session notification request body |

	exchange := self performInitializationId: identifier.
	session := exchange at: 'session'.
	notification := self jsonRpcMessageMethod: 'notifications/initialized' id: nil.
	request := self requestForMessage: notification session: session.
	body := transport handlePostRequest: request.
	self assert: body equals: ''.
	self assert: request header responseHeader status equals: '202 Accepted'.
	self assert: request header responseHeader contentLength equals: 0.
	self assert: session isReady.
	^session
]

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpStreamableHttpAdmission >> requestForMessage: message [
	"Answer a valid POST request containing message."

	^self validRequestWithBody: (self jsonStringFor: message)
]

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpStreamableHttpAdmission >> requestForMessage: message session: session [
	"Answer a valid session POST request containing message."

	^(self requestForMessage: message)
		headerAt: 'MCP-Session-Id' put: session id;
		headerAt: 'MCP-Protocol-Version' put: session protocolVersion;
		yourself
]

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpStreamableHttpAdmission >> responseExchangeFor: message session: session [
	"Send one session message and answer request, body, and decoded response."

	| request body response |

	request := self requestForMessage: message session: session.
	body := transport handlePostRequest: request.
	response := McpJSONReader fromString: body.
	^EsOrderedDictionary new
		at: 'request' put: request;
		at: 'body' put: body;
		at: 'response' put: response;
		yourself
]

{ #category : 'Initialization' }
TestMcpStreamableHttpAdmission >> setUp [
	"Create an initialized transport with a real protocol dispatcher."

	| dispatcher |

	super setUp.
	protocolServer := McpServer new.
	dispatcher := McpJsonRpcDispatcher new.
	dispatcher server: protocolServer.
	transport := McpStreamableHttpTransport new.
	transport dispatcher: dispatcher
]

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpStreamableHttpAdmission >> strictEmptyObjectSchema [
	"Answer a schema accepting only an empty object."

	^EsOrderedDictionary new
		at: 'type' put: 'object';
		at: 'additionalProperties' put: false;
		yourself
]

{ #category : 'Authorization' }
TestMcpStreamableHttpAdmission >> testAllowedOriginProceedsToBodyParsing [
	"An explicitly allowed Origin passes the admission boundary."

	| request body |

	transport allowedOrigins: #('https://app.example').
	request := self validRequestWithBody: '{invalid'.
	request headerAt: 'Origin' put: 'HTTPS://APP.EXAMPLE'.
	body := transport handlePostRequest: request.
	self assert: request header responseHeader status equals: '400 Bad Request'.
	self assert: request header responseHeader contentType equals: 'application/json'.
	self deny: body isEmpty
]

{ #category : 'Validation' }
TestMcpStreamableHttpAdmission >> testContentTypeMustBeJson [
	"POST requires an application/json request media type."

	| missing unsupported |

	missing :=
		McpHttpServerTestRequest new
			headerAt: 'Accept' put: 'application/json, text/event-stream';
			contents: '{invalid' asUtf8Bytes;
			yourself.
	self assert: (transport handlePostRequest: missing) equals: ''.
	self assert: missing header responseHeader status equals: '400 Bad Request'.
	unsupported := self validRequestWithBody: '{invalid'.
	unsupported contentType: 'text/plain'.
	self assert: (transport handlePostRequest: unsupported) equals: ''.
	self assert: unsupported header responseHeader status equals: '400 Bad Request'
]

{ #category : 'Session Management' }
TestMcpStreamableHttpAdmission >> testDeleteRequiresKnownSession [
	"DELETE distinguishes a missing session from an unknown session."

	| missing unknown |

	missing := McpHttpServerTestRequest new.
	self assert: (transport handleDeleteRequest: missing) equals: ''.
	self assert: missing header responseHeader status equals: '400 Bad Request'.
	unknown := McpHttpServerTestRequest new.
	unknown headerAt: 'MCP-Session-Id' put: 'unknown-session'.
	self assert: (transport handleDeleteRequest: unknown) equals: ''.
	self assert: unknown header responseHeader status equals: '404 Not Found'
]

{ #category : 'Session Management' }
TestMcpStreamableHttpAdmission >> testDeleteTerminatesKnownSession [
	"DELETE removes a known session and a repeated DELETE reports 404."

	| exchange session request repeated |

	exchange := self performInitializationId: 80.
	session := exchange at: 'session'.
	request := self deleteRequestForSession: session.
	self assert: (transport handleDeleteRequest: request) equals: ''.
	self assert: request header responseHeader status equals: '204 No Content'.
	self assert: request header responseHeader contentLength equals: 0.
	self assert: (transport sessionNamed: session id ifAbsent: [nil]) equals: nil.
	repeated := self deleteRequestForSession: session.
	self assert: (transport handleDeleteRequest: repeated) equals: ''.
	self assert: repeated header responseHeader status equals: '404 Not Found'
]

{ #category : 'Testing' }
TestMcpStreamableHttpAdmission >> testExpiryFreesCapacityForNewInitialization [
	"Expiry returns capacity to the same admission path that enforces the cap."
	| now request |
	now := 1.
	transport sessionClock: [now]; sessionIdleTimeout: 10; maxSessions: 1.
	self readySessionId: 1.
	now := 11.
	request := self requestForMessage: (self initializeMessageId: 2).
	transport handlePostRequest: request.
	self assert: request header responseHeader status equals: '200 OK'.
	self assert: transport sessionCount equals: 1

]

{ #category : 'Testing' }
TestMcpStreamableHttpAdmission >> testFailedOpeningDeliveryDiscardsSession [
	"A socket-write failure after successful initialization frees the session."
	| exchange servlet writer connection |
	transport maxSessions: 1.
	exchange := self performInitializationId: 1.
	servlet := TestMcpDeliveryServlet new transport: transport; yourself.
	writer := servlet responseEntity: (exchange at: 'body')
		for: (exchange at: 'request').
	connection := TestMcpDeliveryConnection new
		writeAction: [:bytes | self error: 'Expected delivery failure'];
			yourself.
	self should: [writer value: connection] raise: Error.
	self assert: transport sessionCount equals: 0.
	self assert: (exchange at: 'session') activeRequestCount equals: 0.
	self readySessionId: 2.
	self assert: transport sessionCount equals: 1

]

{ #category : 'Testing' }
TestMcpStreamableHttpAdmission >> testFailedToolReleasesActiveRequestPin [
	"A tool error cannot retain an active request count forever."
	| now session request |
	now := 1.
	transport sessionClock: [now]; sessionIdleTimeout: 10.
	session := self readySessionId: 1.
	protocolServer toolRegistry registerTool:
		(self toolNamed: 'fail' block: [McpToolError signal:
			'Expected failure']).
	request := self requestForMessage:
		(self toolCallMessageNamed: 'fail' arguments: nil id: 2) session:
			session.
	transport handlePostRequest: request.
	self assert: session activeRequestCount equals: 0.
	now := 11.
	self assert: transport sessionCount equals: 0

]

{ #category : 'Protocol Operations' }
TestMcpStreamableHttpAdmission >> testGetIsRejectedWithAdvertisedMethods [
	"Standalone GET streams are unsupported and advertise POST and DELETE."

	| request result response |

	request := McpHttpServerTestRequest new.
	result := transport handleGetRequest: request.
	response := request header responseHeader.
	self assert: result equals: ''.
	self assert: response status equals: '405 Method Not Allowed'.
	self assert: response contentLength equals: 0.
	self assert: (response at: 'Allow' ifAbsent: [nil]) equals: 'POST, DELETE'
]

{ #category : 'Authorization' }
TestMcpStreamableHttpAdmission >> testGetRejectsDisallowedOriginBeforeMethodHandling [
	"Origin policy is enforced before unsupported-method formatting."

	| request response |

	request := McpHttpServerTestRequest new.
	request headerAt: 'Origin' put: 'https://denied.example'.
	self assert: (transport handleGetRequest: request) equals: ''.
	response := request header responseHeader.
	self assert: response status equals: '403 Forbidden'.
	self assert: (response at: 'Allow' ifAbsent: [nil]) equals: nil
]

{ #category : 'Testing' }
TestMcpStreamableHttpAdmission >> testHttpDeliveryRemainsPinnedUntilFlushed [
	"The idle timeout excludes actual HTTP entity delivery."
	| now exchange servlet writer connection |
	now := 1.
	transport sessionClock: [now]; sessionIdleTimeout: 10.
	exchange := self performInitializationId: 1.
	servlet := TestMcpDeliveryServlet new transport: transport; yourself.
	writer := servlet responseEntity: (exchange at: 'body')
		for: (exchange at: 'request').
	connection := TestMcpDeliveryConnection new writeAction: [:bytes |
		now := 1000.
		self assert: transport expireIdleSessions equals: 0.
		self assert: (exchange at: 'session') activeRequestCount equals: 1];
		yourself.
	writer value: connection.
	self assert: (exchange at: 'session') activeRequestCount equals: 0.
	now := 1010.
	self assert: transport sessionCount equals: 0

]

{ #category : 'Error Handling' }
TestMcpStreamableHttpAdmission >> testHttpInvalidToolArgumentsReturnProtocolError [
	"Invalid arguments return an error result without invoking the callback."

	| callbackRan properties schema tool session arguments message exchange response result content |

	callbackRan := false.
	properties := EsOrderedDictionary with: 'value' -> (EsOrderedDictionary with: 'type' -> 'string').
	schema :=
		EsOrderedDictionary new
			at: 'type' put: 'object';
			at: 'properties' put: properties;
			at: 'required' put: #('value');
			at: 'additionalProperties' put: false;
			yourself.
	tool :=
		McpBlockTool new
			name: 'required.value';
			inputSchema: schema;
			block: [:values |
				callbackRan := true.
				'unused'];
			yourself.
	protocolServer toolRegistry registerTool: tool.
	session := self readySessionId: 201.
	arguments := EsOrderedDictionary new.
	message := self toolCallMessageNamed: 'required.value' arguments: arguments id: 202.
	exchange := self responseExchangeFor: message session: session.
	response := exchange at: 'response'.
	self assertHttpJsonExchange: exchange id: 202.
	self deny: callbackRan.
	self deny: (response includesKey: 'error').
	result := response at: 'result'.
	content := result at: 'content'.
	self assert: (result at: 'isError') equals: true.
	self assert: content size equals: 1.
	self assert: (content first at: 'type') equals: 'text'.
	self assert: (content first at: 'text') isString.
	self deny: (content first at: 'text') isEmpty
]

{ #category : 'Validation' }
TestMcpStreamableHttpAdmission >> testHttpNonObjectJsonMessageReturnsInvalidRequest [
	"A valid JSON value that is not an object is an invalid request."

	| session request body response error constants |

	session := self readySessionId: 203.
	request := self validRequestWithBody: '[]'.
	request
		headerAt: 'MCP-Session-Id' put: session id;
		headerAt: 'MCP-Protocol-Version' put: session protocolVersion.
	body := transport handlePostRequest: request.
	response := McpJSONReader fromString: body.
	error := response at: 'error'.
	constants := Smalltalk at: #McpJsonRpcConstants.
	self assert: request header responseHeader status equals: '200 OK'.
	self assert: request header responseHeader contentType equals: 'application/json'.
	self assert: request header responseHeader contentLength equals: body asUtf8Bytes size.
	self assert: (response at: 'jsonrpc') equals: '2.0'.
	self assert: (response at: 'id') equals: nil.
	self deny: (response includesKey: 'result').
	self assert: (error at: 'code') equals: (constants at: 'McpJsonRpcInvalidRequestCode')
]

{ #category : 'Authentication' }
TestMcpStreamableHttpAdmission >> testHttpToolCallReceivesRequestContext [
	"A two-argument tool receives the authenticated session context."

	| context tool session message exchange response result content |

	transport requestContextFactory: [:request :incomingSession |
		McpServerRequestContext new
			principal: 'principal-42';
			metadata: (EsOrderedDictionary with: 'scope' -> 'tools:call');
			yourself].
	tool :=
		self
			toolNamed: 'context.identity'
			block: [:arguments :requestContext |
				context := requestContext.
				requestContext principal].
	protocolServer toolRegistry registerTool: tool.
	session := self readySessionId: 204.
	message :=
		self toolCallMessageNamed: 'context.identity' arguments: EsOrderedDictionary new id: 205.
	exchange := self responseExchangeFor: message session: session.
	response := exchange at: 'response'.
	self assertHttpJsonExchange: exchange id: 205.
	self deny: (response includesKey: 'error').
	result := response at: 'result'.
	content := result at: 'content'.
	self assert: (result at: 'isError') equals: false.
	self assert: (content first at: 'text') equals: 'principal-42'.
	self assert: context session == session.
	self assert: context sessionId equals: session id.
	self assert: context principal equals: 'principal-42'.
	self assert: (context metadata at: 'scope') equals: 'tools:call'
]

{ #category : 'Error Handling' }
TestMcpStreamableHttpAdmission >> testHttpToolExecutionFailureReturnsErrorResult [
	"A callback failure is an actionable tool result, not a protocol error."

	| tool session message exchange response result content |

	tool := self toolNamed: 'failing.tool' block: [self error: 'The upstream service is unavailable'].
	protocolServer toolRegistry registerTool: tool.
	session := self readySessionId: 206.
	message := self toolCallMessageNamed: 'failing.tool' arguments: EsOrderedDictionary new id: 207.
	exchange := self responseExchangeFor: message session: session.
	response := exchange at: 'response'.
	self assertHttpJsonExchange: exchange id: 207.
	self deny: (response includesKey: 'error').
	result := response at: 'result'.
	content := result at: 'content'.
	self assert: (result at: 'isError') equals: true.
	self assert: content size equals: 1.
	self assert: (content first at: 'type') equals: 'text'.
	self assert: (content first at: 'text') equals: 'The upstream service is unavailable'
]

{ #category : 'Protocol Operations' }
TestMcpStreamableHttpAdmission >> testHttpToolsCallReturnsSuccessfulContent [
	"A ready session executes a tool and returns correlated text content."

	| capturedArguments properties schema tool session arguments message exchange response result
	  content |

	properties :=
		EsOrderedDictionary with: 'message' -> (EsOrderedDictionary with: 'type' -> 'string').
	schema :=
		EsOrderedDictionary new
			at: 'type' put: 'object';
			at: 'properties' put: properties;
			at: 'required' put: #('message');
			at: 'additionalProperties' put: false;
			yourself.
	tool :=
		McpBlockTool new
			name: 'echo.message';
			inputSchema: schema;
			block: [:values |
				capturedArguments := values.
				values at: 'message'];
			yourself.
	protocolServer toolRegistry registerTool: tool.
	session := self readySessionId: 208.
	arguments := EsOrderedDictionary with: 'message' -> 'hello'.
	message := self toolCallMessageNamed: 'echo.message' arguments: arguments id: 209.
	exchange := self responseExchangeFor: message session: session.
	arguments at: 'message' put: 'changed'.
	response := exchange at: 'response'.
	self assertHttpJsonExchange: exchange id: 209.
	self deny: (response includesKey: 'error').
	self assert: (capturedArguments at: 'message') equals: 'hello'.
	result := response at: 'result'.
	content := result at: 'content'.
	self assert: (result at: 'isError') equals: false.
	self assert: content size equals: 1.
	self assert: (content first at: 'type') equals: 'text'.
	self assert: (content first at: 'text') equals: 'hello'
]

{ #category : 'Protocol Operations' }
TestMcpStreamableHttpAdmission >> testHttpToolsListReturnsRegisteredDefinitions [
	"Tool definitions traverse an initialized HTTP session intact."

	| firstTool secondTool session message exchange response result tools names |

	firstTool := self toolNamed: 'zeta.tool' block: ['zeta'].
	firstTool description: 'The later tool'.
	secondTool := self toolNamed: 'alpha.tool' block: ['alpha'].
	secondTool description: 'The earlier tool'.
	protocolServer toolRegistry
		registerTool: firstTool;
		registerTool: secondTool.
	session := self readySessionId: 210.
	message := self jsonRpcMessageMethod: 'tools/list' id: 211.
	exchange := self responseExchangeFor: message session: session.
	response := exchange at: 'response'.
	self assertHttpJsonExchange: exchange id: 211.
	self deny: (response includesKey: 'error').
	result := response at: 'result'.
	tools := result at: 'tools'.
	self assert: tools size equals: 2.
	names := Set new.
	tools do: [:definition |
		names add: (definition at: 'name').
		self assert: (definition at: 'inputSchema') isCollection.
		self assert: ((definition at: 'inputSchema') at: 'type') equals: 'object'].
	self assert: (names includes: 'zeta.tool').
	self assert: (names includes: 'alpha.tool').
	self deny: (result includesKey: 'nextCursor')
]

{ #category : 'Error Handling' }
TestMcpStreamableHttpAdmission >> testHttpUnknownToolReturnsCorrelatedProtocolError [
	"An unknown tool returns invalid params with the original request ID."

	| session message exchange response error constants |

	session := self readySessionId: 212.
	message := self toolCallMessageNamed: 'missing.tool' arguments: EsOrderedDictionary new id: 213.
	exchange := self responseExchangeFor: message session: session.
	response := exchange at: 'response'.
	error := response at: 'error'.
	constants := Smalltalk at: #McpJsonRpcConstants.
	self assertHttpJsonExchange: exchange id: 213.
	self deny: (response includesKey: 'result').
	self assert: (error at: 'code') equals: (constants at: 'McpJsonRpcInvalidParamsCode').
	self assert: (error at: 'message') equals: 'Unknown tool: missing.tool'
]

{ #category : 'Testing' }
TestMcpStreamableHttpAdmission >> testIdleAndCapacityLimitsCanBeDisabled [
	"Nil disables each limit independently."
	| now |
	now := 1.
	transport sessionClock: [now]; maxSessions: nil; sessionIdleTimeout: nil.
	self readySessionId: 1.
	now := 1000000.
	self readySessionId: 2.
	self assert: transport sessionCount equals: 2

]

{ #category : 'Testing' }
TestMcpStreamableHttpAdmission >> testIdleSessionExpiresAtBoundary [
	"An idle legacy session becomes unknown at the configured timeout."
	| now session request |
	now := 100.
	transport sessionClock: [now]; sessionIdleTimeout: 10.
	session := self readySessionId: 1.
	now := 109.
	self assert: transport sessionCount equals: 1.
	now := 110.
	request := self requestForMessage:
		(self jsonRpcMessageMethod: 'ping' id: 2) session: session.
	transport handlePostRequest: request.
	self assert: request header responseHeader status equals: '404 Not Found'.
	self assert: transport sessionCount equals: 0

]

{ #category : 'Validation' }
TestMcpStreamableHttpAdmission >> testInitializationErrorDoesNotCreateSession [
	"An invalid initialize message returns an error without a session."

	| message request body response error constants |

	message := self initializeMessageId: 81.
	(message at: 'params') removeKey: 'clientInfo'.
	request := self requestForMessage: message.
	body := transport handlePostRequest: request.
	response := McpJSONReader fromString: body.
	error := response at: 'error'.
	constants := Smalltalk at: #McpJsonRpcConstants.
	self assert: request header responseHeader status equals: '200 OK'.
	self assert: (request header responseHeader at: 'MCP-Session-Id' ifAbsent: [nil]) equals: nil.
	self assert: (error at: 'code') equals: (constants at: 'McpJsonRpcInvalidParamsCode')
]

{ #category : 'Validation' }
TestMcpStreamableHttpAdmission >> testInitializationNotificationIsRejected [
	"Initialize must be a request carrying a JSON-RPC identifier."

	| message request |

	message := self initializeMessageId: 82.
	message removeKey: 'id'.
	request := self requestForMessage: message.
	self assert: (transport handlePostRequest: request) equals: ''.
	self assert: request header responseHeader status equals: '400 Bad Request'.
	self assert: request header responseHeader contentLength equals: 0
]

{ #category : 'Validation' }
TestMcpStreamableHttpAdmission >> testInitializationRejectsExistingSessionHeader [
	"A new initialization exchange cannot carry an existing session ID."

	| request |

	request := self requestForMessage: (self initializeMessageId: 83).
	request headerAt: 'MCP-Session-Id' put: 'existing-session'.
	self assert: (transport handlePostRequest: request) equals: ''.
	self assert: request header responseHeader status equals: '400 Bad Request'
]

{ #category : 'Session Management' }
TestMcpStreamableHttpAdmission >> testInitializedNotificationTransitionsSessionToReady [
	"The required notification atomically completes session initialization."

	| exchange session notification request |

	exchange := self performInitializationId: 84.
	session := exchange at: 'session'.
	notification := self jsonRpcMessageMethod: 'notifications/initialized' id: nil.
	request := self requestForMessage: notification session: session.
	self assert: (transport handlePostRequest: request) equals: ''.
	self assert: request header responseHeader status equals: '202 Accepted'.
	self assert: request header responseHeader contentLength equals: 0.
	self assert: session isReady
]

{ #category : 'Validation' }
TestMcpStreamableHttpAdmission >> testInitializedRequestWithIdentifierIsRejected [
	"The initialized signal must be a notification, not a request."

	| exchange session message request |

	exchange := self performInitializationId: 85.
	session := exchange at: 'session'.
	message := self jsonRpcMessageMethod: 'notifications/initialized' id: 86.
	request := self requestForMessage: message session: session.
	self assert: (transport handlePostRequest: request) equals: ''.
	self assert: request header responseHeader status equals: '400 Bad Request'.
	self assert: session isInitializing
]

{ #category : 'Testing' }
TestMcpStreamableHttpAdmission >> testInvalidOpeningDoesNotConsumeCapacity [
	"An initialization protocol error releases its reserved slot."
	| message request |
	transport maxSessions: 1.
	message := self initializeMessageId: 1.
	(message at: 'params') removeKey: 'clientInfo'.
	request := self requestForMessage: message.
	transport handlePostRequest: request.
	self assert: transport sessionCount equals: 0.
	self readySessionId: 2.
	self assert: transport sessionCount equals: 1

]

{ #category : 'Testing' }
TestMcpStreamableHttpAdmission >> testInvalidSessionLimitsRejected [
	"Reject invalid limits before changing the active policy."
	self should: [transport maxSessions: 0] raise: Error.
	self should: [transport maxSessions: 1.5] raise: Error.
	self should: [transport sessionIdleTimeout: 0] raise: Error.
	self should: [transport sessionIdleTimeout: -1] raise: Error.
	self should: [transport sessionIdleTimeout: '10'] raise: Error.
	self assert: transport maxSessions equals: 10000.
	self assert: transport sessionIdleTimeout equals: 1800

]

{ #category : 'Validation' }
TestMcpStreamableHttpAdmission >> testJsonContentTypeAllowsCaseAndParameters [
	"JSON media-type matching ignores case and optional parameters."

	| request body |

	request := self validRequestWithBody: '{invalid'.
	request contentType: 'Application/JSON; charset=utf-8'.
	body := transport handlePostRequest: request.
	self assert: request header responseHeader status equals: '400 Bad Request'.
	self assert: request header responseHeader contentType equals: 'application/json'.
	self deny: body isEmpty
]

{ #category : 'Parsing' }
TestMcpStreamableHttpAdmission >> testMalformedJsonReturnsCanonicalParseError [
	"Malformed JSON produces the canonical JSON-RPC parse error."

	| request body parsed error constants |

	request := self validRequestWithBody: '{broken'.
	body := transport handlePostRequest: request.
	parsed := McpJSONReader fromString: body.
	error := parsed at: 'error'.
	constants := Smalltalk at: #McpJsonRpcConstants.
	self assert: (parsed at: 'jsonrpc') equals: '2.0'.
	self assert: (parsed at: 'id') equals: nil.
	self assert: (error at: 'code') equals: (constants at: 'McpJsonRpcParseErrorCode').
	self assert: (error at: 'message') equals: 'Parse error'.
	self assert: request header responseHeader status equals: '400 Bad Request'.
	self assert: request header responseHeader contentLength equals: body asUtf8Bytes size
]

{ #category : 'Validation' }
TestMcpStreamableHttpAdmission >> testMissingOrPartialAcceptIsRejected [
	"POST Accept must advertise JSON and Server-Sent Events."

	| missing jsonOnly eventOnly requests |

	missing :=
		McpHttpServerTestRequest new
			contentType: 'application/json';
			contents: '{invalid' asUtf8Bytes;
			yourself.
	jsonOnly :=
		McpHttpServerTestRequest new
			headerAt: 'Accept' put: 'application/json';
			contentType: 'application/json';
			contents: '{invalid' asUtf8Bytes;
			yourself.
	eventOnly :=
		McpHttpServerTestRequest new
			headerAt: 'Accept' put: 'text/event-stream';
			contentType: 'application/json';
			contents: '{invalid' asUtf8Bytes;
			yourself.
	requests :=
		OrderedCollection new
			add: missing;
			add: jsonOnly;
			add: eventOnly;
			yourself.
	requests do: [:request |
		self assert: (transport handlePostRequest: request) equals: ''.
		self assert: request header responseHeader status equals: '400 Bad Request']
]

{ #category : 'Validation' }
TestMcpStreamableHttpAdmission >> testModernMismatchedMethodHeaderReturnsHeaderMismatch [
	"A modern request whose Mcp-Method header disagrees with the body is rejected with -32020."

	| message request response body |

	message := self jsonRpcMessageMethod: 'tools/list' id: 105.
	request :=
		(self requestForMessage: message)
			headerAt: 'MCP-Protocol-Version' put: '2026-07-28';
			headerAt: 'Mcp-Method' put: 'prompts/list';
			yourself.
	response := transport handlePostRequest: request.
	self assert: request header responseHeader status equals: '400 Bad Request'.
	body := (McpJSONReader on: response readStream) next.
	self assert: ((body at: 'error') at: 'code') equals: -32020
]

{ #category : 'Validation' }
TestMcpStreamableHttpAdmission >> testModernMismatchedProtocolVersionHeaderReturnsHeaderMismatch [
	"A modern request whose MCP-Protocol-Version header disagrees with the body's _meta protocolVersion is rejected with -32020."

	| message request response body params |

	message := self jsonRpcMessageMethod: 'tools/list' id: 107.
	params := message at: 'params' ifAbsentPut: [EsOrderedDictionary new].
	params
		at: '_meta'
		put: (
			EsOrderedDictionary new
				at: 'io.modelcontextprotocol/protocolVersion' put: '2025-11-25';
				at: 'io.modelcontextprotocol/clientCapabilities' put: EsOrderedDictionary new;
				yourself).
	request :=
		(self requestForMessage: message)
			headerAt: 'MCP-Protocol-Version' put: '2026-07-28';
			headerAt: 'Mcp-Method' put: 'tools/list';
			yourself.
	response := transport handlePostRequest: request.

	self assert: request header responseHeader status equals: '400 Bad Request'.
	body := McpJSONReader fromString: response.
	self assert: ((body at: 'error') at: 'code') equals: -32020
]

{ #category : 'Protocol Operations' }
TestMcpStreamableHttpAdmission >> testModernNotificationPostReturnsAccepted202 [
	"In protocol 2026-07-28, a notification POST returns 202 Accepted."

	| message request response |

	message :=
		EsOrderedDictionary new
			at: 'jsonrpc' put: '2.0';
			at: 'method' put: 'notifications/custom';
			at: 'params' put: EsOrderedDictionary new;
			yourself.
	request :=
		(self requestForMessage: message)
			headerAt: 'MCP-Protocol-Version' put: '2026-07-28';
			yourself.
	response := transport handlePostRequest: request.
	self assert: request header responseHeader status equals: '202 Accepted'.
	self assert: response equals: ''
]

{ #category : 'Validation' }
TestMcpStreamableHttpAdmission >> testModernPostAcceptsJsonWithoutEventStream [
	"In protocol 2026-07-28, Accept: application/json alone is accepted."

	| message request response body |

	message := self jsonRpcMessageMethod: 'server/discover' id: 102.
	(message at: 'params')
		at: '_meta'
		put: (
			EsOrderedDictionary new
				at: 'io.modelcontextprotocol/protocolVersion' put: '2026-07-28';
				at: 'io.modelcontextprotocol/clientCapabilities' put: EsOrderedDictionary new;
				yourself).
	request :=
		(self requestForMessage: message)
			headerAt: 'MCP-Protocol-Version' put: '2026-07-28';
			headerAt: 'Mcp-Method' put: 'server/discover';
			headerAt: 'Accept' put: 'application/json';
			yourself.
	response := transport handlePostRequest: request.
	self assert: request header responseHeader status equals: '200 OK'.
	body := (McpJSONReader on: response readStream) next.
	self assert: (body at: 'id') equals: 102
]

{ #category : 'Validation' }
TestMcpStreamableHttpAdmission >> testModernRequestMissingMcpMethodHeaderIsRejectedWithHeaderMismatch [
	"A modern request missing the required Mcp-Method header is rejected with HTTP 400 and -32020 HeaderMismatch."

	| message request response body params |

	message := self jsonRpcMessageMethod: 'tools/list' id: 106.
	params := message at: 'params' ifAbsentPut: [EsOrderedDictionary new].
	params
		at: '_meta'
		put: (
			EsOrderedDictionary new
				at: 'io.modelcontextprotocol/protocolVersion' put: '2026-07-28';
				at: 'io.modelcontextprotocol/clientCapabilities' put: EsOrderedDictionary new;
				yourself).
	request :=
		(self requestForMessage: message)
			headerAt: 'MCP-Protocol-Version' put: '2026-07-28';
			yourself.
	"Mcp-Method header is intentionally omitted"
	response := transport handlePostRequest: request.

	self assert: request header responseHeader status equals: '400 Bad Request'.
	body := McpJSONReader fromString: response.
	self assert: ((body at: 'error') at: 'code') equals: -32020
]

{ #category : 'Validation' }
TestMcpStreamableHttpAdmission >> testModernRequestMissingRequiredMetaFieldsIsRejectedWithInvalidParams [
	"A modern request missing required _meta fields (clientCapabilities) is rejected with code -32602 per MCP 2026-07-28."

	| message request response body params |

	message := self jsonRpcMessageMethod: 'tools/list' id: 108.
	params := message at: 'params' ifAbsentPut: [EsOrderedDictionary new].
	params
		at: '_meta'
		put: (
			EsOrderedDictionary new
				at: 'io.modelcontextprotocol/protocolVersion' put: '2026-07-28';
				yourself).
	request :=
		(self requestForMessage: message)
			headerAt: 'MCP-Protocol-Version' put: '2026-07-28';
			headerAt: 'Mcp-Method' put: 'tools/list';
			yourself.
	response := transport handlePostRequest: request.

	self assert: request header responseHeader status equals: '400 Bad Request'.
	body := McpJSONReader fromString: response.
	self assert: ((body at: 'error') at: 'code') equals: -32602
]

{ #category : 'Testing' }
TestMcpStreamableHttpAdmission >> testModernRequestsIgnoreLegacyCapacity [
	"The 2026 protocol remains sessionless when legacy capacity is exhausted."

	| request message params |

	transport maxSessions: 1.
	self readySessionId: 1.
	message := self jsonRpcMessageMethod: 'server/discover' id: 2.
	params := message at: 'params' ifAbsentPut: [EsOrderedDictionary new].
	params
		at: '_meta'
		put: (
			EsOrderedDictionary new
				at: 'io.modelcontextprotocol/protocolVersion' put: '2026-07-28';
				at: 'io.modelcontextprotocol/clientCapabilities' put: EsOrderedDictionary new;
				yourself).
	request := self requestForMessage: message.
	request
		headerAt: 'MCP-Protocol-Version' put: '2026-07-28';
		headerAt: 'Mcp-Method' put: 'server/discover'.
	transport handlePostRequest: request.
	self assert: request header responseHeader status equals: '200 OK'.
	self assert: transport sessionCount equals: 1
]

{ #category : 'Protocol Operations' }
TestMcpStreamableHttpAdmission >> testModernSessionlessPostDoesNotRequireSessionId [
	"In protocol 2026-07-28, POST requests are sessionless and do not require MCP-Session-Id."

	| message request response body |

	message := self jsonRpcMessageMethod: 'server/discover' id: 101.
	(message at: 'params')
		at: '_meta'
		put: (
			EsOrderedDictionary new
				at: 'io.modelcontextprotocol/protocolVersion' put: '2026-07-28';
				at: 'io.modelcontextprotocol/clientCapabilities' put: EsOrderedDictionary new;
				yourself).
	request :=
		(self requestForMessage: message)
			headerAt: 'MCP-Protocol-Version' put: '2026-07-28';
			headerAt: 'Mcp-Method' put: 'server/discover';
			yourself.
	response := transport handlePostRequest: request.
	self assert: request header responseHeader status equals: '200 OK'.
	body := (McpJSONReader on: response readStream) next.
	self assert: (body at: 'id') equals: 101.
	self assert: ((body at: 'result') at: 'resultType') equals: 'complete'
]

{ #category : 'Validation' }
TestMcpStreamableHttpAdmission >> testModernToolCallMissingMcpNameHeaderIsRejectedWithHeaderMismatch [
	"A modern tools/call request missing the required Mcp-Name header is rejected with HTTP 400 and -32020 HeaderMismatch."

	| testTool message request response body params |

	testTool := self toolNamed: 'echo.tool' block: ['echoed'].
	protocolServer toolRegistry registerTool: testTool.

	message := self toolCallMessageNamed: 'echo.tool' arguments: EsOrderedDictionary new id: 302.
	params := message at: 'params' ifAbsentPut: [EsOrderedDictionary new].
	params
		at: '_meta'
		put: (
			EsOrderedDictionary new
				at: 'io.modelcontextprotocol/protocolVersion' put: '2026-07-28';
				at: 'io.modelcontextprotocol/clientCapabilities' put: EsOrderedDictionary new;
				yourself).
	request :=
		(self requestForMessage: message)
			headerAt: 'MCP-Protocol-Version' put: '2026-07-28';
			headerAt: 'Mcp-Method' put: 'tools/call';
			yourself.
	"Mcp-Name header is intentionally omitted"
	response := transport handlePostRequest: request.

	self assert: request header responseHeader status equals: '400 Bad Request'.
	body := McpJSONReader fromString: response.
	self assert: ((body at: 'error') at: 'code') equals: -32020
]

{ #category : 'Validation' }
TestMcpStreamableHttpAdmission >> testModernToolCallRejectsMismatchedMcpParamHeader [
	"A modern tools/call whose Mcp-Param-* header disagrees with the argument is rejected with -32020."

	| tool schema message request response body |

	schema :=
		EsOrderedDictionary new
			at: 'type' put: 'object';
			at: 'properties'
				put: (
					EsOrderedDictionary with:
						'region' -> (
							EsOrderedDictionary new
								at: 'type' put: 'string';
								at: 'x-mcp-header' put: 'Region';
								yourself));
			yourself.
	tool :=
		McpBlockTool new
			name: 'cloud.deploy2';
			inputSchema: schema;
			block: [:arguments | 'Deployed'];
			yourself.
	protocolServer toolRegistry registerTool: tool.

	message :=
		self
			toolCallMessageNamed: 'cloud.deploy2'
			arguments: (EsOrderedDictionary with: 'region' -> 'us-west1')
			id: 107.
	request :=
		(self requestForMessage: message)
			headerAt: 'MCP-Protocol-Version' put: '2026-07-28';
			headerAt: 'Mcp-Param-Region' put: 'eu-central1';
			yourself.
	response := transport handlePostRequest: request.
	self assert: request header responseHeader status equals: '400 Bad Request'.
	body := (McpJSONReader on: response readStream) next.
	self assert: ((body at: 'error') at: 'code') equals: -32020
]

{ #category : 'Protocol Operations' }
TestMcpStreamableHttpAdmission >> testModernToolCallValidatesMatchingMcpParamHeader [
	"A modern tools/call with matching Mcp-Param-* header dispatches successfully."

	| tool schema message request response body params |

	schema :=
		EsOrderedDictionary new
			at: 'type' put: 'object';
			at: 'properties'
				put: (
					EsOrderedDictionary with:
						'region' -> (
							EsOrderedDictionary new
								at: 'type' put: 'string';
								at: 'x-mcp-header' put: 'Region';
								yourself));
			yourself.
	tool :=
		McpBlockTool new
			name: 'cloud.deploy';
			inputSchema: schema;
			block: [:arguments | 'Deployed to ' , (arguments at: 'region')];
			yourself.
	protocolServer toolRegistry registerTool: tool.

	message :=
		self
			toolCallMessageNamed: 'cloud.deploy'
			arguments: (EsOrderedDictionary with: 'region' -> 'us-west1')
			id: 106.
	params := message at: 'params'.
	params
		at: '_meta'
		put: (
			EsOrderedDictionary new
				at: 'io.modelcontextprotocol/protocolVersion' put: '2026-07-28';
				at: 'io.modelcontextprotocol/clientCapabilities' put: EsOrderedDictionary new;
				yourself).
	request :=
		(self requestForMessage: message)
			headerAt: 'MCP-Protocol-Version' put: '2026-07-28';
			headerAt: 'Mcp-Method' put: 'tools/call';
			headerAt: 'Mcp-Name' put: 'cloud.deploy';
			headerAt: 'Mcp-Param-Region' put: 'us-west1';
			yourself.
	response := transport handlePostRequest: request.
	self assert: request header responseHeader status equals: '200 OK'.
	body := (McpJSONReader on: response readStream) next.
	self assert: (body at: 'id') equals: 106.
	self
		assert: (((body at: 'result') at: 'content') first at: 'text')
		equals: 'Deployed to us-west1'
]

{ #category : 'Protocol Operations' }
TestMcpStreamableHttpAdmission >> testModernToolCallWithProgressStreamsSse [
	"A modern tools/call with progressToken and text/event-stream Accept header switches to streaming."

	| tool message request response meta |

	tool :=
		McpBlockTool new
			name: 'heavy.work';
			inputSchema: (EsOrderedDictionary with: 'type' -> 'object');
			block: [:arguments :ctx |
				ctx ifNotNil: [ctx reportProgress: 50 total: 100 message: 'Halfway'].
				'Done'];
			yourself.
	protocolServer toolRegistry registerTool: tool.

	message :=
		self
			toolCallMessageNamed: 'heavy.work'
			arguments: EsOrderedDictionary new
			id: 301.
	meta :=
		EsOrderedDictionary new
			at: 'progressToken' put: 'prog-1';
			at: 'io.modelcontextprotocol/protocolVersion' put: '2026-07-28';
			at: 'io.modelcontextprotocol/clientCapabilities' put: EsOrderedDictionary new;
			yourself.
	(message at: 'params') at: '_meta' put: meta.

	request :=
		(self requestForMessage: message)
			headerAt: 'MCP-Protocol-Version' put: '2026-07-28';
			headerAt: 'Mcp-Method' put: 'tools/call';
			headerAt: 'Mcp-Name' put: 'heavy.work';
			headerAt: 'Accept' put: 'application/json, text/event-stream';
			yourself.
	response := transport handlePostRequest: request.
	self assert: request header responseHeader status equals: '200 OK'.
	self assert: (
		(request header responseHeader contentType
			indexOfSubCollection: 'text/event-stream'
			startingAt: 1) > 0).
	self assert: response isBlock
]

{ #category : 'Protocol Operations' }
TestMcpStreamableHttpAdmission >> testMultipleConcurrentPostRequestsOnSameSession [
	"Multiple concurrent POST requests within the same session dispatch successfully."

	| exchange session tool req1 req2 req3 resp1 resp2 resp3 |

	tool :=
		self
			toolNamed: 'echo.tool'
			block: [:args | 'echoed'].
	protocolServer toolRegistry registerTool: tool.

	exchange := self performInitializationId: 120.
	session := exchange at: 'session'.
	session markReady.

	req1 :=
		(self
			requestForMessage: (
				self
					toolCallMessageNamed: 'echo.tool'
					arguments: EsOrderedDictionary new
					id: 121)
			session: session)
				headerAt: 'mcp-protocol-version' put: '2025-11-25';
				yourself.
	req2 :=
		(self
			requestForMessage: (
				self
					toolCallMessageNamed: 'echo.tool'
					arguments: EsOrderedDictionary new
					id: 122)
			session: session)
				headerAt: 'mcp-protocol-version' put: '2025-11-25';
				yourself.
	req3 :=
		(self
			requestForMessage: (
				self
					toolCallMessageNamed: 'echo.tool'
					arguments: EsOrderedDictionary new
					id: 123)
			session: session)
				headerAt: 'mcp-protocol-version' put: '2025-11-25';
				yourself.

	resp1 := transport handlePostRequest: req1.
	resp2 := transport handlePostRequest: req2.
	resp3 := transport handlePostRequest: req3.

	self assert: req1 header responseHeader status equals: '200 OK'.
	self assert: req2 header responseHeader status equals: '200 OK'.
	self assert: req3 header responseHeader status equals: '200 OK'.

	self assert: ((McpJSONReader on: resp1 readStream) next at: 'id') equals: 121.
	self assert: ((McpJSONReader on: resp2 readStream) next at: 'id') equals: 122.
	self assert: ((McpJSONReader on: resp3 readStream) next at: 'id') equals: 123
]

{ #category : 'Validation' }
TestMcpStreamableHttpAdmission >> testNumericMcpParamHeaderComparison [
	"A modern request whose integer parameter header matches numerically (e.g. 42 vs 42.0) succeeds."

	| numTool schema message request response body params |

	schema :=
		EsOrderedDictionary new
			at: 'type' put: 'object';
			at: 'properties'
				put: (
					EsOrderedDictionary with:
						'count' -> (
							EsOrderedDictionary new
								at: 'type' put: 'integer';
								at: 'x-mcp-header' put: 'Count';
								yourself));
			yourself.
	numTool :=
		McpBlockTool new
			name: 'calc.scale';
			inputSchema: schema;
			block: [:arguments | (arguments at: 'count') * 2];
			yourself.
	protocolServer toolRegistry registerTool: numTool.

	message :=
		self
			toolCallMessageNamed: 'calc.scale'
			arguments: (EsOrderedDictionary with: 'count' -> 42)
			id: 303.
	params := message at: 'params'.
	params
		at: '_meta'
		put: (
			EsOrderedDictionary new
				at: 'io.modelcontextprotocol/protocolVersion' put: '2026-07-28';
				at: 'io.modelcontextprotocol/clientCapabilities' put: EsOrderedDictionary new;
				yourself).

	request :=
		(self requestForMessage: message)
			headerAt: 'MCP-Protocol-Version' put: '2026-07-28';
			headerAt: 'Mcp-Method' put: 'tools/call';
			headerAt: 'Mcp-Name' put: 'calc.scale';
			headerAt: 'Mcp-Param-Count' put: '42';
			yourself.
	response := transport handlePostRequest: request.
	self assert: request header responseHeader status equals: '200 OK'.
	body := (McpJSONReader on: response readStream) next.
	self assert: (body at: 'id') equals: 303
]

{ #category : 'Authorization' }
TestMcpStreamableHttpAdmission >> testOriginHeaderIsDeniedByDefault [
	"An Origin header is forbidden when no origin is explicitly allowed."

	| request |

	request := self validRequestWithBody: '{invalid'.
	request headerAt: 'Origin' put: 'https://app.example'.
	self assert: (transport handlePostRequest: request) equals: ''.
	self assert: request header responseHeader status equals: '403 Forbidden'.
	self assert: request header responseHeader contentLength equals: 0
]

{ #category : 'Validation' }
TestMcpStreamableHttpAdmission >> testOversizedBodyIsRejectedBeforeParsing [
	"The byte limit is enforced before UTF-8 decoding or JSON parsing."

	| request |

	transport maximumRequestSize: 4.
	request :=
		McpHttpServerTestRequest new
			headerAt: 'Accept' put: 'application/json, text/event-stream';
			contentType: 'application/json';
			contents: #[1 2 3 4 5];
			yourself.
	self assert: (transport handlePostRequest: request) equals: ''.
	self assert: request header responseHeader status equals: '413 Payload Too Large'.
	self assert: request header responseHeader contentLength equals: 0
]

{ #category : 'Session Management' }
TestMcpStreamableHttpAdmission >> testPingIsAllowedWhileSessionIsInitializing [
	"Ping remains available before the initialized notification."

	| exchange session request body response |

	exchange := self performInitializationId: 87.
	session := exchange at: 'session'.
	request := self requestForMessage: (self jsonRpcMessageMethod: 'ping' id: 88) session: session.
	body := transport handlePostRequest: request.
	response := McpJSONReader fromString: body.
	self assert: request header responseHeader status equals: '200 OK'.
	self assert: (response at: 'id') equals: 88.
	self assert: (response at: 'result') isEmpty.
	self assert: session isInitializing
]

{ #category : 'Validation' }
TestMcpStreamableHttpAdmission >> testPostWithMissingProtocolVersionUsesCompatibilityVersion [
	"A missing version falls back to March 2025 and is rejected if unsupported."

	| request |

	request := self validRequestWithBody: (self pingJsonId: 70).
	self assert: (transport handlePostRequest: request) equals: ''.
	self assert: request header responseHeader status equals: '400 Bad Request'
]

{ #category : 'Validation' }
TestMcpStreamableHttpAdmission >> testPostWithUnsupportedProtocolVersionIsRejected [
	"A non-initialize POST rejects an unsupported protocol version with HTTP 400 and error -32022."

	| request response body |

	request := self validRequestWithBody: (self pingJsonId: 71).
	request headerAt: 'MCP-Protocol-Version' put: '2099-01-01'.
	response := transport handlePostRequest: request.
	self assert: request header responseHeader status equals: '400 Bad Request'.
	self assert: request header responseHeader contentType equals: 'application/json'.
	body := McpJSONReader fromString: response.
	self assert: ((body at: 'error') at: 'code') equals: -32022
]

{ #category : 'Validation' }
TestMcpStreamableHttpAdmission >> testPostWithUnsupportedProtocolVersionReturnsSpecCompliantError [
	"A request proposing an unsupported protocol version MUST return HTTP 400 with JSON-RPC error -32022 per MCP 2026-07-28."

	| message request response body error data |

	message :=
		EsOrderedDictionary new
			at: 'jsonrpc' put: '2.0';
			at: 'id' put: 72;
			at: 'method' put: 'tools/list';
			at: 'params'
				put: (
					EsOrderedDictionary with:
						'_meta' ->
							(EsOrderedDictionary with:
								'io.modelcontextprotocol/protocolVersion' -> '1999-01-01'));
			yourself.
	request :=
		(self requestForMessage: message)
			headerAt: 'MCP-Protocol-Version' put: '1999-01-01';
			headerAt: 'Mcp-Method' put: 'tools/list';
			yourself.
	response := transport handlePostRequest: request.

	self assert: request header responseHeader status equals: '400 Bad Request'.
	self assert: request header responseHeader contentType equals: 'application/json'.
	body := McpJSONReader fromString: response.
	self assert: (body at: 'jsonrpc') equals: '2.0'.
	self assert: (body at: 'id') equals: 72.
	error := body at: 'error'.
	self assert: (error at: 'code') equals: -32022.
	self assert: (error at: 'message') equals: 'Unsupported protocol version'.
	data := error at: 'data'.
	self assert: (data at: 'requested') equals: '1999-01-01'.
	self assert: (data at: 'supported') equals: protocolServer supportedProtocolVersions
]

{ #category : 'Session Management' }
TestMcpStreamableHttpAdmission >> testPreReadyNotificationIsRejected [
	"A non-initialized notification cannot run before session readiness."

	| exchange session message request |

	exchange := self performInitializationId: 89.
	session := exchange at: 'session'.
	message := self jsonRpcMessageMethod: 'notifications/cancelled' id: nil.
	request := self requestForMessage: message session: session.
	self assert: (transport handlePostRequest: request) equals: ''.
	self assert: request header responseHeader status equals: '400 Bad Request'.
	self assert: session isInitializing
]

{ #category : 'Session Management' }
TestMcpStreamableHttpAdmission >> testPreReadyRequestReturnsServerNotInitialized [
	"A non-ping request receives the MCP server-not-initialized error."

	| exchange session message request body response error constants |

	exchange := self performInitializationId: 90.
	session := exchange at: 'session'.
	message := self jsonRpcMessageMethod: 'tools/list' id: 91.
	request := self requestForMessage: message session: session.
	body := transport handlePostRequest: request.
	response := McpJSONReader fromString: body.
	error := response at: 'error'.
	constants := Smalltalk at: #McpJsonRpcConstants.
	self assert: request header responseHeader status equals: '200 OK'.
	self assert: (error at: 'code') equals: (constants at: 'McpServerNotInitializedErrorCode').
	self assert: (error at: 'message') equals: 'Server not initialized'.
	self assert: session isInitializing
]

{ #category : 'Validation' }
TestMcpStreamableHttpAdmission >> testProtocolVersionMustMatchKnownSession [
	"Every post-initialization request must use the negotiated version."

	| exchange session request response body |

	exchange := self performInitializationId: 92.
	session := exchange at: 'session'.
	request := self requestForMessage: (self jsonRpcMessageMethod: 'ping' id: 93) session: session.
	request headerAt: 'MCP-Protocol-Version' put: '2099-01-01'.
	response := transport handlePostRequest: request.
	self assert: request header responseHeader status equals: '400 Bad Request'.
	body := McpJSONReader fromString: response.
	self assert: ((body at: 'error') at: 'code') equals: -32022
]

{ #category : 'Session Management' }
TestMcpStreamableHttpAdmission >> testReadySessionDispatchesRequests [
	"A ready session dispatches ordinary JSON-RPC requests."

	| exchange session notification readyRequest pingRequest body response |

	exchange := self performInitializationId: 94.
	session := exchange at: 'session'.
	notification := self jsonRpcMessageMethod: 'notifications/initialized' id: nil.
	readyRequest := self requestForMessage: notification session: session.
	transport handlePostRequest: readyRequest.
	pingRequest := self
		requestForMessage: (self jsonRpcMessageMethod: 'ping' id: 95)
		session: session.
	body := transport handlePostRequest: pingRequest.
	response := McpJSONReader fromString: body.
	self assert: session isReady.
	self assert: pingRequest header responseHeader status equals: '200 OK'.
	self assert: (response at: 'id') equals: 95.
	self assert: (response at: 'result') isEmpty
]

{ #category : 'Testing' }
TestMcpStreamableHttpAdmission >> testRequestCompletionRestartsIdleInterval [
	"A tool in flight survives the timeout and restarts idle time on
		completion."
	| now session request tool |
	now := 100.
	transport sessionClock: [now]; sessionIdleTimeout: 10.
	session := self readySessionId: 1.
	tool := self toolNamed: 'slow' block: [
		now := 1000.
		self assert: transport expireIdleSessions equals: 0.
		self assert: transport sessionCount equals: 1.
		'done'].
	protocolServer toolRegistry registerTool: tool.
	request := self requestForMessage:
		(self toolCallMessageNamed: 'slow' arguments: nil id: 2) session:
			session.
	transport handlePostRequest: request.
	self assert: request header responseHeader status equals: '200 OK'.
	now := 1009.
	self assert: transport sessionCount equals: 1.
	now := 1010.
	self assert: transport sessionCount equals: 0

]

{ #category : 'Authentication' }
TestMcpStreamableHttpAdmission >> testRequestContextFactoryReceivesRequestAndSession [
	"Each session message receives validated request-scoped context."

	| exchange session request capturedRequest capturedSession context |

	exchange := self performInitializationId: 96.
	session := exchange at: 'session'.
	context :=
		McpServerRequestContext new
			principal: 'principal-1';
			yourself.
	transport requestContextFactory: [:incomingRequest :incomingSession |
		capturedRequest := incomingRequest.
		capturedSession := incomingSession.
		context].
	request := self requestForMessage: (self jsonRpcMessageMethod: 'ping' id: 97) session: session.
	transport handlePostRequest: request.
	self assert: capturedRequest == request.
	self assert: capturedSession == session.
	self assert: context session == session.
	self assert: context transportRequest == request.
	self assert: context principal equals: 'principal-1'.
	self assert: context sessionId equals: session id
]

{ #category : 'Validation' }
TestMcpStreamableHttpAdmission >> testSentinelEncodedMcpNameHeaderMatches [
	"A modern request whose Mcp-Name is Base64 sentinel encoded matches the unencoded body."

	| message request response body encodedName testTool params |

	testTool := self toolNamed: 'echo.tool' block: ['echoed'].
	protocolServer toolRegistry registerTool: testTool.

	encodedName :=
		'=?base64?' , ((Base64Coder current encode: 'echo.tool' asUtf8Bytes) asString) , '?='.
	message := self toolCallMessageNamed: 'echo.tool' arguments: EsOrderedDictionary new id: 301.
	params := message at: 'params'.
	params
		at: '_meta'
		put: (
			EsOrderedDictionary new
				at: 'io.modelcontextprotocol/protocolVersion' put: '2026-07-28';
				at: 'io.modelcontextprotocol/clientCapabilities' put: EsOrderedDictionary new;
				yourself).

	request :=
		(self requestForMessage: message)
			headerAt: 'MCP-Protocol-Version' put: '2026-07-28';
			headerAt: 'Mcp-Method' put: 'tools/call';
			headerAt: 'Mcp-Name' put: encodedName;
			yourself.
	response := transport handlePostRequest: request.
	self assert: request header responseHeader status equals: '200 OK'.
	body := (McpJSONReader on: response readStream) next.
	self assert: (body at: 'id') equals: 301
]

{ #category : 'Validation' }
TestMcpStreamableHttpAdmission >> testSentinelEncodedMcpParamHeaderMatches [
	"A modern request whose Mcp-Param-* header is sentinel encoded matches the body argument."

	| paramTool schema message request response body encodedVal params |

	schema :=
		EsOrderedDictionary new
			at: 'type' put: 'object';
			at: 'properties'
				put: (
					EsOrderedDictionary with:
						'title' -> (
							EsOrderedDictionary new
								at: 'type' put: 'string';
								at: 'x-mcp-header' put: 'Title';
								yourself));
			yourself.
	paramTool :=
		McpBlockTool new
			name: 'article.create';
			inputSchema: schema;
			block: [:arguments | 'Created: ' , (arguments at: 'title')];
			yourself.
	protocolServer toolRegistry registerTool: paramTool.

	encodedVal :=
		'=?base64?' , ((Base64Coder current encode: 'Special Text' asUtf8Bytes) asString) , '?='.
	message :=
		self
			toolCallMessageNamed: 'article.create'
			arguments: (EsOrderedDictionary with: 'title' -> 'Special Text')
			id: 302.
	params := message at: 'params'.
	params
		at: '_meta'
		put: (
			EsOrderedDictionary new
				at: 'io.modelcontextprotocol/protocolVersion' put: '2026-07-28';
				at: 'io.modelcontextprotocol/clientCapabilities' put: EsOrderedDictionary new;
				yourself).

	request :=
		(self requestForMessage: message)
			headerAt: 'MCP-Protocol-Version' put: '2026-07-28';
			headerAt: 'Mcp-Method' put: 'tools/call';
			headerAt: 'Mcp-Name' put: 'article.create';
			headerAt: 'Mcp-Param-Title' put: encodedVal;
			yourself.
	response := transport handlePostRequest: request.
	self assert: request header responseHeader status equals: '200 OK'.
	body := (McpJSONReader on: response readStream) next.
	self assert: (body at: 'id') equals: 302
]

{ #category : 'Validation' }
TestMcpStreamableHttpAdmission >> testSessionBoundRequestAcceptsSupportedProtocolVersion [
	"A session-bound request carrying a supported protocol version dispatches successfully."

	| exchange session request response body |

	exchange := self performInitializationId: 94.
	session := exchange at: 'session'.
	session markReady.
	request :=
		(self requestForMessage: (self jsonRpcMessageMethod: 'ping' id: 95) session: session)
			headerAt: 'MCP-Protocol-Version' put: '2025-11-25';
			yourself.
	response := transport handlePostRequest: request.
	self assert: request header responseHeader status equals: '200 OK'.
	body := (McpJSONReader on: response readStream) next.
	self assert: (body at: 'id') equals: 95
]

{ #category : 'Testing' }
TestMcpStreamableHttpAdmission >> testSessionCapAndDeleteRelease [
	"A full server refuses new sessions; DELETE immediately frees capacity."
	| session refused accepted |
	transport maxSessions: 1.
	session := self readySessionId: 1.
	refused := self requestForMessage: (self initializeMessageId: 2).
	transport handlePostRequest: refused.
	self assert: refused header responseHeader status
		equals: '503 Service Unavailable'.
	self assert: transport sessionCount equals: 1.
	transport handleDeleteRequest: (self deleteRequestForSession: session).
	self assert: transport sessionCount equals: 0.
	accepted := self requestForMessage: (self initializeMessageId: 3).
	transport handlePostRequest: accepted.
	self assert: accepted header responseHeader status equals: '200 OK'.
	self assert: transport sessionCount equals: 1

]

{ #category : 'Protocol Operations' }
TestMcpStreamableHttpAdmission >> testSubscriptionsListenAcknowledgesWithSseAccept [
	"A modern subscriptions/listen request with text/event-stream Accept dispatches and acknowledges."

	| message request response body params |

	message :=
		EsOrderedDictionary new
			at: 'jsonrpc' put: '2.0';
			at: 'id' put: 109;
			at: 'method' put: 'subscriptions/listen';
			at: 'params'
				put: (
					EsOrderedDictionary with:
						'notifications' ->
							(EsOrderedDictionary with: 'tools' -> true with: 'prompts' -> true));
			yourself.
	params := message at: 'params'.
	params
		at: '_meta'
		put: (
			EsOrderedDictionary new
				at: 'io.modelcontextprotocol/protocolVersion' put: '2026-07-28';
				at: 'io.modelcontextprotocol/clientCapabilities' put: EsOrderedDictionary new;
				yourself).
	request :=
		(self requestForMessage: message)
			headerAt: 'MCP-Protocol-Version' put: '2026-07-28';
			headerAt: 'Mcp-Method' put: 'subscriptions/listen';
			headerAt: 'Accept' put: 'text/event-stream';
			yourself.
	response := transport handlePostRequest: request.
	self assert: request header responseHeader status equals: '200 OK'.
	body := (McpJSONReader on: response readStream) next.
	self assert: (body at: 'id') equals: 109.
	self assert: (((body at: 'result') at: 'notifications') at: 'tools') equals: true.
	self assert: (((body at: 'result') at: 'notifications') at: 'prompts') equals: true
]

{ #category : 'Validation' }
TestMcpStreamableHttpAdmission >> testSubscriptionsListenRequiresSseAcceptInModernMode [
	"A subscriptions/listen request whose Accept lacks text/event-stream is rejected with 406."

	| message request response |

	message := self jsonRpcMessageMethod: 'subscriptions/listen' id: 108.
	request :=
		(self requestForMessage: message)
			headerAt: 'MCP-Protocol-Version' put: '2026-07-28';
			headerAt: 'Mcp-Method' put: 'subscriptions/listen';
			headerAt: 'Accept' put: 'application/json';
			yourself.
	response := transport handlePostRequest: request.
	self assert: request header responseHeader status equals: '406 Not Acceptable'
]

{ #category : 'Protocol Operations' }
TestMcpStreamableHttpAdmission >> testSubscriptionsListenStreamsAcknowledgmentNotification [
	"Verify subscriptions/listen streams notifications/subscriptions/acknowledged as the first message per MCP 2026-07-28."

	| message request capturedBytes connection events parsedMessage meta |

	message :=
		EsOrderedDictionary new
			at: 'jsonrpc' put: '2.0';
			at: 'id' put: 555;
			at: 'method' put: 'subscriptions/listen';
			at: 'params'
				put: (
					EsOrderedDictionary with:
						'notifications' ->
							(EsOrderedDictionary with: 'toolsListChanged' -> true));
			yourself.
	request := self requestForMessage: message.
	capturedBytes := nil.
	connection := TestMcpDeliveryConnection new.
	connection writeAction: [:bytes |
		capturedBytes := bytes copy.
		Error signal: 'stopStream'].
	[
		transport
			streamSubscriptionsListen: message
			on: connection
			request: request
	] on: Error do: [:e | nil].

	self assert: capturedBytes notNil.
	events := McpSseParser new parse: capturedBytes asString.
	self assert: events notEmpty.
	parsedMessage := McpJSONReader fromString: events first data.

	"Per MCP 2026-07-28: acknowledgment MUST be a notification (no id) with method notifications/subscriptions/acknowledged"
	self assert: (parsedMessage at: 'jsonrpc') equals: '2.0'.
	self assert: (parsedMessage at: 'method') equals: 'notifications/subscriptions/acknowledged'.
	self assert: (parsedMessage includesKey: 'id') not.
	self assert: (parsedMessage includesKey: 'params').
	meta := (parsedMessage at: 'params') at: '_meta'.
	self assert: (meta at: 'io.modelcontextprotocol/subscriptionId') equals: 555.
	self assert: (((parsedMessage at: 'params') at: 'notifications') at: 'toolsListChanged') equals: true
]

{ #category : 'Session Management' }
TestMcpStreamableHttpAdmission >> testSuccessfulInitializationCreatesNegotiatedSession [
	"Initialize returns a session header and retains negotiated metadata."

	| exchange request body response result session sessionId |

	exchange := self performInitializationId: 98.
	request := exchange at: 'request'.
	body := exchange at: 'body'.
	response := McpJSONReader fromString: body.
	result := response at: 'result'.
	session := exchange at: 'session'.
	sessionId := exchange at: 'sessionId'.
	self assert: request header responseHeader status equals: '200 OK'.
	self assert: request header responseHeader contentType equals: 'application/json'.
	self assert: request header responseHeader contentLength equals: body asUtf8Bytes size.
	self deny: sessionId isEmpty.
	self assert: session id equals: sessionId.
	self assert: session isInitializing.
	self
		assert: session protocolVersion
		equals: protocolServer supportedHandshakeProtocolVersions first.
	self assert: (session clientInfo at: 'name') equals: 'test-client'.
	self assert: (session clientInfo at: 'version') equals: '1.0'.
	self assert: (session clientCapabilities includesKey: 'roots').
	self assert: (result at: 'protocolVersion') equals: session protocolVersion
]

{ #category : 'Session Management' }
TestMcpStreamableHttpAdmission >> testValidProtocolRequiresKnownSession [
	"A non-initialize POST distinguishes missing and unknown sessions."

	| missing unknown version |

	version := protocolServer supportedHandshakeProtocolVersions first.
	missing := self validRequestWithBody: (self pingJsonId: 72).
	missing headerAt: 'MCP-Protocol-Version' put: version.
	self assert: (transport handlePostRequest: missing) equals: ''.
	self assert: missing header responseHeader status equals: '400 Bad Request'.
	unknown := self validRequestWithBody: (self pingJsonId: 73).
	unknown headerAt: 'MCP-Protocol-Version' put: version.
	unknown headerAt: 'MCP-Session-Id' put: 'unknown-session'.
	self assert: (transport handlePostRequest: unknown) equals: ''.
	self assert: unknown header responseHeader status equals: '404 Not Found'
]

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpStreamableHttpAdmission >> toolCallMessageNamed: toolName arguments: arguments id: identifier [
	"Answer one JSON-RPC tools/call request fixture."

	| message parameters |

	parameters := EsOrderedDictionary with: 'name' -> toolName.
	arguments ifNotNil: [parameters at: 'arguments' put: arguments].
	message := self jsonRpcMessageMethod: 'tools/call' id: identifier.
	message at: 'params' put: parameters.
	^message
]

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpStreamableHttpAdmission >> toolNamed: toolName block: executionBlock [
	"Answer a block tool with a strict no-argument schema."

	^McpBlockTool new
		name: toolName;
		inputSchema: self strictEmptyObjectSchema;
		block: executionBlock;
		yourself
]

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpStreamableHttpAdmission >> validRequestWithBody: bodyString [
	"Answer a request with the required POST representation headers."

	^McpHttpServerTestRequest new
		headerAt: 'Accept' put: 'application/json, text/event-stream';
		contentType: 'application/json';
		contents: bodyString asUtf8Bytes;
		yourself
]
