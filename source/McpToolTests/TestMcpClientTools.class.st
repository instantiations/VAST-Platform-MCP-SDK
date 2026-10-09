"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# TestMcpClientTools

`TestMcpClientTools` verifies client-side MCP tool operations and multi-round
trip execution.

## Responsibilities

- Verify connection and negotiated-capability gating.
- Verify cursor pagination without assuming server ordering.
- Verify exact `tools/list` and `tools/call` request construction.
- Verify tool-definition and result validation.
- Verify client-side Multi-Round-Trip Request (MRTR) loops resolve input
  requests and enforce `inputRequiredMaxRounds` boundaries.

## Test isolation

Each test creates a new client and `McpScriptedClientTransport`. Tests perform
no network I/O, create no background work, and make no timing assumptions.
"
Class {
	#name : 'TestMcpClientTools',
	#superclass : 'TestCase',
	#instVars : [
		'client',
		'transport'
	],
	#category : 'McpToolTests'
}

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpClientTools >> connectWithCapabilities: capabilities [
	"Connect using the supplied server capability declaration."

	transport enqueueResponse: (self initializeResultWith: capabilities).
	client connect
]

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpClientTools >> connectWithToolsCapability [
	"Connect to a server advertising the tools capability."

	self connectWithCapabilities: (EsOrderedDictionary with: 'tools' -> EsOrderedDictionary new)
]

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpClientTools >> initializeResultWith: capabilities [
	"Answer a valid initialization result with supplied capabilities."

	^EsOrderedDictionary new
		at: 'protocolVersion' put: '2025-11-25';
		at: 'capabilities' put: capabilities;
		at: 'serverInfo'
			put:
				(EsOrderedDictionary with: 'name' -> 'ScriptedToolServer' with: 'version' -> '1.0.0');
		yourself
]

