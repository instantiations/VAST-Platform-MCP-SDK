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
	"Verify client drives multi-round-trip loop when resolver requests input."

	| tool result |

	tool :=
		McpBlockTool new
			name: 'ask_qty';
			inputSchema: (EsOrderedDictionary with: 'type' -> 'object');
			resolve: 'quantity'
				with: [:ctx :args | McpElicit message: 'How many?'];
			block: [:args | | qty |
				qty := (args at: 'quantity' ifAbsent: [EsOrderedDictionary new]) at: 'content' ifAbsent: [args at: 'quantity'].
				'Ordered ' , qty printString];
			yourself.
	server toolRegistry registerTool: tool.

	client elicitationCallback: [:request :name | EsOrderedDictionary with: 'action' -> 'accept' with: 'content' -> 7].
	result := client callTool: 'ask_qty' arguments: EsOrderedDictionary new.

	self assert: (result at: 'isError') equals: false.
	self assert: (((result at: 'content') first) at: 'text') equals: 'Ordered 7'
]

{ #category : 'Testing' }
TestMcpToolResolvers >> testElicitResolverYieldsInputRequired [
	"Verify resolver returning McpElicit yields InputRequiredResult when unhandled."

	| tool result |

	tool :=
		McpBlockTool new
			name: 'ask_age';
			inputSchema: (EsOrderedDictionary with: 'type' -> 'object');
			resolve: 'age' with: [:ctx :args | McpElicit message: 'What is your age?'];
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
	self assert: (((result at: 'inputRequests') at: 'age') at: 'method') equals: 'elicitation/create'.
	self assert: (result at: 'requestState') notNil
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
