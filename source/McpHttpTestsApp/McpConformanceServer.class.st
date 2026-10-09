Class {
	#name : 'McpConformanceServer',
	#superclass : 'Object',
	#instVars : [
		'httpServer',
		'mcpServer',
		'port',
		'host'
	],
	#category : 'McpHttpTestsApp'
}

{ #category : 'Instance Creation' }
McpConformanceServer class >> defaultPort [
	"Answer the standard port used by the MCP conformance test suite.

	 Answers:
		<Integer> 3000."

	^3000
]

{ #category : 'Instance Creation' }
McpConformanceServer class >> new [
	"Answer a new initialized conformance test server.

	 Answers:
		<McpConformanceServer>."

	^super new initialize
]

{ #category : 'Instance Creation' }
McpConformanceServer class >> onPort: aPortNumber [
	"Answer a new conformance test server configured on aPortNumber.

	 Arguments:
		aPortNumber - <Integer>.
	 Answers:
		<McpConformanceServer>."

	^self new
		port: aPortNumber;
		yourself
]

{ #category : 'Instance Creation' }
McpConformanceServer class >> startOnPort: aPortNumber [
	"Start and answer a new conformance test server on aPortNumber.

	 Arguments:
		aPortNumber - <Integer>.
	 Answers:
		<McpConformanceServer>."

	^(self onPort: aPortNumber)
		start;
		yourself
]

{ #category : 'Fixtures' }
McpConformanceServer >> base64PngPixel [
	"Answer a base64-encoded 1x1 PNG image as required by tools-call-image.

	 Answers:
		<String>."

	^'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='
]

{ #category : 'Fixtures' }
McpConformanceServer >> base64WavAudio [
	"Answer a base64-encoded minimal audio/wav as required by tools-call-audio.

	 Answers:
		<String>."

	^'UklGRigAAABXQVZFZm10IBAAAAABAAEARKwAAIhYAQACABAAZGF0YQQAAAAAAA=='
]

{ #category : 'Configuration' }
McpConformanceServer >> configureServer [
	"Build and populate the MCP server with all standard conformance fixtures.

	 Answers:
		<McpServer>."

	mcpServer :=
		McpServer new
			name: 'mcp-conformance-server';
			version: '1.0.0';
			yourself.
	self registerTools.
	self registerResources.
	self registerPrompts.
	self registerCompletions.
	^mcpServer
]

{ #category : 'Accessing' }
McpConformanceServer >> host [
	"Answer the listener host address.

	 Answers:
		<String>."

	^host ifNil: [host := '127.0.0.1']
]

{ #category : 'Accessing' }
McpConformanceServer >> host: aString [
	"Set the listener host address.

	 Arguments:
		aString - <String>.
	 Answers:
		<McpConformanceServer> the receiver."

	host := aString copy.
	^self
]

{ #category : 'Initialization' }
McpConformanceServer >> initialize [
	"Initialize default host and port.

	 Answers:
		<McpConformanceServer> the receiver."

	super initialize.
	host := '127.0.0.1'.
	port := self class defaultPort.
	^self
]

{ #category : 'Testing' }
McpConformanceServer >> isRunning [
	"Answer whether the HTTP listener is currently active.

	 Answers:
		<Boolean>."

	^httpServer notNil and: [httpServer isRunning]
]

{ #category : 'Accessing' }
McpConformanceServer >> mcpServer [
	"Answer the underlying McpServer instance.

	 Answers:
		<McpServer>."

	mcpServer ifNil: [self configureServer].
	^mcpServer
]

{ #category : 'Accessing' }
McpConformanceServer >> port [
	"Answer the HTTP listener port.

	 Answers:
		<Integer>."

	^port ifNil: [port := self class defaultPort]
]

{ #category : 'Accessing' }
McpConformanceServer >> port: anInteger [
	"Set the HTTP listener port.

	 Arguments:
		anInteger - <Integer>.
	 Answers:
		<McpConformanceServer> the receiver."

	port := anInteger.
	^self
]

{ #category : 'Configuration' }
McpConformanceServer >> registerCompletions [
	"Configure completion fallback handling on the server."

	mcpServer completionBlock: [:ref :argument :context :server | | argName prefix |
		argName := argument at: 'name' ifAbsent: [''].
		prefix := argument at: 'value' ifAbsent: [''].
		argName = 'arg1'
			ifTrue: [
				#('paris' 'park' 'party' 'test' 'testing') select: [:candidate |
					(candidate indexOfSubCollection: prefix startingAt: 1) = 1]]
			ifFalse: [
				#('test1' 'test2') select: [:candidate |
					(candidate indexOfSubCollection: prefix startingAt: 1) = 1]]]
]

{ #category : 'Configuration',
  #vaVisibility : 'private' }
McpConformanceServer >> registerMrtrToolsOn: reg [
	"Register all SEP-2322 MRTR (Multi-Round-Trip Request) tools for both server and client testing."

	reg registerTool: (
		McpBlockTool new
			name: 'test_input_required_result_elicitation';
			description: 'MRTR basic elicitation test tool';
			inputSchema: (EsOrderedDictionary with: 'type' -> 'object');
			block: [:args :ctx | | responses |
				responses := ctx ifNotNil: [:c | c inputResponses].
				(responses notNil and: [responses includesKey: 'user_name'])
					ifTrue: [| name |
						name :=
							((responses at: 'user_name') at: 'content' ifAbsent: [EsOrderedDictionary new])
								at: 'name'
								ifAbsent: ['friend'].
						EsOrderedDictionary with: 'content' -> (Array with: (
							EsOrderedDictionary
								with: 'type' -> 'text'
								with: 'text' -> ('Hello, ' , name , '!')))]
					ifFalse: [| req schema |
						schema :=
							EsOrderedDictionary new
								at: 'type' put: 'object';
								at: 'properties' put: (
									EsOrderedDictionary with: 'name' -> (
										EsOrderedDictionary with: 'type' -> 'string'));
								at: 'required' put: #('name');
								yourself.
						req :=
							EsOrderedDictionary new
								at: 'method' put: 'elicitation/create';
								at: 'params' put: (
									EsOrderedDictionary
										with: 'message' -> 'What is your name?'
										with: 'requestedSchema' -> schema);
								yourself.
						EsOrderedDictionary new
							at: 'resultType' put: 'input_required';
							at: 'inputRequests' put: (EsOrderedDictionary with: 'user_name' -> req);
							yourself]];
			yourself).

	reg registerTool: (
		McpBlockTool new
			name: 'test_input_required_result_sampling';
			description: 'MRTR basic sampling test tool';
			inputSchema: (EsOrderedDictionary with: 'type' -> 'object');
			block: [:args :ctx | | responses |
				responses := ctx ifNotNil: [:c | c inputResponses].
				(responses notNil and: [responses includesKey: 'capital_question'])
					ifTrue: [| sampleText |
						sampleText :=
							((responses at: 'capital_question') at: 'content' ifAbsent: [EsOrderedDictionary new])
								at: 'text'
								ifAbsent: ['Paris'].
						EsOrderedDictionary with: 'content' -> (Array with: (
							EsOrderedDictionary with: 'type' -> 'text' with: 'text' -> sampleText))]
					ifFalse: [| req msg |
						msg :=
							EsOrderedDictionary
								with: 'role' -> 'user'
								with: 'content' -> (
									EsOrderedDictionary
										with: 'type' -> 'text'
										with: 'text' -> 'What is the capital of France?').
						req :=
							EsOrderedDictionary new
								at: 'method' put: 'sampling/createMessage';
								at: 'params' put: (
									EsOrderedDictionary
										with: 'messages' -> (Array with: msg)
										with: 'maxTokens' -> 100);
								yourself.
						EsOrderedDictionary new
							at: 'resultType' put: 'input_required';
							at: 'inputRequests' put: (EsOrderedDictionary with: 'capital_question' -> req);
							yourself]];
			yourself).

	reg registerTool: (
		McpBlockTool new
			name: 'test_input_required_result_list_roots';
			description: 'MRTR basic list_roots test tool';
			inputSchema: (EsOrderedDictionary with: 'type' -> 'object');
			block: [:args :ctx | | responses |
				responses := ctx ifNotNil: [:c | c inputResponses].
				(responses notNil and: [responses includesKey: 'client_roots'])
					ifTrue: [
						EsOrderedDictionary with: 'content' -> (Array with: (
							EsOrderedDictionary
								with: 'type' -> 'text'
								with: 'text' -> 'Roots received successfully.'))]
					ifFalse: [| req |
						req :=
							EsOrderedDictionary new
								at: 'method' put: 'roots/list';
								at: 'params' put: EsOrderedDictionary new;
								yourself.
						EsOrderedDictionary new
							at: 'resultType' put: 'input_required';
							at: 'inputRequests' put: (EsOrderedDictionary with: 'client_roots' -> req);
							yourself]];
			yourself).

	reg registerTool: (
		McpBlockTool new
			name: 'test_input_required_result_request_state';
			description: 'MRTR request state round-trip test tool';
			inputSchema: (EsOrderedDictionary with: 'type' -> 'object');
			block: [:args :ctx | | responses state |
				responses := ctx ifNotNil: [:c | c inputResponses].
				state := ctx ifNotNil: [:c | c requestState].
				(responses notNil and: [state notNil and: [state notEmpty]])
					ifTrue: [
						EsOrderedDictionary with: 'content' -> (Array with: (
							EsOrderedDictionary
								with: 'type' -> 'text'
								with: 'text' -> 'state-ok: validation passed'))]
					ifFalse: [| req schema |
						schema :=
							EsOrderedDictionary new
								at: 'type' put: 'object';
								at: 'properties' put: (
									EsOrderedDictionary with: 'ok' -> (
										EsOrderedDictionary with: 'type' -> 'boolean'));
								at: 'required' put: #('ok');
								yourself.
						req :=
							EsOrderedDictionary new
								at: 'method' put: 'elicitation/create';
								at: 'params' put: (
									EsOrderedDictionary
										with: 'message' -> 'Please confirm'
										with: 'requestedSchema' -> schema);
								yourself.
						EsOrderedDictionary new
							at: 'resultType' put: 'input_required';
							at: 'inputRequests' put: (EsOrderedDictionary with: 'confirm' -> req);
							at: 'requestState' put: 'test-opaque-state';
							yourself]];
			yourself).

	reg registerTool: (
		McpBlockTool new
			name: 'test_input_required_result_multiple_inputs';
			description: 'MRTR multiple inputs test tool';
			inputSchema: (EsOrderedDictionary with: 'type' -> 'object');
			block: [:args :ctx | | responses |
				responses := ctx ifNotNil: [:c | c inputResponses].
				(responses notNil
					and: [
						(responses includesKey: 'user_name')
							and: [
								(responses includesKey: 'greeting') and: [responses includesKey: 'client_roots']]])
									ifTrue: [
										EsOrderedDictionary with: 'content' -> (Array with: (
											EsOrderedDictionary with: 'type' -> 'text' with: 'text' -> 'All inputs received.'))]
									ifFalse: [| req1 req2 req3 schema msg |
										schema :=
											EsOrderedDictionary new
												at: 'type' put: 'object';
												at: 'properties' put: (
													EsOrderedDictionary with: 'name' -> (
														EsOrderedDictionary with: 'type' -> 'string'));
												at: 'required' put: #('name');
												yourself.
										req1 :=
											EsOrderedDictionary new
												at: 'method' put: 'elicitation/create';
												at: 'params' put: (
													EsOrderedDictionary
														with: 'message' -> 'What is your name?'
														with: 'requestedSchema' -> schema);
												yourself.
										msg :=
											EsOrderedDictionary
												with: 'role' -> 'user'
												with: 'content' -> (
													EsOrderedDictionary with: 'type' -> 'text' with: 'text' -> 'Generate a greeting').
										req2 :=
											EsOrderedDictionary new
												at: 'method' put: 'sampling/createMessage';
												at: 'params' put: (
													EsOrderedDictionary
														with: 'messages' -> (Array with: msg)
														with: 'maxTokens' -> 50);
												yourself.
										req3 :=
											EsOrderedDictionary new
												at: 'method' put: 'roots/list';
												at: 'params' put: EsOrderedDictionary new;
												yourself.
										EsOrderedDictionary new
											at: 'resultType' put: 'input_required';
											at: 'inputRequests' put: (
												EsOrderedDictionary new
													at: 'user_name' put: req1;
													at: 'greeting' put: req2;
													at: 'client_roots' put: req3;
													yourself);
											at: 'requestState' put: 'multi-state';
											yourself]];
			yourself).

	reg registerTool: (
		McpBlockTool new
			name: 'test_input_required_result_multi_round';
			description: 'MRTR multi-round test tool';
			inputSchema: (EsOrderedDictionary with: 'type' -> 'object');
			block: [:args :ctx | | state |
				state := ctx ifNotNil: [:c | c requestState].
				state = 'state-round-2'
					ifTrue: [
						EsOrderedDictionary with: 'content' -> (Array with: (
							EsOrderedDictionary with: 'type' -> 'text' with: 'text' -> 'Round 3 complete.'))]
					ifFalse: [
						state = 'state-round-1'
							ifTrue: [| req2 schema2 |
								schema2 :=
									EsOrderedDictionary new
										at: 'type' put: 'object';
										at: 'properties' put: (
											EsOrderedDictionary with: 'color' -> (
												EsOrderedDictionary with: 'type' -> 'string'));
										at: 'required' put: #('color');
										yourself.
								req2 :=
									EsOrderedDictionary new
										at: 'method' put: 'elicitation/create';
										at: 'params' put: (
											EsOrderedDictionary
												with: 'message' -> 'Step 2: What is your favorite color?'
												with: 'requestedSchema' -> schema2);
										yourself.
								EsOrderedDictionary new
									at: 'resultType' put: 'input_required';
									at: 'inputRequests' put: (EsOrderedDictionary with: 'step2' -> req2);
									at: 'requestState' put: 'state-round-2';
									yourself]
							ifFalse: [| req1 schema1 |
								schema1 :=
									EsOrderedDictionary new
										at: 'type' put: 'object';
										at: 'properties' put: (
											EsOrderedDictionary with: 'name' -> (
												EsOrderedDictionary with: 'type' -> 'string'));
										at: 'required' put: #('name');
										yourself.
								req1 :=
									EsOrderedDictionary new
										at: 'method' put: 'elicitation/create';
										at: 'params' put: (
											EsOrderedDictionary
												with: 'message' -> 'Step 1: What is your name?'
												with: 'requestedSchema' -> schema1);
										yourself.
								EsOrderedDictionary new
									at: 'resultType' put: 'input_required';
									at: 'inputRequests' put: (EsOrderedDictionary with: 'step1' -> req1);
									at: 'requestState' put: 'state-round-1';
									yourself]]];
			yourself).

	reg registerTool: (
		McpBlockTool new
			name: 'test_input_required_result_tampered_state';
			description: 'MRTR tampered state verification test tool';
			inputSchema: (EsOrderedDictionary with: 'type' -> 'object');
			block: [:args :ctx | | responses state |
				responses := ctx ifNotNil: [:c | c inputResponses].
				state := ctx ifNotNil: [:c | c requestState].
				(responses notNil and: [state notNil])
					ifTrue: [
						((state indexOfSubCollection: 'TAMPERED' startingAt: 1) > 0)
							ifTrue: [
								McpJsonRpcError
									signalCode: -32602
									message: 'Invalid or tampered requestState'
									data: nil]
							ifFalse: [
								EsOrderedDictionary with: 'content' -> (Array with: (
									EsOrderedDictionary with: 'type' -> 'text' with: 'text' -> 'State is valid.'))]]
					ifFalse: [| req schema |
						schema :=
							EsOrderedDictionary new
								at: 'type' put: 'object';
								at: 'properties' put: (
									EsOrderedDictionary with: 'ok' -> (
										EsOrderedDictionary with: 'type' -> 'boolean'));
								at: 'required' put: #('ok');
								yourself.
						req :=
							EsOrderedDictionary new
								at: 'method' put: 'elicitation/create';
								at: 'params' put: (
									EsOrderedDictionary
										with: 'message' -> 'Please confirm'
										with: 'requestedSchema' -> schema);
								yourself.
						EsOrderedDictionary new
							at: 'resultType' put: 'input_required';
							at: 'inputRequests' put: (EsOrderedDictionary with: 'confirm' -> req);
							at: 'requestState' put: 'valid-secure-state-token';
							yourself]];
			yourself).

	reg registerTool: (
		McpBlockTool new
			name: 'test_input_required_result_capabilities';
			description: 'MRTR client capabilities check test tool';
			inputSchema: (EsOrderedDictionary with: 'type' -> 'object');
			block: [:args :ctx | | caps inputRequests |
				caps := ctx ifNotNil: [:c | c clientCapabilities] ifNil: [EsOrderedDictionary new].
				inputRequests := EsOrderedDictionary new.
				(caps includesKey: 'sampling')
					ifTrue: [| msg |
						msg :=
							EsOrderedDictionary
								with: 'role' -> 'user'
								with: 'content' -> (
									EsOrderedDictionary with: 'type' -> 'text' with: 'text' -> 'Sampling check').
						inputRequests
							at: 'sample'
							put: (
								EsOrderedDictionary new
									at: 'method' put: 'sampling/createMessage';
									at: 'params' put: (
										EsOrderedDictionary
											with: 'messages' -> (Array with: msg)
											with: 'maxTokens' -> 50);
									yourself)].
				(caps includesKey: 'elicitation')
					ifTrue: [| schema |
						schema := EsOrderedDictionary with: 'type' -> 'object'.
						inputRequests
							at: 'elicit'
							put: (
								EsOrderedDictionary new
									at: 'method' put: 'elicitation/create';
									at: 'params' put: (
										EsOrderedDictionary
											with: 'message' -> 'Elicit check'
											with: 'requestedSchema' -> schema);
									yourself)].
				inputRequests notEmpty
					ifTrue: [
						EsOrderedDictionary new
							at: 'resultType' put: 'input_required';
							at: 'inputRequests' put: inputRequests;
							yourself]
					ifFalse: [
						EsOrderedDictionary with: 'content' -> (Array with: (
							EsOrderedDictionary with: 'type' -> 'text' with: 'text' -> 'No input required'))]];
			yourself).

	"Client-scenario fixtures (sep-2322-client-request-state)"
	reg registerTool: (
		McpBlockTool new
			name: 'test_mrtr_echo_state';
			description: 'MRTR client test: triggers flow with requestState';
			inputSchema: (EsOrderedDictionary with: 'type' -> 'object');
			block: [:args :ctx | | responses |
				responses := ctx ifNotNil: [:c | c inputResponses].
				responses notNil
					ifTrue: [
						EsOrderedDictionary new
							at: 'resultType' put: 'complete';
							at: 'content' put: (Array with: (
								EsOrderedDictionary with: 'type' -> 'text' with: 'text' -> 'echo-state-ok'));
							yourself]
					ifFalse: [| req schema |
						schema :=
							EsOrderedDictionary new
								at: 'type' put: 'object';
								at: 'properties' put: (
									EsOrderedDictionary with: 'confirmed' -> (
										EsOrderedDictionary with: 'type' -> 'boolean'));
								yourself.
						req :=
							EsOrderedDictionary new
								at: 'method' put: 'elicitation/create';
								at: 'params' put: (
									EsOrderedDictionary
										with: 'message' -> 'Please confirm to continue'
										with: 'requestedSchema' -> schema);
								yourself.
						EsOrderedDictionary new
							at: 'resultType' put: 'input_required';
							at: 'inputRequests' put: (EsOrderedDictionary with: 'confirm' -> req);
							at: 'requestState' put: 'test-echo-state-nonce';
							yourself]];
			yourself).

	reg registerTool: (
		McpBlockTool new
			name: 'test_mrtr_no_state';
			description: 'MRTR client test: triggers flow WITHOUT requestState';
			inputSchema: (EsOrderedDictionary with: 'type' -> 'object');
			block: [:args :ctx | | responses |
				responses := ctx ifNotNil: [:c | c inputResponses].
				responses notNil
					ifTrue: [
						EsOrderedDictionary new
							at: 'resultType' put: 'complete';
							at: 'content' put: (Array with: (
								EsOrderedDictionary with: 'type' -> 'text' with: 'text' -> 'no-state-ok'));
							yourself]
					ifFalse: [| req schema |
						schema :=
							EsOrderedDictionary new
								at: 'type' put: 'object';
								at: 'properties' put: (
									EsOrderedDictionary with: 'confirmed' -> (
										EsOrderedDictionary with: 'type' -> 'boolean'));
								yourself.
						req :=
							EsOrderedDictionary new
								at: 'method' put: 'elicitation/create';
								at: 'params' put: (
									EsOrderedDictionary
										with: 'message' -> 'Please confirm (no state)'
										with: 'requestedSchema' -> schema);
								yourself.
						EsOrderedDictionary new
							at: 'resultType' put: 'input_required';
							at: 'inputRequests' put: (EsOrderedDictionary with: 'confirm' -> req);
							yourself]];
			yourself).

	reg registerTool: (
		McpBlockTool new
			name: 'test_mrtr_unrelated';
			description: 'MRTR client test: unrelated tool called between rounds';
			inputSchema: (EsOrderedDictionary with: 'type' -> 'object');
			block: [:args |
				EsOrderedDictionary new
					at: 'resultType' put: 'complete';
					at: 'content' put: (Array with: (
						EsOrderedDictionary with: 'type' -> 'text' with: 'text' -> 'unrelated-ok'));
					yourself];
			yourself).

	reg registerTool: (
		McpBlockTool new
			name: 'test_mrtr_no_result_type';
			description: 'MRTR client test: returns result without resultType';
			inputSchema: (EsOrderedDictionary with: 'type' -> 'object');
			block: [:args |
				EsOrderedDictionary with: 'content' -> (Array with: (
					EsOrderedDictionary
						with: 'type' -> 'text'
						with: 'text' -> 'no-result-type-test-ok'))];
			yourself)
]

{ #category : 'Configuration' }
McpConformanceServer >> registerPrompts [
	"Register all prompts required by the conformance test suite."

	| reg |

	reg := mcpServer promptRegistry.

	reg registerPrompt: (
		McpBlockPrompt new
			name: 'test_simple_prompt';
			description: 'Simple prompt';
			block: [:args |
				EsOrderedDictionary with: 'messages' -> (Array with: (
					EsOrderedDictionary
						with: 'role' -> 'user'
						with: 'content' -> (
							EsOrderedDictionary
								with: 'type' -> 'text'
								with: 'text' -> 'This is a simple prompt for testing.')))];
			yourself).

	reg registerPrompt: (
		McpBlockPrompt new
			name: 'test_prompt_with_arguments';
			description: 'Parameterized prompt';
			arguments: (Array
				with: (
					EsOrderedDictionary
						with: 'name' -> 'arg1'
						with: 'required' -> true)
				with: (
					EsOrderedDictionary
						with: 'name' -> 'arg2'
						with: 'required' -> true));
			block: [:args | | text |
				text :=
					'Prompt with arguments: arg1=''' , (args at: 'arg1' ifAbsent: ['']) , ''', arg2=''' ,
						(args at: 'arg2' ifAbsent: ['']) ,
						''''.
				EsOrderedDictionary with: 'messages' -> (Array with: (
					EsOrderedDictionary
						with: 'role' -> 'user'
						with: 'content' -> (
							EsOrderedDictionary
								with: 'type' -> 'text'
								with: 'text' -> text)))];
			completionBlock: [:argName :prefix :context |
				#('paris' 'park' 'party' 'test' 'testing') select: [:candidate |
					(candidate indexOfSubCollection: prefix startingAt: 1) = 1]];
			yourself).

	reg registerPrompt: (
		McpBlockPrompt new
			name: 'test_prompt_with_embedded_resource';
			description: 'Prompt with embedded resource';
			arguments: (Array with: (
				EsOrderedDictionary
					with: 'name' -> 'resourceUri'
					with: 'required' -> true));
			block: [:args | | rUri resContent msg1 msg2 |
				rUri := args at: 'resourceUri' ifAbsent: ['test://example-resource'].
				resContent :=
					EsOrderedDictionary new
						at: 'type' put: 'resource';
						at: 'resource' put: (
							EsOrderedDictionary new
								at: 'uri' put: rUri;
								at: 'mimeType' put: 'text/plain';
								at: 'text' put: 'Embedded resource content for testing.';
								yourself);
						yourself.
				msg1 :=
					EsOrderedDictionary
						with: 'role' -> 'user'
						with: 'content' -> resContent.
				msg2 :=
					EsOrderedDictionary
						with: 'role' -> 'user'
						with: 'content' -> (
							EsOrderedDictionary
								with: 'type' -> 'text'
								with: 'text' -> 'Please process the embedded resource above.').
				EsOrderedDictionary with: 'messages' -> (Array with: msg1 with: msg2)];
			yourself).

	reg registerPrompt: (
		McpBlockPrompt new
			name: 'test_prompt_with_image';
			description: 'Prompt with image content';
			block: [:args | | imgContent msg1 msg2 |
				imgContent :=
					EsOrderedDictionary new
						at: 'type' put: 'image';
						at: 'data' put: self base64PngPixel;
						at: 'mimeType' put: 'image/png';
						yourself.
				msg1 :=
					EsOrderedDictionary
						with: 'role' -> 'user'
						with: 'content' -> imgContent.
				msg2 :=
					EsOrderedDictionary
						with: 'role' -> 'user'
						with: 'content' -> (
							EsOrderedDictionary
								with: 'type' -> 'text'
								with: 'text' -> 'Please analyze the image above.').
				EsOrderedDictionary with: 'messages' -> (Array with: msg1 with: msg2)];
			yourself).

	reg registerPrompt: (
		McpBlockPrompt new
			name: 'test_input_required_result_prompt';
			description: 'Prompt with elicitation input required';
			block: [:args :ctx | | responses |
				responses := ctx ifNotNil: [:c | c inputResponses].
				(responses notNil and: [responses includesKey: 'user_context'])
					ifTrue: [| ctxVal |
						ctxVal :=
							((responses at: 'user_context') at: 'content' ifAbsent: [EsOrderedDictionary new])
								at: 'context'
								ifAbsent: ['default'].
						EsOrderedDictionary with: 'messages' -> (Array with: (
							EsOrderedDictionary
								with: 'role' -> 'user'
								with: 'content' -> (
									EsOrderedDictionary
										with: 'type' -> 'text'
										with: 'text' -> ('Prompt with context: ' , ctxVal))))]
					ifFalse: [| req schema |
						schema :=
							EsOrderedDictionary new
								at: 'type' put: 'object';
								at: 'properties' put: (
									EsOrderedDictionary with: 'context' -> (
										EsOrderedDictionary with: 'type' -> 'string'));
								at: 'required' put: #('context');
								yourself.
						req :=
							EsOrderedDictionary new
								at: 'method' put: 'elicitation/create';
								at: 'params' put: (
									EsOrderedDictionary
										with: 'message' -> 'What context should the prompt use?'
										with: 'requestedSchema' -> schema);
								yourself.
						EsOrderedDictionary new
							at: 'resultType' put: 'input_required';
							at: 'inputRequests' put: (EsOrderedDictionary with: 'user_context' -> req);
							yourself]];
			yourself)
]

{ #category : 'Configuration' }
McpConformanceServer >> registerResources [
	"Register all resources and resource templates required by the conformance test suite."

	| reg tReg |

	reg := mcpServer resourceRegistry.
	tReg := mcpServer resourceTemplateRegistry.

	reg registerResource: (
		McpBlockResource new
			uri: 'test://static-text';
			name: 'static-text';
			description: 'Static text resource';
			mimeType: 'text/plain';
			block: [
				EsOrderedDictionary with: 'contents' -> (Array with: (
					EsOrderedDictionary new
						at: 'uri' put: 'test://static-text';
						at: 'mimeType' put: 'text/plain';
						at: 'text' put: 'This is the content of the static text resource.';
						yourself))];
			yourself).

	reg registerResource: (
		McpBlockResource new
			uri: 'test://static-binary';
			name: 'static-binary';
			description: 'Static binary resource';
			mimeType: 'image/png';
			block: [
				EsOrderedDictionary with: 'contents' -> (Array with: (
					EsOrderedDictionary new
						at: 'uri' put: 'test://static-binary';
						at: 'mimeType' put: 'image/png';
						at: 'blob' put: self base64PngPixel;
						yourself))];
			yourself).

	tReg registerTemplate: (
		McpBlockResourceTemplate new
			uriTemplate: 'test://template/{id}/data';
			name: 'template-data';
			description: 'Parameterized resource template';
			readBlock: [:uri :ctx | | vars id text |
				vars := (McpUriTemplate template: 'test://template/{id}/data') matchUri: uri.
				id := vars ifNotNil: [vars at: 'id' ifAbsent: ['123']] ifNil: ['123'].
				text :=
					'{"id":"' , id , '","templateTest":true,"data":"Data for ID: ' , id , '"}'.
				EsOrderedDictionary with: 'contents' -> (Array with: (
					EsOrderedDictionary new
						at: 'uri' put: uri;
						at: 'mimeType' put: 'application/json';
						at: 'text' put: text;
						yourself))];
			yourself)
]

{ #category : 'Configuration' }
McpConformanceServer >> registerTools [
	"Register all tools required by the MCP server and client conformance test suites."

	| reg |

	reg := mcpServer toolRegistry.

	reg registerTool: (
		McpBlockTool new
			name: 'test_simple_text';
			description: 'Simple text response';
			inputSchema: (EsOrderedDictionary with: 'type' -> 'object');
			block: [:args |
				EsOrderedDictionary with: 'content' -> (Array with: (
					EsOrderedDictionary
						with: 'type' -> 'text'
						with: 'text' -> 'This is a simple text response for testing.'))];
			yourself).

	reg registerTool: (
		McpBlockTool new
			name: 'test_image_content';
			description: 'Image content response';
			inputSchema: (EsOrderedDictionary with: 'type' -> 'object');
			block: [:args |
				EsOrderedDictionary with: 'content' -> (Array with: (
					EsOrderedDictionary new
						at: 'type' put: 'image';
						at: 'data' put: self base64PngPixel;
						at: 'mimeType' put: 'image/png';
						yourself))];
			yourself).

	reg registerTool: (
		McpBlockTool new
			name: 'test_audio_content';
			description: 'Audio content response';
			inputSchema: (EsOrderedDictionary with: 'type' -> 'object');
			block: [:args |
				EsOrderedDictionary with: 'content' -> (Array with: (
					EsOrderedDictionary new
						at: 'type' put: 'audio';
						at: 'data' put: self base64WavAudio;
						at: 'mimeType' put: 'audio/wav';
						yourself))];
			yourself).

	reg registerTool: (
		McpBlockTool new
			name: 'test_embedded_resource';
			description: 'Embedded resource content response';
			inputSchema: (EsOrderedDictionary with: 'type' -> 'object');
			block: [:args |
				EsOrderedDictionary with: 'content' -> (Array with: (
					EsOrderedDictionary new
						at: 'type' put: 'resource';
						at: 'resource' put: (
							EsOrderedDictionary new
								at: 'uri' put: 'test://embedded-resource';
								at: 'mimeType' put: 'text/plain';
								at: 'text' put: 'This is an embedded resource content.';
								yourself);
						yourself))];
			yourself).

	reg registerTool: (
		McpBlockTool new
			name: 'test_multiple_content_types';
			description: 'Tool returning mixed content types';
			inputSchema: (EsOrderedDictionary with: 'type' -> 'object');
			block: [:args |
				EsOrderedDictionary with: 'content' -> (Array
					with: (
						EsOrderedDictionary
							with: 'type' -> 'text'
							with: 'text' -> 'Multiple content types test:')
					with: (
						EsOrderedDictionary new
							at: 'type' put: 'image';
							at: 'data' put: self base64PngPixel;
							at: 'mimeType' put: 'image/png';
							yourself)
					with: (
						EsOrderedDictionary new
							at: 'type' put: 'resource';
							at: 'resource' put: (
								EsOrderedDictionary new
									at: 'uri' put: 'test://mixed-content-resource';
									at: 'mimeType' put: 'application/json';
									at: 'text' put: '{"test":"data","value":123}';
									yourself);
							yourself))];
			yourself).

	reg registerTool: (
		McpBlockTool new
			name: 'test_error_handling';
			description: 'Tool intentionally returning an error';
			inputSchema: (EsOrderedDictionary with: 'type' -> 'object');
			block: [:args |
				McpToolError signal: 'This tool intentionally returns an error for testing'];
			yourself).

	reg registerTool: (
		McpBlockTool new
			name: 'test_tool_with_progress';
			description: 'Tool reporting progress updates';
			inputSchema: (EsOrderedDictionary with: 'type' -> 'object');
			block: [:args :ctx |
				ctx ifNotNil: [
					ctx reportProgress: 0 total: 100 message: 'Starting'.
					(Delay forMilliseconds: 50) wait.
					ctx reportProgress: 50 total: 100 message: 'Halfway'.
					(Delay forMilliseconds: 50) wait.
					ctx reportProgress: 100 total: 100 message: 'Done'].
				EsOrderedDictionary with: 'content' -> (Array with: (
					EsOrderedDictionary
						with: 'type' -> 'text'
						with: 'text' -> 'Execution completed with progress.'))];
			yourself).

	reg registerTool: (
		McpBlockTool new
			name: 'test_sampling';
			description: 'Tool requesting LLM sampling';
			inputSchema: (
				EsOrderedDictionary new
					at: 'type' put: 'object';
					at: 'properties' put: (
						EsOrderedDictionary with: 'prompt' -> (
							EsOrderedDictionary with: 'type' -> 'string'));
					at: 'required' put: #('prompt');
					yourself);
			block: [:args |
				EsOrderedDictionary with: 'content' -> (Array with: (
					EsOrderedDictionary
						with: 'type' -> 'text'
						with: 'text' -> ('LLM response: ' , (args at: 'prompt' ifAbsent: ['']))))];
			yourself).

	reg registerTool: (
		McpBlockTool new
			name: 'test_elicitation';
			description: 'Tool requesting user input';
			inputSchema: (
				EsOrderedDictionary new
					at: 'type' put: 'object';
					at: 'properties' put: (
						EsOrderedDictionary with: 'message' -> (
							EsOrderedDictionary with: 'type' -> 'string'));
					at: 'required' put: #('message');
					yourself);
			block: [:args |
				EsOrderedDictionary with: 'content' -> (Array with: (
					EsOrderedDictionary
						with: 'type' -> 'text'
						with: 'text' -> ('User response: ' , (args at: 'message' ifAbsent: ['']))))];
			yourself).

	reg registerTool: (
		McpBlockTool new
			name: 'test_client_elicitation_defaults';
			description: 'Tool triggering client elicitation defaults';
			inputSchema: (EsOrderedDictionary with: 'type' -> 'object');
			block: [:args :ctx | | responses |
				responses := ctx ifNotNil: [:c | c inputResponses].
				responses notNil
					ifTrue: [
						EsOrderedDictionary with: 'content' -> (Array with: (
							EsOrderedDictionary
								with: 'type' -> 'text'
								with: 'text' -> 'elicitation-defaults-ok'))]
					ifFalse: [| req schema |
						schema :=
							EsOrderedDictionary new
								at: 'type' put: 'object';
								at: 'properties' put: (
									EsOrderedDictionary with: 'name' -> (
										EsOrderedDictionary
											with: 'type' -> 'string'
											with: 'default' -> 'DefaultName'));
								yourself.
						req :=
							EsOrderedDictionary new
								at: 'method' put: 'elicitation/create';
								at: 'params' put: (
									EsOrderedDictionary
										with: 'message' -> 'Please provide input'
										with: 'requestedSchema' -> schema);
								yourself.
						EsOrderedDictionary new
							at: 'resultType' put: 'input_required';
							at: 'inputRequests' put: (EsOrderedDictionary with: 'elicit_input' -> req);
							yourself]];
			yourself).

	reg registerTool: (
		McpBlockTool new
			name: 'json_schema_2020_12_tool';
			description: 'Tool with 2020-12 schema';
			inputSchema: (EsOrderedDictionary with: 'type' -> 'object');
			block: ['ok'];
			yourself).

	reg registerTool: (
		McpBlockTool new
			name: 'json_schema_echo';
			description: 'Tool echoing schema';
			inputSchema: (EsOrderedDictionary with: 'type' -> 'object');
			block: [:args |
				EsOrderedDictionary with: 'content' -> (Array with: (
					EsOrderedDictionary with: 'type' -> 'text' with: 'text' -> 'schema-echoed'))];
			yourself).

	self registerMrtrToolsOn: reg
]

{ #category : 'Starting and Stopping' }
McpConformanceServer >> restart [
	"Stop and restart the server to re-register all tools, resources, and prompts.

	 Answers:
		<McpConformanceServer> the receiver."

	self stop.
	mcpServer := nil.
	^self start
]

{ #category : 'Starting and Stopping' }
McpConformanceServer >> start [
	"Start the HTTP conformance test server on the configured port.

	 Answers:
		<McpConformanceServer> the receiver."

	self isRunning ifTrue: [^self].
	httpServer :=
		McpHttpServer new
			host: self host;
			port: self port;
			endpointPath: '/mcp';
			mcpServer: self mcpServer;
			start;
			yourself.
	^self
]

{ #category : 'Starting and Stopping' }
McpConformanceServer >> stop [
	"Stop the HTTP conformance test server and release resources.

	 Answers:
		<McpConformanceServer> the receiver."

	httpServer ifNotNil: [
		httpServer stop.
		httpServer := nil].
	^self
]

{ #category : 'Accessing' }
McpConformanceServer >> url [
	"Answer the full HTTP MCP endpoint URL for this server.

	 Answers:
		<String>."

	^'http://' , self host , ':' , self port printString , '/mcp'
]
