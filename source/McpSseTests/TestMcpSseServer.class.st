Class {
	#name : 'TestMcpSseServer',
	#superclass : 'TestCase',
	#pools : [
		'McpJsonRpcConstants'
	],
	#category : 'McpSseTests'
}

{ #category : 'Testing' }
TestMcpSseServer >> testCloseSessionReleasesWaitingWriter [
	"Verify that closeSession: marks the session closed and signals waiting processes."

	| transport session signaled |

	transport := McpSseServerTransport new.
	session := transport createSession.

	signaled := false.
	[
		(session at: 'queueSemaphore') wait.
		signaled := session at: 'closed']
			fork.
	(Delay forMilliseconds: 10) wait.
	self deny: signaled.

	transport closeSession: session.
	(Delay forMilliseconds: 10) wait.
	self assert: signaled
]

{ #category : 'Testing' }
TestMcpSseServer >> testCreateAndLookupSession [
	"Verify creating, retrieving, and removing SSE sessions."

	| transport session session2 |

	transport := McpSseServerTransport new.
	session := transport createSession.
	self assert: (session at: 'id') notNil.

	session2 := transport sessionNamed: (session at: 'id') ifAbsent: [nil].
	self assert: session2 == session.

	transport removeSessionNamed: (session at: 'id').
	self assert: (transport sessionNamed: (session at: 'id') ifAbsent: [nil]) isNil
]

{ #category : 'Testing' }
TestMcpSseServer >> testDefaultTransportHostValidation [
	"Verify that default SSE transport rejects foreign Host headers with 403 and accepts localhost."

	| transport request |

	transport := McpSseServerTransport new.

	request :=
		McpHttpServerTestRequest new
			requestUri: '/sse';
			headerAt: 'Host' put: 'evil.attacker.com';
			headerAt: 'Accept' put: 'text/event-stream';
			yourself.
	transport handleSseGetRequest: request.
	self assert: request header responseHeader status equals: '403 Forbidden'.

	request :=
		McpHttpServerTestRequest new
			requestUri: '/sse';
			headerAt: 'Host' put: 'localhost';
			headerAt: 'Accept' put: 'text/event-stream';
			yourself.
	transport handleSseGetRequest: request.
	self deny: request header responseHeader status = '403 Forbidden'
]

{ #category : 'Testing' }
TestMcpSseServer >> testEnqueueMessageAndSessionQueueWakeup [
	"Verify that enqueueMessage:forSession: buffers messages and signals the queue semaphore."

	| transport session message queued signaled |

	transport := McpSseServerTransport new.
	session := transport createSession.
	message :=
		EsOrderedDictionary new
			at: 'jsonrpc' put: '2.0';
			at: 'id' put: 99;
			at: 'result' put: 'ok';
			yourself.

	transport enqueueMessage: message forSession: session.
	queued := session at: 'queue'.
	self assert: queued size equals: 1.
	self assert: queued first equals: message.

	signaled := false.
	[
		(session at: 'queueSemaphore') wait.
		signaled := true]
			fork.
	(Delay forMilliseconds: 10) wait.
	self assert: signaled
]

{ #category : 'Testing' }
TestMcpSseServer >> testHandleDeleteSessionRequestRemovesSession [
	"Verify DELETE on a session removes it and returns 204 No Content."

	| transport session request |

	transport := McpSseServerTransport new.
	session := transport createSession.

	request :=
		McpHttpServerTestRequest new
			requestUri: '/messages?session_id=' , (session at: 'id');
			yourself.
	transport handleDeleteSessionRequest: request.

	self assert: request header responseHeader status equals: '204 No Content'.
	self assert: (transport sessionNamed: (session at: 'id') ifAbsent: [nil]) isNil
]

{ #category : 'Testing' }
TestMcpSseServer >> testHandlePostMessageRequestDispatchesAndReturnsResult [
	"Verify posting a JSON-RPC request to /messages dispatches to the MCP server,
	 acknowledges with 202 Accepted, and enqueues the result on the session."

	| server transport session request body result queued |

	server := McpServer new.
	transport := McpSseServerTransport new mcpServer: server.
	session := transport createSession.

	body := '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}'.
	request :=
		McpHttpServerTestRequest new
			requestUri: '/messages?session_id=' , (session at: 'id');
			contentType: 'application/json';
			contents: body asUtf8Bytes;
			yourself.
	result := transport handlePostMessageRequest: request.

	self assert: request header responseHeader status equals: '202 Accepted'.
	self assert: result equals: ''.
	queued := session at: 'queue'.
	self assert: queued size equals: 1.
	self assert: ((queued first at: 'result') at: 'tools') isEmpty
]

{ #category : 'Testing' }
TestMcpSseServer >> testHandlePostMessageRequestMissingSessionReturns404 [
	"Verify posting to an unknown session returns 404 Not Found."

	| transport request body |

	transport := McpSseServerTransport new.
	body := '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}'.
	request :=
		McpHttpServerTestRequest new
			requestUri: '/messages?session_id=nonexistent-session';
			contentType: 'application/json';
			contents: body asUtf8Bytes;
			yourself.
	transport handlePostMessageRequest: request.

	self assert: request header responseHeader status equals: '404 Not Found'
]

{ #category : 'Testing' }
TestMcpSseServer >> testHandleSseGetRequestCreatesSessionAndAnswersEndpoint [
	"Verify GET /sse creates a session and answers text/event-stream with endpoint event."

	| transport request response parser events endpointEvent |

	transport := McpSseServerTransport new.
	request :=
		McpHttpServerTestRequest new
			requestUri: '/sse';
			headerAt: 'Accept' put: 'text/event-stream';
			yourself.
	response := transport handleSseGetRequest: request.

	self assert: request header responseHeader status equals: '200 OK'.
	self assert: request header responseHeader contentType equals: 'text/event-stream'.
	self assert: (response includesSubstring: 'event: endpoint').
	self assert: (response includesSubstring: 'data: /messages?session_id=').

	parser := McpSseParser new.
	events := parser parse: response.
	self assert: events size equals: 1.
	endpointEvent := events first.
	self assert: endpointEvent type equals: 'endpoint'.
	self assert: (endpointEvent data beginsWithSubCollection: '/messages?session_id=')
]

{ #category : 'Testing' }
TestMcpSseServer >> testHostAndOriginValidation [
	"Verify that Host and Origin restrictions are enforced on SSE endpoints."

	| transport request |

	transport := McpSseServerTransport new.
	transport allowedHosts: #('safe.local').
	transport allowedOrigins: #('http://safe.local').

	request :=
		McpHttpServerTestRequest new
			requestUri: '/sse';
			headerAt: 'Host' put: 'evil.attacker.com';
			headerAt: 'Origin' put: 'http://safe.local';
			headerAt: 'Accept' put: 'text/event-stream';
			yourself.
	transport handleSseGetRequest: request.
	self assert: request header responseHeader status equals: '403 Forbidden'.

	request :=
		McpHttpServerTestRequest new
			requestUri: '/sse';
			headerAt: 'Host' put: 'safe.local';
			headerAt: 'Origin' put: 'http://evil.attacker.com';
			headerAt: 'Accept' put: 'text/event-stream';
			yourself.
	transport handleSseGetRequest: request.
	self assert: request header responseHeader status equals: '403 Forbidden'
]

{ #category : 'Testing' }
TestMcpSseServer >> testLegacyUrlModeElicitationIncludesElicitationId [
	"Verify that when a tool returns a URL-mode McpElicit on a legacy session,
	 the bidirectional bridge emits an elicitation/create request containing elicitationId
	 and completes the tool call once the client responds."

	| server tool transport session callBody callRequest queued elicitReq params srvReqId replyBody replyRequest finalResp |

	server := McpServer new.
	tool :=
		McpBlockTool new
			name: 'connect_account';
			inputSchema: (EsOrderedDictionary with: 'type' -> 'object');
			resolve: 'auth'
				with: [:ctx :args |
					McpElicit
						message: 'Authorize your account'
						url: 'https://example.com/oauth/authorize'];
			block: [:args | | resp |
				resp := args at: 'auth' ifAbsent: [EsOrderedDictionary new].
				(resp at: 'action' ifAbsent: ['cancel']) = 'accept'
					ifTrue: ['Connected']
					ifFalse: ['Cancelled']];
			yourself.
	server toolRegistry registerTool: tool.

	transport := McpSseServerTransport new mcpServer: server.
	session := transport createSession.

	callBody :=
		'{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"connect_account","arguments":{}}}'.
	callRequest :=
		McpHttpServerTestRequest new
			requestUri: '/messages?session_id=' , (session at: 'id');
			contentType: 'application/json';
			contents: callBody asUtf8Bytes;
			yourself.
	transport handlePostMessageRequest: callRequest.
	self assert: callRequest header responseHeader status equals: '202 Accepted'.

	(session at: 'queueSemaphore') wait.
	queued := session at: 'queue'.
	self assert: queued size equals: 1.
	elicitReq := queued removeFirst.
	self assert: (elicitReq at: 'method') equals: 'elicitation/create'.
	srvReqId := elicitReq at: 'id'.
	params := elicitReq at: 'params'.
	self assert: (params at: 'mode') equals: 'url'.
	self assert: (params at: 'url') equals: 'https://example.com/oauth/authorize'.
	self assert: (params at: 'message') equals: 'Authorize your account'.
	self assert: (params at: 'elicitationId') equals: srvReqId.
	self deny: (params includesKey: 'requestedSchema').

	replyBody :=
		'{"jsonrpc":"2.0","id":"' , srvReqId , '","result":{"action":"accept"}}'.
	replyRequest :=
		McpHttpServerTestRequest new
			requestUri: '/messages?session_id=' , (session at: 'id');
			contentType: 'application/json';
			contents: replyBody asUtf8Bytes;
			yourself.
	transport handlePostMessageRequest: replyRequest.

	(session at: 'queueSemaphore') wait.
	self assert: queued size equals: 1.
	finalResp := queued removeFirst.
	self assert: (finalResp at: 'id') equals: 1.
	self assert: (((finalResp at: 'result') at: 'content') first at: 'text') equals: 'Connected'
]
