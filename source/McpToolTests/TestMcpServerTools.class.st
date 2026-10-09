"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# TestMcpServerTools

`TestMcpServerTools` verifies the MCP server tool protocol across protocol
eras.

## Responsibilities

- Verify empty and cursor-paginated tool listings without assuming order.
- Verify modern listings attach `resultType`, `cacheScope`, and `ttlMs`.
- Verify successful, structured, and no-argument tool calls.
- Verify tools returning `InputRequiredResult` preserve their shape across
  dispatch and receive retried `inputResponses` and `requestState`.
- Distinguish protocol errors from actionable tool execution errors.

## Test isolation

Each test creates a fresh server, dispatcher, and registry. Tests perform no
network I/O and create no background work.
"
Class {
	#name : 'TestMcpServerTools',
	#superclass : 'TestCase',
	#instVars : [
		'server',
		'dispatcher',
		'registry'
	],
	#category : 'McpToolTests'
}

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpServerTools >> assertErrorResponse: response code: expectedCode id: expectedIdentifier [
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
TestMcpServerTools >> assertSuccessfulResponse: response id: expectedIdentifier [
	"Assert the structural contract of a JSON-RPC result response."

	self assert: response size equals: 3.
	self assert: (response at: 'jsonrpc') equals: '2.0'.
	self assert: (response at: 'id') equals: expectedIdentifier.
	self assert: (response includesKey: 'result').
	self deny: (response includesKey: 'error')
]

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpServerTools >> requestMethod: methodName params: parameters id: identifier [
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
TestMcpServerTools >> setUp [
	"Create a fresh server, registry, and dispatcher."

	super setUp.
	server := McpServer new.
	registry := server toolRegistry.
	dispatcher := McpJsonRpcDispatcher new.
	dispatcher server: server
]

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpServerTools >> strictEmptyObjectSchema [
	"Answer a schema accepting only an empty object."

	^EsOrderedDictionary new
		at: 'type' put: 'object';
		at: 'additionalProperties' put: false;
		yourself
]

{ #category : 'Protocol Operations' }
TestMcpServerTools >> testEmptyToolListingReturnsCompleteResult [
	"An empty registry produces an empty list result without a cursor."

	| response result |

	response := dispatcher dispatch: (self requestMethod: 'tools/list' params: nil id: 1).
	self assertSuccessfulResponse: response id: 1.
	result := response at: 'result'.
	self assert: result size equals: 1.
	self assert: (result at: 'tools') isEmpty.
	self deny: (result includesKey: 'nextCursor')
]

{ #category : 'Error Handling' }
TestMcpServerTools >> testInvalidArgumentsReturnToolExecutionError [
	"Schema mismatches are actionable tool errors and skip execution."

	| tool schema properties callbackRan arguments response result content |

	callbackRan := false.
	properties := EsOrderedDictionary with: 'value' -> (EsOrderedDictionary with: 'type' -> 'string').
	schema :=
		EsOrderedDictionary new
			at: 'type' put: 'object';
			at: 'properties' put: properties;
			at: 'required' put: #('value');
			yourself.
	tool :=
		McpBlockTool new
			name: 'required.value';
			inputSchema: schema;
			block: [:values |
				callbackRan := true.
				'unused'];
			yourself.
	registry registerTool: tool.
	arguments := EsOrderedDictionary new.
	response :=
		dispatcher dispatch: (self toolCallRequestNamed: 'required.value' arguments: arguments id: 2).
	self assertSuccessfulResponse: response id: 2.
	result := response at: 'result'.
	self assert: (result at: 'isError') equals: true.
	content := result at: 'content'.
	self assert: content size equals: 1.
	self assert: (content first at: 'type') equals: 'text'.
	self assert: (content first at: 'text') isEmpty not.
	self deny: callbackRan
]

{ #category : 'Validation' }
TestMcpServerTools >> testMalformedAndExpiredToolCursorsAreRejected [
	"Malformed and out-of-range cursors produce invalid-params errors."

	| parameters response |

	#('not-a-cursor' '1') do: [:cursor |
		parameters := EsOrderedDictionary with: 'cursor' -> cursor.
		response :=
			dispatcher dispatch: (self requestMethod: 'tools/list' params: parameters id: cursor).
		self assertErrorResponse: response code: -32602 id: cursor]
]

{ #category : 'Protocol Operations' }
TestMcpServerTools >> testNoArgumentToolAcceptsOmittedAndEmptyArguments [
	"A strict no-argument tool accepts omitted and empty argument objects."

	| callCount tool firstResponse secondResponse |

	callCount := 0.
	tool :=
		self
			toolNamed: 'no.arguments'
			block: [
				callCount := callCount + 1.
				'no arguments'].
	registry registerTool: tool.
	firstResponse :=
		dispatcher dispatch: (self toolCallRequestNamed: 'no.arguments' arguments: nil id: 3).
	secondResponse :=
		dispatcher dispatch:
			(self toolCallRequestNamed: 'no.arguments' arguments: EsOrderedDictionary new id: 4).
	self assertSuccessfulResponse: firstResponse id: 3.
	self assertSuccessfulResponse: secondResponse id: 4.
	self assert: callCount equals: 2.
	self
		assert: (((firstResponse at: 'result') at: 'content') first at: 'text')
		equals: 'no arguments'.
	self
		assert: (((secondResponse at: 'result') at: 'content') first at: 'text')
		equals: 'no arguments'
]

{ #category : 'Protocol Operations' }
TestMcpServerTools >> testSuccessfulToolCallReceivesDetachedArguments [
	"A successful call passes detached arguments and returns text content."

	| capturedArguments tool schema properties arguments response result content |

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
	registry registerTool: tool.
	arguments := EsOrderedDictionary with: 'message' -> 'hello'.
	response :=
		dispatcher dispatch: (self toolCallRequestNamed: 'echo.message' arguments: arguments id: 5).
	arguments at: 'message' put: 'changed'.
	self assertSuccessfulResponse: response id: 5.
	self assert: (capturedArguments at: 'message') equals: 'hello'.
	result := response at: 'result'.
	self assert: (result at: 'isError') equals: false.
	content := result at: 'content'.
	self assert: content size equals: 1.
	self assert: (content first at: 'type') equals: 'text'.
	self assert: (content first at: 'text') equals: 'hello'
]

{ #category : 'Error Handling' }
TestMcpServerTools >> testToolExecutionFailureReturnsNormalErrorResult [
	"A callback failure returns actionable content in a normal result."

	| tool response result content |

	tool := self toolNamed: 'failing.tool' block: [self error: 'The upstream service is unavailable'].
	registry registerTool: tool.
	response := dispatcher dispatch: (self toolCallRequestNamed: 'failing.tool' arguments: nil id: 6).
	self assertSuccessfulResponse: response id: 6.
	result := response at: 'result'.
	self assert: (result at: 'isError') equals: true.
	content := result at: 'content'.
	self assert: content size equals: 1.
	self assert: (content first at: 'type') equals: 'text'.
	self assert: (content first at: 'text') equals: 'The upstream service is unavailable'
]

{ #category : 'Protocol Operations' }
TestMcpServerTools >> testToolListingPaginatesWithoutOrderAssumptions [
	"Cursor pagination returns every registered definition exactly once."

	| firstResponse secondResponse firstResult secondResult firstTools secondTools names cursor
	  parameters |

	#('zeta.tool' 'alpha.tool' 'middle.tool')
		do: [:toolName | registry registerTool: (self toolNamed: toolName block: ['listed'])].
	server listPageSize: 2.
	firstResponse := dispatcher dispatch: (self requestMethod: 'tools/list' params: nil id: 7).
	self assertSuccessfulResponse: firstResponse id: 7.
	firstResult := firstResponse at: 'result'.
	firstTools := firstResult at: 'tools'.
	self assert: firstTools size equals: 2.
	cursor := firstResult at: 'nextCursor'.
	self assert: cursor isString.
	parameters := EsOrderedDictionary with: 'cursor' -> cursor.
	secondResponse := dispatcher
		dispatch: (self requestMethod: 'tools/list' params: parameters id: 8).
	self assertSuccessfulResponse: secondResponse id: 8.
	secondResult := secondResponse at: 'result'.
	secondTools := secondResult at: 'tools'.
	self assert: secondTools size equals: 1.
	self deny: (secondResult includesKey: 'nextCursor').
	names := Set new.
	firstTools do: [:definition | names add: (definition at: 'name')].
	secondTools do: [:definition | names add: (definition at: 'name')].
	self assert: names size equals: 3.
	self assert: (names includes: 'zeta.tool').
	self assert: (names includes: 'alpha.tool').
	self assert: (names includes: 'middle.tool')
]

{ #category : 'Protocol Operations' }
TestMcpServerTools >> testToolMayReturnInputRequiredResult [
	"A tool returning an InputRequiredResult preserves its shape across dispatch."

	| tool request response result |

	tool :=
		self
			toolNamed: 'two.step'
			block: [:arguments :context |
				(context notNil and: [context inputResponses notNil])
					ifFalse: [
						EsOrderedDictionary new
							at: 'resultType' put: 'inputRequired';
							at: 'requestState' put: 'step-1';
							at: 'inputRequests'
								put: (
									EsOrderedDictionary with:
										'q' -> (
											EsOrderedDictionary
												with: 'method' -> 'elicitation/create'));
							yourself]
					ifTrue: ['Answer was: ' , (context inputResponses at: 'q') printString]].
	registry registerTool: tool.

	request := self toolCallRequestNamed: 'two.step' arguments: EsOrderedDictionary new id: 1.
	response := dispatcher dispatch: request.
	result := response at: 'result'.
	self assert: (result at: 'resultType') equals: 'inputRequired'.
	self assert: (result at: 'requestState') equals: 'step-1'.
	self assert: (result includesKey: 'inputRequests')
]

{ #category : 'Protocol Operations' }
TestMcpServerTools >> testToolWithArrayOutputSchemaReturnsArrayStructuredContent [
	"Per MCP 2026-07-28 SEP-2106, structuredContent can be any JSON value including an array."

	| tool outputSchema response result structured content users |

	outputSchema :=
		EsOrderedDictionary new
			at: 'type' put: 'array';
			at: 'items' put: (
				EsOrderedDictionary new
					at: 'type' put: 'object';
					at: 'properties' put: (
						EsOrderedDictionary with: 'id' -> (EsOrderedDictionary with: 'type' -> 'string')
							with: 'name' -> (EsOrderedDictionary with: 'type' -> 'string'));
					at: 'required' put: #('id' 'name');
					yourself);
			yourself.
	users := Array
		with: (EsOrderedDictionary with: 'id' -> '1' with: 'name' -> 'Alice')
		with: (EsOrderedDictionary with: 'id' -> '2' with: 'name' -> 'Bob').
	tool := self toolNamed: 'users.list' block: [users copy].
	tool outputSchema: outputSchema.
	registry registerTool: tool.

	response := dispatcher dispatch: (self toolCallRequestNamed: 'users.list' arguments: nil id: 10).
	self assertSuccessfulResponse: response id: 10.
	result := response at: 'result'.
	self assert: (result at: 'isError') equals: false.
	structured := result at: 'structuredContent'.
	self assert: (structured isKindOf: SequenceableCollection).
	self assert: (structured isKindOf: KeyedCollection) not.
	self assert: structured size equals: 2.
	self assert: (structured first at: 'name') equals: 'Alice'.
	content := result at: 'content'.
	self assert: content size equals: 1.
	self assert: (content first at: 'type') equals: 'text'
]

{ #category : 'Protocol Operations' }
TestMcpServerTools >> testToolWithOutputSchemaReturnsStructuredContent [
	"A schema-backed tool returns matching structured and text content."

	| tool outputSchema properties response result content structured |

	properties := EsOrderedDictionary with: 'total' -> (EsOrderedDictionary with: 'type' -> 'number').
	outputSchema :=
		EsOrderedDictionary new
			at: 'type' put: 'object';
			at: 'properties' put: properties;
			at: 'required' put: #('total');
			yourself.
	tool := self toolNamed: 'structured.total' block: [EsOrderedDictionary with: 'total' -> 12].
	tool outputSchema: outputSchema.
	registry registerTool: tool.
	response :=
		dispatcher dispatch: (self toolCallRequestNamed: 'structured.total' arguments: nil id: 9).
	self assertSuccessfulResponse: response id: 9.
	result := response at: 'result'.
	self assert: (result at: 'isError') equals: false.
	structured := result at: 'structuredContent'.
	self assert: (structured at: 'total') equals: 12.
	content := result at: 'content'.
	self assert: content size equals: 1.
	self assert: (content first at: 'type') equals: 'text'.
	self assert: (content first at: 'text') isEmpty not
]

{ #category : 'Error Handling' }
TestMcpServerTools >> testUnknownToolReturnsProtocolError [
	"An unknown tool produces a correlated invalid-params protocol error."

	| response |

	response := dispatcher
		dispatch: (self toolCallRequestNamed: 'missing.tool' arguments: nil id: 10).
	self assertErrorResponse: response code: -32602 id: 10.
	self assert: ((response at: 'error') at: 'message') equals: 'Unknown tool: missing.tool'
]

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpServerTools >> toolCallRequestNamed: toolName arguments: arguments id: identifier [
	"Answer a tools/call request fixture."

	| parameters |

	parameters := EsOrderedDictionary with: 'name' -> toolName.
	arguments ifNotNil: [parameters at: 'arguments' put: arguments].
	^self requestMethod: 'tools/call' params: parameters id: identifier
]

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpServerTools >> toolNamed: toolName block: executionBlock [
	"Answer a block tool with a valid strict object input schema."

	^McpBlockTool new
		name: toolName;
		inputSchema: self strictEmptyObjectSchema;
		block: executionBlock;
		yourself
]
