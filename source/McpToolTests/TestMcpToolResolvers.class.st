Class {
	#name : 'TestMcpToolResolvers',
	#superclass : 'TestCase',
	#instVars : [
		'server',
		'client'
	],
	#pools : [
		'McpJsonRpcConstants'
	],
	#category : 'McpToolTests'
}

{ #category : 'Running' }
TestMcpToolResolvers >> setUp [
	"Prepare the test server and in-memory client."

	super setUp.
	server := McpServer new.
	client := McpClient forServer: server.
	client connect
]

{ #category : 'Running' }
TestMcpToolResolvers >> tearDown [
	"Shut down client and clean up."

	client ifNotNil: [client close].
	super tearDown
]

{ #category : 'Testing' }
TestMcpToolResolvers >> testClientAnswersElicitResolver [
	"Verify client drives multi-round-trip loop when resolver requests input with an explicit schema."

	| tool elicitSchema result |

	elicitSchema :=
		EsOrderedDictionary new
			at: 'type' put: 'object';
			at: 'properties'
				put: (
					EsOrderedDictionary
						with: 'quantity' -> (EsOrderedDictionary with: 'type' -> 'integer'));
			at: 'required' put: #('quantity');
			yourself.
	tool :=
		McpBlockTool new
			name: 'ask_qty';
			inputSchema: (EsOrderedDictionary with: 'type' -> 'object');
			resolve: 'quantity'
				with: [:ctx :args | McpElicit message: 'How many?' schema: elicitSchema];
			block: [:args | | resp content qty |
				resp := args at: 'quantity' ifAbsent: [EsOrderedDictionary new].
				content := resp at: 'content' ifAbsent: [EsOrderedDictionary new].
				qty := content at: 'quantity'.
				'Ordered ' , qty printString];
			yourself.
	server toolRegistry registerTool: tool.

	client elicitationCallback: [:request :cl |
		EsOrderedDictionary
			with: 'action' -> 'accept'
			with: 'content' -> (EsOrderedDictionary with: 'quantity' -> 7)].
	result := client callTool: 'ask_qty' arguments: EsOrderedDictionary new.

	self assert: (result at: 'isError') equals: false.
	self assert: (((result at: 'content') first) at: 'text') equals: 'Ordered 7'
]

{ #category : 'Testing' }
TestMcpToolResolvers >> testClientAppliesElicitationSchemaDefaults [
	"Verify McpClient pre-populates missing content fields from requestedSchema property defaults on accept."

	| schema wire response content |

	schema :=
		EsOrderedDictionary new
			at: 'type' put: 'object';
			at: 'properties'
				put: (
					EsOrderedDictionary
						with:
							'name' -> (
								EsOrderedDictionary
									with: 'type' -> 'string'
									with: 'default' -> 'DefaultName')
						with:
							'count' -> (
								EsOrderedDictionary
									with: 'type' -> 'integer'
									with: 'default' -> 42));
			yourself.
	wire := (McpElicit message: 'Provide defaults' schema: schema) asInputRequest.
	client elicitationCallback: [:req :c |
		EsOrderedDictionary
			with: 'action' -> 'accept'
			with: 'content' -> (EsOrderedDictionary with: 'count' -> 10)].

	response := client perform: #dispatchInputRequest:named: with: wire with: 'defaults'.
	content := response at: 'content'.
	self assert: (content at: 'name') equals: 'DefaultName'.
	self assert: (content at: 'count') equals: 10
]

{ #category : 'Testing' }
TestMcpToolResolvers >> testClientRejectsElicitationWithoutRequestedSchema [
	"Verify McpClient validates requestedSchema on incoming elicitation/create requests."

	| badRequest |

	client elicitationCallback: [:req :c |
		EsOrderedDictionary with: 'action' -> 'accept' with: 'content' -> EsOrderedDictionary new].
	badRequest :=
		EsOrderedDictionary new
			at: 'method' put: 'elicitation/create';
			at: 'params' put: (EsOrderedDictionary with: 'message' -> 'Missing schema');
			yourself.
	self
		should: [client perform: #dispatchInputRequest:named: with: badRequest with: 'test']
		raise: McpJsonRpcError
]

{ #category : 'Testing' }
TestMcpToolResolvers >> testElicitRejectsInvalidSchema [
	"Verify McpElicit enforces a flat object schema with primitive/enum properties for form mode."

	| nestedObjectSchema |

	self should: [McpElicit message: 'Prompt' schema: nil] raise: Error.
	self
		should: [
			McpElicit
				message: 'Prompt'
				schema: (EsOrderedDictionary with: 'type' -> 'string')]
		raise: Error.
	nestedObjectSchema :=
		EsOrderedDictionary new
			at: 'type' put: 'object';
			at: 'properties'
				put: (
					EsOrderedDictionary
						with: 'nested' -> (EsOrderedDictionary with: 'type' -> 'object'));
			yourself.
	self should: [McpElicit message: 'Prompt' schema: nestedObjectSchema] raise: Error
]

{ #category : 'Testing' }
TestMcpToolResolvers >> testElicitResolverYieldsInputRequired [
	"Verify resolver returning McpElicit yields InputRequiredResult with its explicit requestedSchema."

	| tool elicitSchema result req params schema props |

	elicitSchema :=
		EsOrderedDictionary new
			at: 'type' put: 'object';
			at: 'properties'
				put: (
					EsOrderedDictionary
						with: 'age' -> (EsOrderedDictionary with: 'type' -> 'integer'));
			at: 'required' put: #('age');
			yourself.
	tool :=
		McpBlockTool new
			name: 'ask_age';
			inputSchema: (EsOrderedDictionary with: 'type' -> 'object');
			resolve: 'age'
				with: [:ctx :args | McpElicit message: 'What is your age?' schema: elicitSchema];
			block: [:args | 'Age is ' , (args at: 'age') printString];
			yourself.
	server toolRegistry registerTool: tool.

	result :=
		server toolsCall: (
			EsOrderedDictionary new
				at: 'name' put: 'ask_age';
				at: 'arguments' put: EsOrderedDictionary new;
				yourself).
	self assert: (result at: 'resultType') equals: 'input_required'.
	self assert: ((result at: 'inputRequests') includesKey: 'age').
	req := (result at: 'inputRequests') at: 'age'.
	self assert: (req at: 'method') equals: 'elicitation/create'.
	params := req at: 'params'.
	self assert: (params at: 'mode') equals: 'form'.
	schema := params at: 'requestedSchema' ifAbsent: [nil].
	self assert: (schema isKindOf: KeyedCollection).
	self assert: (schema at: 'type' ifAbsent: [nil]) equals: 'object'.
	props := schema at: 'properties' ifAbsent: [nil].
	self assert: ((props isKindOf: KeyedCollection) and: [props includesKey: 'age']).
	self assert: (result at: 'requestState') notNil
]

{ #category : 'Testing' }
TestMcpToolResolvers >> testElicitUrlModeRequest [
	"Verify McpElicit URL mode produces a valid url-mode elicitation/create wire request."

	| elicit wire params response |

	elicit :=
		McpElicit
			message: 'Please provide your API key to continue.'
			url: 'https://mcp.example.com/ui/set_api_key'.
	self assert: elicit mode equals: 'url'.
	self assert: elicit url equals: 'https://mcp.example.com/ui/set_api_key'.
	self assert: elicit schema isNil.

	wire := elicit asInputRequest.
	self assert: (wire at: 'method') equals: 'elicitation/create'.
	params := wire at: 'params'.
	self assert: (params at: 'mode') equals: 'url'.
	self assert: (params at: 'url') equals: 'https://mcp.example.com/ui/set_api_key'.
	self assert: (params at: 'message') equals: 'Please provide your API key to continue.'.
	self deny: (params includesKey: 'requestedSchema').

	client elicitationCallback: [:req :c | EsOrderedDictionary with: 'action' -> 'accept'].
	response := client perform: #dispatchInputRequest:named: with: wire with: 'api_key'.
	self assert: (response at: 'action') equals: 'accept'
]

{ #category : 'Testing' }
TestMcpToolResolvers >> testLegacyClientHandlesServerElicitationRequest [
	"Verify legacy McpClient dispatches server-initiated elicitation/create via elicitationCallback and applies defaults."

	| legacyClient scriptedTransport schema request sentResponse resultPayload |

	scriptedTransport := McpScriptedClientTransport new.
	legacyClient := McpClient legacy.
	legacyClient transport: scriptedTransport.
	legacyClient elicitationCallback: [:req :c |
		EsOrderedDictionary
			with: 'action' -> 'accept'
			with: 'content' -> EsOrderedDictionary new].
	schema :=
		EsOrderedDictionary new
			at: 'type' put: 'object';
			at: 'properties'
				put: (
					EsOrderedDictionary
						with: 'role' -> (
							EsOrderedDictionary
								with: 'type' -> 'string'
								with: 'default' -> 'viewer'));
			yourself.
	request :=
		EsOrderedDictionary new
			at: 'jsonrpc' put: '2.0';
			at: 'id' put: 'srv-1';
			at: 'method' put: 'elicitation/create';
			at: 'params'
				put: (
					EsOrderedDictionary
						with: 'message' -> 'Choose role'
						with: 'requestedSchema' -> schema);
			yourself.
	legacyClient handleIncomingMessage: request.
	self assert: scriptedTransport notifications size equals: 1.
	sentResponse := scriptedTransport notifications first.
	self assert: (sentResponse at: 'id') equals: 'srv-1'.
	resultPayload := sentResponse at: 'result'.
	self assert: (resultPayload at: 'action') equals: 'accept'.
	self assert: ((resultPayload at: 'content') at: 'role') equals: 'viewer'
]

{ #category : 'Testing' }
TestMcpToolResolvers >> testMcpToolErrorSignalsToolFailure [
	"Verify signaling McpToolError returns a structured error result with its message."

	| tool result |

	tool :=
		McpBlockTool new
			name: 'fail_tool';
			inputSchema: (EsOrderedDictionary with: 'type' -> 'object');
			block: [:args | McpToolError signal: 'Custom tool error message'];
			yourself.
	server toolRegistry registerTool: tool.

	result := client callTool: 'fail_tool' arguments: EsOrderedDictionary new.

	self assert: (result at: 'isError') equals: true.
	self assert: (((result at: 'content') first) at: 'text') equals: 'Custom tool error message'
]

{ #category : 'Testing' }
TestMcpToolResolvers >> testStaticResolver [
	"Verify static parameter resolver injects computed value before tool execution."

	| tool result |

	tool :=
		McpBlockTool new
			name: 'greet';
			inputSchema: (EsOrderedDictionary with: 'type' -> 'object');
			resolve: 'greeting' with: [:ctx :args | 'Hello, Smalltalk!'];
			block: [:args | args at: 'greeting'];
			yourself.
	server toolRegistry registerTool: tool.

	result := client callTool: 'greet' arguments: EsOrderedDictionary new.
	self assert: (result at: 'isError') equals: false.
	self assert: (((result at: 'content') first) at: 'text') equals: 'Hello, Smalltalk!'
]