{ #category : 'Initialization' }
TestMcpClientTools >> setUp [
	"Create a fresh client and scripted transport."

	super setUp.
	transport := McpScriptedClientTransport new.
	client := McpClient new.
	client transport: transport
]

{ #category : 'Testing' }
TestMcpClientTools >> testCallRejectsExternalOutputReference [
	"Reject an unresolvable advertised schema at the actual call boundary."
	| result definition failureText |
	self connectWithToolsCapability.
	result := self textToolResult: 'value' isError: false.
	result at: 'structuredContent' put: EsOrderedDictionary new.
	definition := self toolDefinitionNamed: 'probe'.
	definition at: 'outputSchema' put:
		(EsOrderedDictionary with: '$ref' -> 'https://example.invalid/schema').
	transport enqueueResponse: result.
	transport enqueueResponse:
		(EsOrderedDictionary with: 'tools' -> (Array with: definition)).
	failureText := nil.
	[client callTool: 'probe' arguments: nil]
		on: Error
		do: [:failure |
			failureText := failure messageText.
			failure return].
	self assert: failureText notNil.
	self assert: (failureText beginsWithSubCollection:
		'Invalid schema for tool probe:').
	self assert: transport requests size equals: 3

]

{ #category : 'Testing' }
TestMcpClientTools >> testCallRejectsMissingOutputReference [
	"Reject an unresolvable advertised schema at the actual call boundary."
	| result definition failureText |
	self connectWithToolsCapability.
	result := self textToolResult: 'value' isError: false.
	result at: 'structuredContent' put: EsOrderedDictionary new.
	definition := self toolDefinitionNamed: 'probe'.
	definition at: 'outputSchema' put:
		(EsOrderedDictionary with: '$ref' -> '#/$defs/missing').
	transport enqueueResponse: result.
	transport enqueueResponse:
		(EsOrderedDictionary with: 'tools' -> (Array with: definition)).
	failureText := nil.
	[client callTool: 'probe' arguments: nil]
		on: Error
		do: [:failure |
			failureText := failure messageText.
			failure return].
	self assert: failureText notNil.
	self assert: (failureText beginsWithSubCollection:
		'Invalid schema for tool probe:').
	self assert: transport requests size equals: 3

]

{ #category : 'Validation' }
TestMcpClientTools >> testCallToolAbortsWhenMaxRoundsExceeded [
	"Client aborts when server exceeds inputRequiredMaxRounds."

	| inputRequired |

	inputRequired :=
		EsOrderedDictionary new
			at: 'resultType' put: 'input_required';
			at: 'requestState' put: 'loop';
			yourself.
	self connectWithToolsCapability.
	client inputRequiredMaxRounds: 2.
	3 timesRepeat: [transport enqueueResponse: inputRequired].
	self should: [client callTool: 'loop.tool' arguments: EsOrderedDictionary new] raise: Error
]

{ #category : 'Testing' }
TestMcpClientTools >> testCallToolDrivesInputRequiredLoop [
	"Client automatically resolves InputRequiredResult rounds through registered
		callbacks."

	| inputRequired promptResult result requests |

	self connectWithToolsCapability.
	inputRequired :=
		EsOrderedDictionary new
			at: 'resultType' put: 'inputRequired';
			at: 'requestState' put: 'nonce-1';
			at: 'inputRequests'
				put: (
					EsOrderedDictionary with:
						'confirm' -> (
							EsOrderedDictionary
								with: 'method' -> 'elicitation/create'
								with: 'params' -> (EsOrderedDictionary with:
				'message' -> 'Proceed?')));
			yourself.
	promptResult :=
		EsOrderedDictionary new
			at: 'resultType' put: 'complete';
			at: 'content'
				put:
					(Array with: (EsOrderedDictionary with: 'type' -> 'text'
				with: 'text' -> 'done'));
			at: 'isError' put: false;
			yourself.
	transport enqueueResponse: inputRequired.
	transport enqueueResponse: promptResult.
	client elicitationCallback: [:request :cl |
		self assert: ((request at: 'params') at: 'message') equals: 'Proceed?'.
		EsOrderedDictionary with: 'confirmed' -> true].
	transport enqueueResponse: (EsOrderedDictionary with: 'tools' -> #()).
	result := client callTool: 'interactive.tool' arguments: EsOrderedDictionary
		new.
	self assert: ((result at: 'content') first at: 'text') equals: 'done'.
	self assert: transport requests size equals: 4.
	requests := transport requests.
	self assert: (requests third at: 'method') equals: 'tools/call'.
	self assert: ((requests third at: 'params') at: 'requestState') equals:
		'nonce-1'.
	self
		assert: (((requests third at: 'params') at: 'inputResponses') at:
			'confirm')
		equals: (EsOrderedDictionary with: 'confirmed' -> true)

]

{ #category : 'Testing' }
TestMcpClientTools >> testCallToolOmitsNilArguments [
	"A nil argument value omits the optional arguments member."

	| response request parameters |

	self connectWithToolsCapability.
	response := self textToolResult: 'complete' isError: false.
	transport enqueueResponse: response.
	transport enqueueResponse: (EsOrderedDictionary with: 'tools' -> #()).
	client callTool: 'status.check' arguments: nil.
	request := transport requests at: 2.
	self assert: (request at: 'method') equals: 'tools/call'.
	parameters := request at: 'params'.
	self assert: parameters size equals: 1.
	self assert: (parameters at: 'name') equals: 'status.check'.
	self deny: (parameters includesKey: 'arguments')

]

{ #category : 'Error Handling' }
TestMcpClientTools >> testCallToolPreservesExecutionErrorResult [
	"An execution-error result remains a normal validated tool result."

	| result |

	self connectWithToolsCapability.
	transport enqueueResponse: (self textToolResult: 'Try a later departure date' isError: true).
	result := client callTool: 'travel.plan' arguments: EsOrderedDictionary new.
	self assert: (result at: 'isError') equals: true.
	self assert: ((result at: 'content') first at: 'text') equals: 'Try a later departure date'
]

{ #category : 'Validation' }
TestMcpClientTools >> testCallToolRejectsMalformedResult [
	"The client rejects a tool result without a content array."

	self connectWithToolsCapability.
	transport enqueueResponse: (EsOrderedDictionary with: 'isError' -> false).
	self should: [client callTool: 'broken.result' arguments: nil] raise: Error
]

{ #category : 'Validation' }
TestMcpClientTools >> testCallToolRequiresConnectedClient [
	"A tool call is unavailable before initialization completes."

	self should: [client callTool: 'status.check' arguments: nil] raise: Error.
	self assert: transport interactions isEmpty
]

{ #category : 'Validation' }
TestMcpClientTools >> testCallToolRequiresToolsCapability [
	"A connected client rejects calls when tools were not advertised."

	self connectWithCapabilities: EsOrderedDictionary new.
	self should: [client callTool: 'status.check' arguments: nil] raise: Error.
	self assert: transport requests size equals: 1
]

{ #category : 'Testing' }
TestMcpClientTools >> testCallToolSendsDetachedArgumentsAndValidatesResult [
	"A tool call snapshots arguments and returns validated detached content."

	| arguments scriptedResult result request parameters |

	self connectWithToolsCapability.
	arguments := EsOrderedDictionary with: 'message' -> 'hello'.
	scriptedResult := self textToolResult: 'hello' isError: false.
	transport enqueueResponse: scriptedResult.
	transport enqueueResponse: (EsOrderedDictionary with: 'tools' -> #()).
	result := client callTool: 'echo.message' arguments: arguments.
	arguments at: 'message' put: 'changed'.
	(scriptedResult at: 'content') first at: 'text' put: 'changed result'.
	request := transport requests at: 2.
	self assert: (request at: 'jsonrpc') equals: '2.0'.
	self assert: (request at: 'id') equals: 2.
	self assert: (request at: 'method') equals: 'tools/call'.
	parameters := request at: 'params'.
	self assert: (parameters at: 'name') equals: 'echo.message'.
	self assert: ((parameters at: 'arguments') at: 'message') equals: 'hello'.
	self assert: (result at: 'isError') equals: false.
	self assert: ((result at: 'content') first at: 'text') equals: 'hello'

]

{ #category : 'Testing' }
TestMcpClientTools >> testCallValidatesDiscoveredOutputAndReusesSchema [
	"Discovery happens once for a known schema and validates each result."
	| result definition schema returned |
	self connectWithToolsCapability.
	schema := McpJSONReader fromString:
		'{"type":"object","properties":{"v":{"type":"integer"}}}'.
	definition := self toolDefinitionNamed: 'probe'.
	definition at: 'outputSchema' put: schema.
	result := self textToolResult: 'value' isError: false.
	result at: 'structuredContent' put: (EsOrderedDictionary with: 'v' -> 4).
	transport enqueueResponse: result.
	transport enqueueResponse:
		(EsOrderedDictionary with: 'tools' -> (Array with: definition)).
	returned := client callTool: 'probe' arguments: nil.
	self assert: ((returned at: 'structuredContent') at: 'v') equals: 4.
	(result at: 'structuredContent') at: 'v' put: 'bad'.
	transport enqueueResponse: result.
	self should: [client callTool: 'probe' arguments: nil] raise: Error.
	self assert: transport requests size equals: 4

]

{ #category : 'Protocol Operations' }
TestMcpClientTools >> testListToolsCollectsEveryPageWithoutOrderAssumptions [
	"The client follows cursors and aggregates every valid tool definition."

	| firstPage secondPage tools names firstRequest secondRequest |

	self connectWithToolsCapability.
	firstPage :=
		EsOrderedDictionary new
			at: 'tools'
				put: (
					Array
						with: (self toolDefinitionNamed: 'zeta.tool')
						with: (self toolDefinitionNamed: 'alpha.tool'));
			at: 'nextCursor' put: 'page-2';
			yourself.
	secondPage :=
		EsOrderedDictionary with: 'tools' -> (Array with: (self toolDefinitionNamed: 'middle.tool')).
	transport
		enqueueResponse: firstPage;
		enqueueResponse: secondPage.
	tools := client listTools.
	self assert: tools size equals: 3.
	names := Set new.
	tools do: [:definition | names add: (definition at: 'name')].
	self assert: (names includes: 'zeta.tool').
	self assert: (names includes: 'alpha.tool').
	self assert: (names includes: 'middle.tool').
	self assert: transport requests size equals: 3.
	firstRequest := transport requests at: 2.
	secondRequest := transport requests at: 3.
	self assert: (firstRequest at: 'id') equals: 2.
	self assert: (firstRequest at: 'method') equals: 'tools/list'.
	self assert: (firstRequest at: 'params') isEmpty.
	self assert: (secondRequest at: 'id') equals: 3.
	self assert: (secondRequest at: 'method') equals: 'tools/list'.
	self assert: ((secondRequest at: 'params') at: 'cursor') equals: 'page-2'
]

{ #category : 'Validation' }
TestMcpClientTools >> testListToolsRejectsMalformedDefinition [
	"The client rejects a listed tool without its required input schema."

	| invalidDefinition page |

	self connectWithToolsCapability.
	invalidDefinition := EsOrderedDictionary with: 'name' -> 'missing.schema'.
	page := EsOrderedDictionary with: 'tools' -> (Array with: invalidDefinition).
	transport enqueueResponse: page.
	self should: [client listTools] raise: Error
]

{ #category : 'Validation' }
TestMcpClientTools >> testListToolsRejectsRepeatedCursor [
	"The client rejects a server that repeats a pagination cursor."

	| firstPage secondPage |

	self connectWithToolsCapability.
	firstPage :=
		EsOrderedDictionary new
			at: 'tools' put: #();
			at: 'nextCursor' put: 'same-cursor';
			yourself.
	secondPage :=
		EsOrderedDictionary new
			at: 'tools' put: #();
			at: 'nextCursor' put: 'same-cursor';
			yourself.
	transport
		enqueueResponse: firstPage;
		enqueueResponse: secondPage.
	self should: [client listTools] raise: Error.
	self assert: transport requests size equals: 3
]

{ #category : 'Validation' }
TestMcpClientTools >> testListToolsRequiresToolsCapability [
	"A connected client rejects listing when tools were not advertised."

	self connectWithCapabilities: EsOrderedDictionary new.
	self should: [client listTools] raise: Error.
	self assert: transport requests size equals: 1
]

{ #category : 'Copying' }
TestMcpClientTools >> testListToolsReturnsDetachedDefinitions [
	"Listed definitions are detached from the transport response."

	| definition page tools |

	self connectWithToolsCapability.
	definition := self toolDefinitionNamed: 'snapshot.tool'.
	page := EsOrderedDictionary with: 'tools' -> (Array with: definition).
	transport enqueueResponse: page.
	tools := client listTools.
	definition at: 'name' put: 'changed.tool'.
	(definition at: 'inputSchema') at: 'type' put: 'array'.
	self assert: (tools first at: 'name') equals: 'snapshot.tool'.
	self assert: ((tools first at: 'inputSchema') at: 'type') equals: 'object'
]

{ #category : 'Validation' }
TestMcpClientTools >> testMalformedToolsCapabilityIsRejected [
	"A non-object tools capability cannot authorize tool operations."

	| capabilities |

	capabilities := EsOrderedDictionary with: 'tools' -> true.
	self connectWithCapabilities: capabilities.
	self should: [client listTools] raise: Error.
	self assert: transport requests size equals: 1
]

{ #category : 'Testing' }
TestMcpClientTools >> testMissingStructuredOutputRejected [
	"An advertised output schema requires structured output on success."
	| definition message |
	self connectWithToolsCapability.
	definition := self toolDefinitionNamed: 'probe'.
	definition at: 'outputSchema' put:
		(EsOrderedDictionary with: 'type' -> 'object').
	transport enqueueResponse: (self textToolResult: 'text only' isError:
		false).
	transport enqueueResponse:
		(EsOrderedDictionary with: 'tools' -> (Array with: definition)).
	message := nil.
	[client callTool: 'probe' arguments: nil]
		on: Error
		do: [:failure |
			message := failure messageText.
			failure return].
	self assert: message notNil.
	self assert: (message beginsWithSubCollection:
		'Tool probe has an output schema but no structured content')

]

{ #category : 'Testing' }
TestMcpClientTools >> testToolListNotificationInvalidatesOutputSchema [
	"A changed tools/list contract is fetched again for the next call."
	| definition response |
	self connectWithToolsCapability.
	definition := self toolDefinitionNamed: 'probe'.
	transport enqueueResponse:
		(EsOrderedDictionary with: 'tools' -> (Array with: definition)).
	client listTools.
	client handleNotificationMethod: 'notifications/tools/list_changed'
		params: EsOrderedDictionary new.
	definition at: 'outputSchema' put:
		(EsOrderedDictionary with: '$ref' -> '#/missing').
	response := self textToolResult: 'value' isError: false.
	response at: 'structuredContent' put: EsOrderedDictionary new.
	transport enqueueResponse: response.
	transport enqueueResponse:
		(EsOrderedDictionary with: 'tools' -> (Array with: definition)).
	self should: [client callTool: 'probe' arguments: nil] raise: Error.
	self assert: (transport requests last at: 'method') equals: 'tools/list'

]

{ #category : 'Testing' }
TestMcpClientTools >> testToolWithArrayOutputSchemaAcceptsArrayStructuredContent [
	"Per MCP 2026-07-28 SEP-2106, clients accept non-keyed structuredContent conforming to outputSchema."

	| definition response result users outputSchema |

	self connectWithToolsCapability.
	outputSchema :=
		EsOrderedDictionary new
			at: 'type' put: 'array';
			at: 'items' put: (
				EsOrderedDictionary new
					at: 'type' put: 'object';
					at: 'properties' put: (
						EsOrderedDictionary with: 'id' -> (EsOrderedDictionary with: 'type' -> 'string'));
					yourself);
			yourself.
	definition := self toolDefinitionNamed: 'list_users'.
	definition at: 'outputSchema' put: outputSchema.
	users := Array with: (EsOrderedDictionary with: 'id' -> 'user-1').

	response := self textToolResult: 'Alice' isError: false.
	response at: 'structuredContent' put: users.

	transport enqueueResponse: response.
	transport enqueueResponse: (EsOrderedDictionary with: 'tools' -> (Array with: definition)).

	result := client callTool: 'list_users' arguments: nil.
	self assert: (result at: 'isError') equals: false.
	self assert: ((result at: 'structuredContent') isKindOf: SequenceableCollection).
	self assert: ((result at: 'structuredContent') first at: 'id') equals: 'user-1'
]

{ #category : 'Testing' }
TestMcpClientTools >> testValidateToolDefinitionAllowsArbitraryNames [
	"Verify that client allows arbitrary tool names, ignoring the SHOULD guideline for characters."

	| tool validator |
	validator := McpClient new.

	tool := EsOrderedDictionary new
		at: 'name' put: 'tool:with/slash and space';
		at: 'description' put: 'A test';
		at: 'inputSchema' put: (EsOrderedDictionary with: 'type' -> 'object');
		yourself.

	self shouldnt: [validator validateToolDefinition: tool] raise: Error
]

{ #category : 'Testing' }
TestMcpClientTools >> testValidateToolDefinitionRejectsMalformedParamHeaders [
	"Verify that client rejects tools with invalid x-mcp-header constraints."

	| tool schemaProps validator |
	validator := McpClient new.

	schemaProps := EsOrderedDictionary new
		at: 'param1' put: (
			EsOrderedDictionary new
				at: 'type' put: 'string';
				at: 'x-mcp-header' put: 123;
				yourself);
		yourself.

	tool := EsOrderedDictionary new
		at: 'name' put: 'test_tool';
		at: 'description' put: 'A test';
		at: 'inputSchema' put: (
			EsOrderedDictionary new
				at: 'type' put: 'object';
				at: 'properties' put: schemaProps;
				yourself);
		yourself.

	self should: [validator validateToolDefinition: tool] raise: Error.

	(schemaProps at: 'param1') at: 'x-mcp-header' put: ''.
	self should: [validator validateToolDefinition: tool] raise: Error.

	(schemaProps at: 'param1') at: 'x-mcp-header' put: 'invalid header! '.
	self should: [validator validateToolDefinition: tool] raise: Error.

	(schemaProps at: 'param1')
		at: 'type' put: 'object';
		at: 'x-mcp-header' put: 'Valid-Header'.
	self should: [validator validateToolDefinition: tool] raise: Error.

	(schemaProps at: 'param1')
		at: 'type' put: 'string';
		at: 'x-mcp-header' put: 'Valid-Header'.
	self shouldnt: [validator validateToolDefinition: tool] raise: Error
]

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpClientTools >> textToolResult: text isError: isError [
	"Answer a CallToolResult containing one text block."

	| content |

	content :=
		EsOrderedDictionary new
			at: 'type' put: 'text';
			at: 'text' put: text;
			yourself.
	^EsOrderedDictionary new
		at: 'content' put: (Array with: content);
		at: 'isError' put: isError;
		yourself
]

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpClientTools >> toolDefinitionNamed: toolName [
	"Answer a minimally valid MCP tool definition."

	^EsOrderedDictionary new
		at: 'name' put: toolName;
		at: 'inputSchema' put: (EsOrderedDictionary with: 'type' -> 'object');
		yourself
]
