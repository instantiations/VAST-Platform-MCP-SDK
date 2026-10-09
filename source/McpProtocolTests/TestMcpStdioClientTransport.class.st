"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# TestMcpStdioClientTransport

`TestMcpStdioClientTransport` tests native Standard I/O subprocess transport
execution, stream decoding, error handling, and ADK tool integration.
"
Class {
	#name : 'TestMcpStdioClientTransport',
	#superclass : 'TestCase',
	#instVars : [
		'transport',
		'client'
	],
	#category : 'McpProtocolTests'
}

{ #category : 'Running' }
TestMcpStdioClientTransport >> selectorsToSkip [
	"Dynamically skip tests that require tools that are not present."

	| skip |

	skip := super selectorsToSkip asOrderedCollection.
	(Smalltalk includesKey: #AdkMcpServer) ifFalse: [skip add: #testAdkMcpServerStdioIntegration].
	^skip
]

{ #category : 'Running' }
TestMcpStdioClientTransport >> setUp [
	"Prepare a default stdio transport fixture.

	 Answers:
		<TestMcpStdioClientTransport> the receiver."

	super setUp.
	transport := McpStdioClientTransport command: 'echo'.
	client := McpClient new.
	^self
]

{ #category : 'Running' }
TestMcpStdioClientTransport >> tearDown [
	"Clean up running transport and client fixtures.

	 Answers:
		<TestMcpStdioClientTransport> the receiver."

	transport ifNotNil: [[transport close] on: Error do: [:closeError | closeError return: nil]].
	client ifNotNil: [[client close] on: Error do: [:closeError | closeError return: nil]].
	super tearDown
]

{ #category : 'Testing' }
TestMcpStdioClientTransport >> testAdkMcpServerStdioIntegration [
	"Live end-to-end: AdkMcpServer connects to a python stdio MCP server."

	| adkServer tools tool result |

	adkServer :=
		(Smalltalk at: #AdkMcpServer)
			named: 'py-stdio'
			command: 'python'
			arguments: #('test_stdio_server.py')
			environment: nil
			workingDirectory: 'C:\Users\sberman\repos\mcp-python'
			mode: #auto.
	[
		tools := adkServer tools.
		self assert: tools notEmpty.
		tool := tools detect: [:t | t name = 'add_numbers'] ifNone: [nil].
		self assert: tool notNil.
		result :=
			tool executeWithArguments: (Dictionary with: 'a' -> 100 with: 'b' -> 23) context: nil.
		self assert: (result at: 'isError') equals: false.
		self assert: (((result at: 'content') first at: 'text') includesSubstring: '123')]
			ensure: [adkServer close]
]

{ #category : 'Testing' }
TestMcpStdioClientTransport >> testCustomConfiguration [
	"Verify configuration mutators."

	transport
		command: 'python';
		arguments: #('-u' 'server.py');
		environment: (Dictionary with: 'MCP_PORT' -> '8080');
		workingDirectory: 'C:/temp';
		runInShell: true;
		requestTimeout: 30.

	self assert: transport command = 'python'.
	self assert: transport arguments asArray = #('-u' 'server.py').
	self assert: (transport environment at: 'MCP_PORT') = '8080'.
	self assert: transport workingDirectory = 'C:/temp'.
	self assert: transport runInShell.
	self assert: transport requestTimeout = 30
]

{ #category : 'Testing' }
TestMcpStdioClientTransport >> testDefaultConfiguration [
	"Verify default transport state and capabilities."

	self assert: transport command = 'echo'.
	self assert: transport arguments isEmpty.
	self assert: transport environment isNil.
	self assert: transport workingDirectory isNil.
	self deny: transport runInShell.
	self assert: transport requestTimeout = 60.
	self deny: transport supportsRequestHeaders.
	self deny: transport isRunning.
	self assert: transport stderrLines isEmpty
]

{ #category : 'Testing' }
TestMcpStdioClientTransport >> testHandleIncomingErrorResponse [
	"Verify that handleStdoutLine: handles error responses and validatedResultFrom:id: signals McpJsonRpcError."

	| sem entry lineJson response |

	sem := Semaphore new.
	entry := Dictionary new.
	entry
		at: #semaphore put: sem;
		at: #response put: nil;
		at: #completed put: false;
		at: #timedOut put: false;
		at: #errorReason put: nil.

	(transport instVarNamed: 'pendingRequests') at: 10 put: entry.
	lineJson :=
		'{"jsonrpc": "2.0", "id": 10, "error": {"code": -32601, "message": "Method not found"}}'.
	transport handleStdoutLine: lineJson asUtf8Bytes.

	self assert: (entry at: #completed).
	response := entry at: #response.
	self assert: response notNil.

	self should: [transport validatedResultFrom: response id: 10] raise: McpJsonRpcError
]

{ #category : 'Testing' }
TestMcpStdioClientTransport >> testHandleIncomingNotificationDispatchedToClient [
	"Verify that server-sent notifications are forwarded to the client's notification handlers."

	| receivedNotification lineJson |

	receivedNotification := nil.
	transport client: client.
	client
		onNotification: 'notifications/tools/list_changed'
		do: [:params | receivedNotification := params].

	lineJson :=
		'{"jsonrpc": "2.0", "method": "notifications/tools/list_changed", "params": {"updated": true}}'.
	transport handleStdoutLine: lineJson asUtf8Bytes.

	self assert: receivedNotification notNil.
	self assert: (receivedNotification at: 'updated') = true
]

{ #category : 'Testing' }
TestMcpStdioClientTransport >> testHandleIncomingResponseResolvesPendingRequest [
	"Verify that handleStdoutLine: matches and resolves a pending request by ID."

	| sem entry lineJson response |

	sem := Semaphore new.
	entry := Dictionary new.
	entry
		at: #semaphore put: sem;
		at: #response put: nil;
		at: #completed put: false;
		at: #timedOut put: false;
		at: #errorReason put: nil.

	(transport instVarNamed: 'pendingRequests') at: 42 put: entry.
	lineJson := '{"jsonrpc": "2.0", "id": 42, "result": {"status": "ok"}}'.
	transport handleStdoutLine: lineJson asUtf8Bytes.

	self assert: (entry at: #completed).
	response := entry at: #response.
	self assert: response notNil.
	self assert: (response at: 'id') = 42.
	self assert: ((response at: 'result') at: 'status') = 'ok'
]

{ #category : 'Testing' }
TestMcpStdioClientTransport >> testHandleStderrLine [
	"Verify stderr line recording and handler invocation."

	| captured |

	captured := OrderedCollection new.
	transport stderrHandler: [:line | captured add: line].
	transport handleStderrLine: 'Log message 1' asUtf8Bytes.
	transport handleStderrLine: 'Log message 2' asUtf8Bytes.

	self assert: transport stderrLines asArray = #('Log message 1' 'Log message 2').
	self assert: captured asArray = #('Log message 1' 'Log message 2')
]

{ #category : 'Testing' }
TestMcpStdioClientTransport >> testHeadersAreRejected [
	"Verify that passing transport headers signals an error."

	self
		should: [
			transport
				sendRequest: (Dictionary with: 'method' -> 'ping')
				id: 1
				headers: (Dictionary with: 'Authorization' -> 'Bearer test')]
		raise: Error
]

{ #category : 'Testing' }
TestMcpStdioClientTransport >> testStdioPythonServerIntegration [
	"Live end-to-end: VAST McpClient connects to a python stdio MCP server."

	| scriptLines stdioTransport mcpClient tools toolNames result |

	scriptLines := #(
		'from mcp.server.mcpserver import MCPServer'
		'mcp = MCPServer("PythonStdioServer")'
		'@mcp.tool()'
		'def add_numbers(a: int, b: int) -> int:'
		'	return a + b'
		'mcp.run(transport="stdio")').

	stdioTransport :=
		McpStdioClientTransport
			command: 'uv'
			arguments: { 'run'. '--with'. 'mcp'. 'python'. '-c'. CldtConstants::LineDelimiter join: scriptLines }
			environment: nil
			workingDirectory: nil.
	stdioTransport requestTimeout: 15.

	mcpClient := McpClient auto.
	mcpClient transport: stdioTransport.
	[
		mcpClient connect.
		self assert: mcpClient isConnected.
		self assert: (mcpClient serverInfo at: 'name') = 'PythonStdioServer'.
		tools := mcpClient listTools.
		toolNames := tools collect: [:each | each at: 'name'].
		self assert: (toolNames includes: 'add_numbers').
		result :=
			mcpClient
				callTool: 'add_numbers'
				arguments: (EsOrderedDictionary with: 'a' -> 17 with: 'b' -> 25).
		self assert: (result at: 'isError') equals: false.
		self assert: (((result at: 'content') first at: 'text') includesSubstring: '42')]
			ensure: [mcpClient close].
	self deny: stdioTransport isRunning
]

{ #category : 'Testing' }
TestMcpStdioClientTransport >> testValidationRejectsInvalidParameters [
	"Verify that invalid configuration arguments raise appropriate errors."

	self should: [transport command: ''] raise: Error.
	self should: [transport command: nil] raise: Error.
	self should: [transport arguments: 123] raise: Error.
	self should: [transport environment: 456] raise: Error.
	self should: [transport workingDirectory: 789] raise: Error.
	self should: [transport requestTimeout: 0] raise: Error.
	self should: [transport requestTimeout: -5] raise: Error.
	self should: [transport stderrHandler: 'not a block'] raise: Error
]
