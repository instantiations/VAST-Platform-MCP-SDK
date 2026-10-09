"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# TestMcpJsonRpcDispatcher

`TestMcpJsonRpcDispatcher` verifies transport-neutral JSON-RPC dispatch.

## Responsibilities

- Verify request identifier validation and response correlation.
- Verify invalid-request and method-not-found error envelopes.
- Verify notifications never produce responses.
- Verify unexpected handler failures become internal errors.

Each test creates a fresh dispatcher and server. Tests perform no network I/O,
create no background work, and share no mutable fixtures.
"
Class {
	#name : 'TestMcpJsonRpcDispatcher',
	#superclass : 'TestCase',
	#instVars : [
		'server',
		'dispatcher'
	],
	#category : 'McpProtocolTests'
}

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpJsonRpcDispatcher >> assertErrorResponse: response code: expectedCode id: expectedIdentifier [
	"Assert the complete structural contract of a JSON-RPC error response."

	| error |

	self assert: response size equals: 3.
	self assert: (response at: 'jsonrpc') equals: '2.0'.
	self assert: (response at: 'id') equals: expectedIdentifier.
	self deny: (response includesKey: 'result').
	error := response at: 'error'.
	self assert: (error at: 'code') equals: expectedCode.
	self assert: (error at: 'message') isString.
	self deny: (error at: 'message') isEmpty
]

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpJsonRpcDispatcher >> notificationMethod: methodName params: parameters [
	"Answer a JSON-RPC notification fixture."

	| notification |

	notification :=
		EsOrderedDictionary new
			at: 'jsonrpc' put: '2.0';
			at: 'method' put: methodName;
			yourself.
	parameters ifNotNil: [notification at: 'params' put: parameters].
	^notification
]

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpJsonRpcDispatcher >> requestMethod: methodName params: parameters id: identifier [
	"Answer a JSON-RPC request fixture."

	| request |

	request :=
		EsOrderedDictionary new
			at: 'jsonrpc' put: '2.0';
			at: 'id' put: identifier;
			at: 'method' put: methodName;
			yourself.
	parameters ifNotNil: [request at: 'params' put: parameters].
	^request
]

{ #category : 'Initialization' }
TestMcpJsonRpcDispatcher >> setUp [
	"Create a fresh server and dispatcher."

	super setUp.
	server := McpServer new.
	dispatcher := McpJsonRpcDispatcher new.
	dispatcher server: server
]

{ #category : 'Validation' }
TestMcpJsonRpcDispatcher >> testEmptyObjectIsInvalidRequest [
	"An empty object produces an uncorrelated invalid-request error."

	| response |

	response := dispatcher dispatch: EsOrderedDictionary new.
	self assertErrorResponse: response code: -32600 id: nil
]

{ #category : 'Validation' }
TestMcpJsonRpcDispatcher >> testFractionalRequestIdentifierIsRejected [
	"MCP request identifiers may not be fractional numbers."

	| request response |

	request := self requestMethod: 'ping' params: nil id: 1.5.
	response := dispatcher dispatch: request.
	self assertErrorResponse: response code: -32600 id: nil
]

{ #category : 'Validation' }
TestMcpJsonRpcDispatcher >> testInvalidVersionPreservesReadableIdentifier [
	"A readable identifier remains correlated when the version is invalid."

	| request response |

	request := self requestMethod: 'ping' params: nil id: 'bad-version'.
	request at: 'jsonrpc' put: '1.0'.
	response := dispatcher dispatch: request.
	self assertErrorResponse: response code: -32600 id: 'bad-version'
]

{ #category : 'Dispatching' }
TestMcpJsonRpcDispatcher >> testKnownNotificationHasNoResponse [
	"A known notification is dispatched without a response."

	| notification |

	notification :=
		self notificationMethod: 'notifications/initialized' params: EsOrderedDictionary new.
	self assert: (dispatcher dispatch: notification) equals: nil
]

{ #category : 'Validation' }
TestMcpJsonRpcDispatcher >> testMissingMethodPreservesReadableIdentifier [
	"A request missing its method retains a readable response identifier."

	| request response |

	request :=
		EsOrderedDictionary new
			at: 'jsonrpc' put: '2.0';
			at: 'id' put: 17;
			yourself.
	response := dispatcher dispatch: request.
	self assertErrorResponse: response code: -32600 id: 17
]

{ #category : 'Validation' }
TestMcpJsonRpcDispatcher >> testNonObjectIsInvalidRequest [
	"A non-object message produces an uncorrelated invalid-request error."

	| response |

	response := dispatcher dispatch: #().
	self assertErrorResponse: response code: -32600 id: nil
]

{ #category : 'Dispatching' }
TestMcpJsonRpcDispatcher >> testNumericRequestIdentifierIsCorrelated [
	"An integer request identifier is repeated in the result response."

	| response |

	response := dispatcher dispatch: (self requestMethod: 'ping' params: nil id: 42).
	self assert: (response at: 'jsonrpc') equals: '2.0'.
	self assert: (response at: 'id') equals: 42.
	self assert: (response at: 'result') isEmpty.
	self deny: (response includesKey: 'error')
]

{ #category : 'Error Handling' }
TestMcpJsonRpcDispatcher >> testRegisteredHandlerFailureBecomesInternalError [
	"An unexpected handler failure is hidden behind an internal error."

	| request response |

	dispatcher
		registerMethod: 'testing/fail'
		handler: [:parameters :context | self error: 'Deliberate test-handler failure'].
	request := self requestMethod: 'testing/fail' params: nil id: 8.
	response := dispatcher dispatch: request.
	self assertErrorResponse: response code: -32603 id: 8.
	self assert: ((response at: 'error') at: 'message') equals: 'Internal error'
]

{ #category : 'Dispatching' }
TestMcpJsonRpcDispatcher >> testResponseObjectIsIgnored [
	"A valid response object received by the server is not answered."

	| responseObject |

	responseObject :=
		EsOrderedDictionary new
			at: 'jsonrpc' put: '2.0';
			at: 'id' put: 4;
			at: 'result' put: EsOrderedDictionary new;
			yourself.
	self assert: (dispatcher dispatch: responseObject) equals: nil
]

{ #category : 'Dispatching' }
TestMcpJsonRpcDispatcher >> testStringRequestIdentifierIsCorrelated [
	"A string request identifier is repeated exactly in the response."

	| response |

	response := dispatcher dispatch: (self requestMethod: 'ping' params: nil id: 'request-7').
	self assert: (response at: 'jsonrpc') equals: '2.0'.
	self assert: (response at: 'id') equals: 'request-7'.
	self assert: (response at: 'result') isEmpty.
	self deny: (response includesKey: 'error')
]

{ #category : 'Dispatching' }
TestMcpJsonRpcDispatcher >> testUnknownNotificationHasNoResponse [
	"An unknown notification produces no response."

	| notification |

	notification := self notificationMethod: 'testing/unknown' params: EsOrderedDictionary new.
	self assert: (dispatcher dispatch: notification) equals: nil
]

{ #category : 'Error Handling' }
TestMcpJsonRpcDispatcher >> testUnknownRequestProducesMethodNotFound [
	"An unknown request produces a correlated method-not-found error."

	| request response |

	request := self requestMethod: 'testing/unknown' params: nil id: 9.
	response := dispatcher dispatch: request.
	self assertErrorResponse: response code: -32601 id: 9.
	self assert: ((response at: 'error') at: 'message') equals: 'Method not found: testing/unknown'
]
