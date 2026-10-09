"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# TestMcpCompletion

`TestMcpCompletion` tests MCP `completion/complete` request dispatch,
capability advertisement, prompt and resource template autocompletion handlers,
and 100-item truncation limits.
"
Class {
	#name : 'TestMcpCompletion',
	#superclass : 'TestCase',
	#instVars : [
		'server',
		'dispatcher',
		'client',
		'transport'
	],
	#pools : [
		'McpJsonRpcConstants'
	],
	#category : 'McpProtocolTests'
}

{ #category : 'Running' }
TestMcpCompletion >> setUp [
	"Prepare MCP completion test fixtures.

	 Answers:
		<TestMcpCompletion> the receiver."

	super setUp.
	server := McpServer new.
	dispatcher := McpJsonRpcDispatcher new.
	dispatcher server: server.
	transport := McpScriptedClientTransport new.
	client := McpClient new.
	client transport: transport.
	^self
]

{ #category : 'Running' }
TestMcpCompletion >> tearDown [
	"Clean up test fixtures.

	 Answers:
		<TestMcpCompletion> the receiver."

	client ifNotNil: [[client close] on: Error do: [:closeError | closeError return: nil]].
	super tearDown
]

{ #category : 'Testing' }
TestMcpCompletion >> testClientCompletePrompt [
	"Verify client completePrompt:argument:value: against scripted transport."

	| scriptedResponse completion |

	client instVarNamed: 'isConnected' put: true.
	client instVarNamed: 'serverCapabilities' put: (Dictionary with: 'completions' -> Dictionary new).

	scriptedResponse :=
		EsOrderedDictionary with:
			'completion' -> (
				EsOrderedDictionary new
					at: 'values' put: #('argVal1' 'argVal2');
					at: 'total' put: 2;
					at: 'hasMore' put: false;
					yourself).
	transport enqueueResponse: scriptedResponse.

	completion := client completePrompt: 'review' argument: 'style' value: 'pe'.
	self assert: (completion at: 'values') asArray = #('argVal1' 'argVal2').
	self assert: (completion at: 'total') = 2.
	self assert: (completion at: 'hasMore') = false.

	self assert: (transport requests last at: 'method') = 'completion/complete'
]

{ #category : 'Testing' }
TestMcpCompletion >> testClientCompleteResource [
	"Verify client completeResource:argument:value: against scripted transport."

	| scriptedResponse completion |

	client instVarNamed: 'isConnected' put: true.
	client instVarNamed: 'serverCapabilities' put: (Dictionary with: 'completions' -> Dictionary new).

	scriptedResponse :=
		EsOrderedDictionary with:
			'completion' -> (
				EsOrderedDictionary new
					at: 'values' put: #('main' 'develop');
					yourself).
	transport enqueueResponse: scriptedResponse.

	completion :=
		client
			completeResource: 'git://{branch}/log'
			argument: 'branch'
			value: 'm'
			context: (Dictionary with: 'arguments' -> (Dictionary with: 'repo' -> 'vast')).

	self assert: (completion at: 'values') asArray = #('main' 'develop').
	self assert: (transport requests last at: 'method') = 'completion/complete'
]

{ #category : 'Testing' }
TestMcpCompletion >> testClientRejectsMissingCompletionsCapability [
	"Verify that client requires the completions capability before sending completion/complete."

	client instVarNamed: 'isConnected' put: true.
	client instVarNamed: 'serverCapabilities' put: (Dictionary with: 'prompts' -> Dictionary new).

	self should: [client completePrompt: 'review' argument: 'style' value: 'pe'] raise: Error
]

{ #category : 'Testing' }
TestMcpCompletion >> testCompletionLimitsTo100Values [
	"Verify that server truncates completion values to 100 items maximum."

	| request response completion values |

	server completionBlock: [:ref :arg :ctx | (1 to: 150) collect: [:i | 'val' , i printString]].

	request :=
		EsOrderedDictionary new
			at: 'jsonrpc' put: '2.0';
			at: 'id' put: 6;
			at: 'method' put: 'completion/complete';
			at: 'params'
				put: (
					EsOrderedDictionary new
						at: 'ref'
							put: (
								EsOrderedDictionary
									with: 'type' -> 'ref/prompt'
									with: 'name' -> 'test');
						at: 'argument'
							put: (EsOrderedDictionary with: 'name' -> 'item' with: 'value' -> '');
						yourself);
			yourself.

	response := dispatcher dispatch: request.
	self assert: (response includesKey: 'result').
	completion := (response at: 'result') at: 'completion'.
	values := completion at: 'values'.
	self assert: values size = 100
]

{ #category : 'Testing' }
TestMcpCompletion >> testCompletionResultIncludesResultType [
	"Verify that modern complete results carry resultType: 'complete'."

	| request response |

	server completionBlock: [:ref :arg :ctx | #('val')].

	request :=
		EsOrderedDictionary new
			at: 'jsonrpc' put: '2.0';
			at: 'id' put: 7;
			at: 'method' put: 'completion/complete';
			at: 'params'
				put: (
					EsOrderedDictionary new
						at: '_meta' put: (EsOrderedDictionary with: 'io.modelcontextprotocol/protocolVersion' -> '2026-07-28');
						at: 'ref'
							put: (
								EsOrderedDictionary
									with: 'type' -> 'ref/prompt'
									with: 'name' -> 'test');
						at: 'argument'
							put: (EsOrderedDictionary with: 'name' -> 'item' with: 'value' -> '');
						yourself);
			yourself.

	response := dispatcher dispatch: request.
	self assert: (response includesKey: 'result').
	self assert: ((response at: 'result') at: 'resultType') = 'complete'
]

{ #category : 'Testing' }
TestMcpCompletion >> testServerAdvertisesCompletionsCapability [
	"Verify that McpServer advertises the completions capability."

	self assert: (server capabilities includesKey: 'completions')
]

{ #category : 'Testing' }
TestMcpCompletion >> testServerGlobalCompletionHandler [
	"Verify that a server-level completionBlock handles completion/complete."

	| request response completion values |

	server completionBlock: [:ref :arg :ctx |
		#('alpha' 'beta' 'gamma')
			select: [:each | (each indexOfSubCollection: (arg at: 'value') startingAt: 1) = 1]].

	request :=
		EsOrderedDictionary new
			at: 'jsonrpc' put: '2.0';
			at: 'id' put: 1;
			at: 'method' put: 'completion/complete';
			at: 'params'
				put: (
					EsOrderedDictionary new
						at: 'ref'
							put: (
								EsOrderedDictionary
									with: 'type' -> 'ref/prompt'
									with: 'name' -> 'test');
						at: 'argument'
							put: (EsOrderedDictionary with: 'name' -> 'item' with: 'value' -> 'be');
						yourself);
			yourself.

	response := dispatcher dispatch: request.
	self assert: (response includesKey: 'result').
	completion := (response at: 'result') at: 'completion'.
	values := completion at: 'values'.
	self assert: values asArray = #('beta')
]

{ #category : 'Testing' }
TestMcpCompletion >> testServerPromptCompletion [
	"Verify that a prompt's completionBlock is invoked for ref/prompt."

	| prompt request response completion values |

	prompt :=
		McpBlockPrompt new
			name: 'code_review';
			description: 'Review code';
			arguments: (
				Array with: (EsOrderedDictionary with: 'name' -> 'language' with: 'required' -> true));
			completionBlock: [:argName :val :ctx |
				#('python' 'javascript' 'smalltalk')
					select: [:each | (each indexOfSubCollection: val startingAt: 1) = 1]];
			yourself.
	server promptRegistry registerPrompt: prompt.

	request :=
		EsOrderedDictionary new
			at: 'jsonrpc' put: '2.0';
			at: 'id' put: 2;
			at: 'method' put: 'completion/complete';
			at: 'params'
				put: (
					EsOrderedDictionary new
						at: 'ref'
							put: (
								EsOrderedDictionary
									with: 'type' -> 'ref/prompt'
									with: 'name' -> 'code_review');
						at: 'argument'
							put: (
								EsOrderedDictionary with: 'name' -> 'language' with: 'value' -> 'sm');
						yourself);
			yourself.

	response := dispatcher dispatch: request.
	self assert: (response includesKey: 'result').
	completion := (response at: 'result') at: 'completion'.
	values := completion at: 'values'.
	self assert: values asArray = #('smalltalk')
]

{ #category : 'Testing' }
TestMcpCompletion >> testServerResourceTemplateCompletion [
	"Verify that a resource template's completionBlock is invoked for ref/resource."

	| template request response completion values |

	template :=
		McpBlockResourceTemplate new
			uriTemplate: 'memo://{category}/{id}';
			name: 'memos';
			completionBlock: [:varName :val :ctx |
				varName = 'category'
					ifTrue: [
						#('work' 'personal' 'finance')
							select: [:each | (each indexOfSubCollection: val startingAt: 1) = 1]]
					ifFalse: [#()]];
			yourself.
	server resourceTemplateRegistry registerTemplate: template.

	request :=
		EsOrderedDictionary new
			at: 'jsonrpc' put: '2.0';
			at: 'id' put: 3;
			at: 'method' put: 'completion/complete';
			at: 'params'
				put: (
					EsOrderedDictionary new
						at: 'ref'
							put: (
								EsOrderedDictionary
									with: 'type' -> 'ref/resource'
									with: 'uri' -> 'memo://{category}/{id}');
						at: 'argument'
							put: (
								EsOrderedDictionary with: 'name' -> 'category' with: 'value' -> 'fi');
						yourself);
			yourself.

	response := dispatcher dispatch: request.
	self assert: (response includesKey: 'result').
	completion := (response at: 'result') at: 'completion'.
	values := completion at: 'values'.
	self assert: values asArray = #('finance')
]

{ #category : 'Testing' }
TestMcpCompletion >> testServerUnknownPromptSignalsInvalidParams [
	"Verify that asking for completions on an unknown prompt raises JSON-RPC -32602."

	| request response |

	request :=
		EsOrderedDictionary new
			at: 'jsonrpc' put: '2.0';
			at: 'id' put: 4;
			at: 'method' put: 'completion/complete';
			at: 'params'
				put: (
					EsOrderedDictionary new
						at: 'ref'
							put: (
								EsOrderedDictionary
									with: 'type' -> 'ref/prompt'
									with: 'name' -> 'nonexistent');
						at: 'argument'
							put: (EsOrderedDictionary with: 'name' -> 'arg' with: 'value' -> 'val');
						yourself);
			yourself.

	response := dispatcher dispatch: request.
	self assert: (response includesKey: 'error').
	self assert: ((response at: 'error') at: 'code') = McpJsonRpcInvalidParamsCode
]

{ #category : 'Testing' }
TestMcpCompletion >> testServerUnknownResourceTemplateSignalsInvalidParams [
	"Verify that asking for completions on an unknown template raises JSON-RPC -32602."

	| request response |

	request :=
		EsOrderedDictionary new
			at: 'jsonrpc' put: '2.0';
			at: 'id' put: 5;
			at: 'method' put: 'completion/complete';
			at: 'params'
				put: (
					EsOrderedDictionary new
						at: 'ref'
							put: (
								EsOrderedDictionary
									with: 'type' -> 'ref/resource'
									with: 'uri' -> 'unknown://template');
						at: 'argument'
							put: (EsOrderedDictionary with: 'name' -> 'arg' with: 'value' -> 'val');
						yourself);
			yourself.

	response := dispatcher dispatch: request.
	self assert: (response includesKey: 'error').
	self assert: ((response at: 'error') at: 'code') = McpJsonRpcInvalidParamsCode
]
