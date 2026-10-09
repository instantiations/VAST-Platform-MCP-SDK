Class {
	#name : 'TestMcpLegacySseClientTransport',
	#superclass : 'TestCase',
	#pools : [
		'McpJsonRpcConstants'
	],
	#category : 'McpSseTests'
}

{ #category : 'Testing' }
TestMcpLegacySseClientTransport >> testCloseTerminatesPendingRequests [
	"Verify that closing the transport terminates in-flight requests."

	| transport sem entry signaled |

	transport := McpLegacySseClientTransport url: 'http://127.0.0.1:8080/sse'.
	sem := Semaphore new.
	entry :=
		Dictionary new
			at: #semaphore put: sem;
			at: #response put: nil;
			at: #completed put: false;
			at: #timedOut put: false;
			at: #errorReason put: nil;
			yourself.
	(transport instVarNamed: 'pendingRequests') at: 1 put: entry.

	transport close.

	self assert: (entry at: #errorReason) notNil.
	signaled := false.
	[
		sem wait.
		signaled := true]
			fork.
	(Delay forMilliseconds: 20) wait.
	self assert: signaled
]

{ #category : 'Testing' }
TestMcpLegacySseClientTransport >> testExtractSessionId [
	"Verify session ID extraction from endpoint URLs."

	| transport |

	transport := McpLegacySseClientTransport url: 'http://127.0.0.1:8080/sse'.
	self assert: (transport extractSessionIdFrom: '/messages/?session_id=abc-123') equals: 'abc-123'.
	self
		assert: (transport extractSessionIdFrom: '/messages/?session_id=abc-123&foo=bar')
		equals: 'abc-123'.
	self assert: (transport extractSessionIdFrom: '/messages/?sessionId=def-456') equals: 'def-456'.
	self
		assert: (transport extractSessionIdFrom: '/messages/?sessionId=def-456&foo=bar')
		equals: 'def-456'.
	self assert: (transport extractSessionIdFrom: '/messages/plain') isNil
]

{ #category : 'Testing' }
TestMcpLegacySseClientTransport >> testHandleSseEventEndpoint [
	"Verify endpoint discovery and session ID extraction from SSE events."

	| transport event |

	transport := McpLegacySseClientTransport url: 'http://127.0.0.1:8080/sse'.
	event :=
		McpSseEvent new
			type: 'endpoint';
			data: '/messages/?session_id=sess-999';
			yourself.
	transport handleSseEvent: event.
	self
		assert: transport postUrl asString
		equals: 'http://127.0.0.1:8080/messages/?session_id=sess-999'.
	self assert: transport sessionID equals: 'sess-999'
]

{ #category : 'Testing' }
TestMcpLegacySseClientTransport >> testHandleSseEventMessageCorrelatesPendingRequest [
	"Verify that an incoming message event fulfills a waiting pending request."

	| transport sem entry event responseJson |

	transport := McpLegacySseClientTransport url: 'http://127.0.0.1:8080/sse'.
	sem := Semaphore new.
	entry :=
		Dictionary new
			at: #semaphore put: sem;
			at: #response put: nil;
			at: #completed put: false;
			at: #timedOut put: false;
			at: #errorReason put: nil;
			yourself.
	(transport instVarNamed: 'pendingRequests') at: 42 put: entry.

	responseJson := '{"jsonrpc":"2.0","id":42,"result":{"protocolVersion":"2024-11-05"}}'.
	event :=
		McpSseEvent new
			type: 'message';
			data: responseJson;
			yourself.
	transport handleSseEvent: event.

	self assert: (entry at: #completed) equals: true.
	self assert: ((entry at: #response) at: 'result') notNil.
	self assert: (((entry at: #response) at: 'result') at: 'protocolVersion') equals: '2024-11-05'
]

{ #category : 'Testing' }
TestMcpLegacySseClientTransport >> testHandleSseEventMessageForwardsNotificationToClient [
	"Verify that an incoming notification event is forwarded to the owning client."

	| transport client receivedNotification event |

	transport := McpLegacySseClientTransport url: 'http://127.0.0.1:8080/sse'.
	client := McpClient legacy.
	client transport: transport.
	receivedNotification := nil.
	client
		onNotification: 'notifications/tools/list_changed'
		do: [:params | receivedNotification := params].

	event :=
		McpSseEvent new
			type: 'message';
			data: '{"jsonrpc":"2.0","method":"notifications/tools/list_changed","params":{}}';
			yourself.
	transport handleSseEvent: event.

	self assert: receivedNotification notNil
]

{ #category : 'Testing' }
TestMcpLegacySseClientTransport >> testKeepAlivePingInMessageEventIsIgnored [
	"Verify that empty message events (keep-alives) are ignored."

	| transport event |

	transport := McpLegacySseClientTransport url: 'http://127.0.0.1:8080/sse'.
	event :=
		McpSseEvent new
			type: 'message';
			data: '';
			yourself.
	transport handleSseEvent: event.
	self assert: true
]

{ #category : 'Testing' }
TestMcpLegacySseClientTransport >> testMalformedJsonInMessageEventIsSafelyIgnored [
	"Verify that malformed JSON in SSE events does not raise unhandled exceptions."

	| transport event |

	transport := McpLegacySseClientTransport url: 'http://127.0.0.1:8080/sse'.
	event :=
		McpSseEvent new
			type: 'message';
			data: 'not-json-content';
			yourself.
	transport handleSseEvent: event.
	self assert: true
]

{ #category : 'Testing' }
TestMcpLegacySseClientTransport >> testResolveEndpointUrl [
	"Verify resolution and origin matching of discovered endpoint URLs."

	| transport resolved |

	transport := McpLegacySseClientTransport url: 'http://127.0.0.1:8080/sse'.
	resolved := transport resolveEndpointUrl: '/messages/?session_id=123'.
	self assert: resolved asString equals: 'http://127.0.0.1:8080/messages/?session_id=123'.

	resolved := transport resolveEndpointUrl: 'http://127.0.0.1:8080/custom-messages'.
	self assert: resolved asString equals: 'http://127.0.0.1:8080/custom-messages'.

	"Different port must be rejected"
	self should: [transport resolveEndpointUrl: 'http://127.0.0.1:9090/messages'] raise: Error.

	"Different scheme must be rejected"
	self should: [transport resolveEndpointUrl: 'https://127.0.0.1:8080/messages'] raise: Error.

	"Different host must be rejected"
	self should: [transport resolveEndpointUrl: 'http://evil.com/messages'] raise: Error
]

{ #category : 'Testing' }
TestMcpLegacySseClientTransport >> testResponseBeforeAcknowledgmentOrdering [
	"Verify that an SSE message event arriving before or concurrently with the POST request resolves successfully."

	| transport sem entry event responseJson result |

	transport := McpLegacySseClientTransport url: 'http://127.0.0.1:8080/sse'.
	sem := Semaphore new.
	entry :=
		Dictionary new
			at: #semaphore put: sem;
			at: #response put: nil;
			at: #completed put: false;
			at: #timedOut put: false;
			at: #errorReason put: nil;
			yourself.
	(transport instVarNamed: 'pendingRequests') at: 101 put: entry.

	responseJson := '{"jsonrpc":"2.0","id":101,"result":{"status":"ok"}}'.
	event :=
		McpSseEvent new
			type: 'message';
			data: responseJson;
			yourself.
	transport handleSseEvent: event.

	self assert: (entry at: #completed) equals: true.
	result := transport validatedResultFrom: (entry at: #response) id: 101.
	self assert: (result at: 'status') equals: 'ok'
]

{ #category : 'Testing' }
TestMcpLegacySseClientTransport >> testSupportsRequestHeaders [
	"Verify that legacy SSE transports accept request-scoped headers."

	| transport |

	transport := McpLegacySseClientTransport url: 'http://127.0.0.1:8080/sse'.
	self assert: transport supportsRequestHeaders
]

{ #category : 'Testing' }
TestMcpLegacySseClientTransport >> testUrlValidation [
	"Verify validation of SSE endpoint URLs."

	| transport |

	transport := McpLegacySseClientTransport url: 'http://127.0.0.1:8080/sse'.
	self assert: transport url asString equals: 'http://127.0.0.1:8080/sse'.

	self should: [McpLegacySseClientTransport url: 'ftp://127.0.0.1:8080/sse'] raise: Error.
	self should: [McpLegacySseClientTransport url: 'invalid-url'] raise: Error.
	self should: [McpLegacySseClientTransport url: 12345] raise: Error
]
