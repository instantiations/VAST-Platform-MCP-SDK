"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# TestMcpProgress

`TestMcpProgress` tests MCP `notifications/progress` notification dispatch,
server-side progress token extraction, context reporting, and client-side
progress callback correlation.
"
Class {
	#name : 'TestMcpProgress',
	#superclass : 'TestCase',
	#instVars : [
		'server',
		'dispatcher',
		'client',
		'transport'
	],
	#category : 'McpProtocolTests'
}

{ #category : 'Running' }
TestMcpProgress >> setUp [
	"Prepare progress test fixtures.

	 Answers:
		<TestMcpProgress> the receiver."

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
TestMcpProgress >> tearDown [
	"Clean up test fixtures.

	 Answers:
		<TestMcpProgress> the receiver."

	client ifNotNil: [[client close] on: Error do: [:closeError | closeError return: nil]].
	super tearDown
]

{ #category : 'Testing' }
TestMcpProgress >> testClientAutoGeneratesProgressTokenWhenCallbackSupplied [
	"Verify that providing a progressCallback without a token automatically
		attaches a generated progressToken."

	| response sentRequest meta token |

	client instVarNamed: 'isConnected' put: true.
	client instVarNamed: 'serverCapabilities' put: (Dictionary with: 'tools' ->
		Dictionary new).

	response :=
		EsOrderedDictionary new
			at: 'content'
				put: (Array with: (EsOrderedDictionary with: 'type' -> 'text'
				with: 'text' -> 'OK'));
			at: 'isError' put: false;
			yourself.
	transport enqueueResponse: response.
	transport enqueueResponse: (EsOrderedDictionary with: 'tools' -> #()).

	client callTool: 'heavy_task' arguments: nil progressCallback: [:prog :tot
		:msg | nil].

	sentRequest := transport requests first.
	meta := (sentRequest at: 'params') at: '_meta'.
	self assert: (meta includesKey: 'progressToken').
	token := meta at: 'progressToken'.
	self assert: ((token indexOfSubCollection: 'progress-' startingAt: 1) = 1)

]

{ #category : 'Testing' }
TestMcpProgress >> testClientDeregistersProgressCallbackAfterCompletion [
	"Verify that the progress callback is cleanly removed after request
		completion."

	| response callbacks |

	client instVarNamed: 'isConnected' put: true.
	client instVarNamed: 'serverCapabilities' put: (Dictionary with: 'tools' ->
		Dictionary new).

	response :=
		EsOrderedDictionary new
			at: 'content'
				put: (Array with: (EsOrderedDictionary with: 'type' -> 'text'
				with: 'text' -> 'OK'));
			at: 'isError' put: false;
			yourself.
	transport enqueueResponse: response.
	transport enqueueResponse: (EsOrderedDictionary with: 'tools' -> #()).

	client
		callTool: 'heavy_task'
		arguments: nil
		progressToken: 'tok-temp'
		progressCallback: [:p | nil].

	callbacks := client instVarNamed: 'progressCallbacks'.
	self deny: (callbacks includesKey: 'tok-temp')

]

{ #category : 'Testing' }
TestMcpProgress >> testClientDispatchesProgressNotificationToCallback [
	"Verify that client dispatches notifications/progress to the matching
		progressCallback."

	| updates response progressNotification |

	updates := OrderedCollection new.
	client instVarNamed: 'isConnected' put: true.
	client instVarNamed: 'serverCapabilities' put: (Dictionary with: 'tools' ->
		Dictionary new).

	response :=
		EsOrderedDictionary new
			at: 'content'
				put: (Array with: (EsOrderedDictionary with: 'type' -> 'text'
				with: 'text' -> 'OK'));
			at: 'isError' put: false;
			yourself.
	transport enqueueResponse: response.
	transport enqueueResponse: (EsOrderedDictionary with: 'tools' -> #()).

	transport requestBlock: [
		progressNotification :=
			EsOrderedDictionary new
				at: 'jsonrpc' put: '2.0';
				at: 'method' put: 'notifications/progress';
				at: 'params'
					put: (
						EsOrderedDictionary new
							at: 'progressToken' put: 'tok-1';
							at: 'progress' put: 33;
							at: 'total' put: 100;
							at: 'message' put: 'One third';
							yourself);
				yourself.
		client handleIncomingMessage: progressNotification].

	client
		callTool: 'heavy_task'
		arguments: nil
		progressToken: 'tok-1'
		progressCallback: [:prog :tot :msg | updates add: (Array with: prog
			with: tot with: msg)].

	self assert: updates size = 1.
	self assert: updates first = #(33 100 'One third')

]

{ #category : 'Testing' }
TestMcpProgress >> testEndToEndToolCallWithProgress [
	"Verify end-to-end tool execution with progress reporting."

	| tool clientReceivedUpdates |

	clientReceivedUpdates := OrderedCollection new.
	tool :=
		McpBlockTool new
			name: 'backup_database';
			inputSchema: (EsOrderedDictionary with: 'type' -> 'object');
			block: [:args :ctx |
				ctx ifNotNil: [
					ctx reportProgress: 25 total: 100 message:
				'Exporting tables'.
					ctx reportProgress: 75 total: 100 message:
				'Compressing archive'.
					ctx reportProgress: 100 total: 100 message: 'Complete'].
				'Backup complete'];
			yourself.
	server toolRegistry registerTool: tool.

	client instVarNamed: 'isConnected' put: true.
	client instVarNamed: 'serverCapabilities' put: (Dictionary with: 'tools' ->
		Dictionary new).

	transport requestBlock: [| lastReq reqContext |
		lastReq := transport requests last.
		(lastReq at: 'method') = 'tools/list' ifTrue: [
			transport enqueueResponse: (EsOrderedDictionary with: 'tools' ->
				#())
		] ifFalse: [
		reqContext := McpServerRequestContext new.
		reqContext progressReporter: [:progressNotificationParams |
			client handleIncomingMessage: (
				EsOrderedDictionary new
					at: 'jsonrpc' put: '2.0';
					at: 'method' put: 'notifications/progress';
					at: 'params' put: progressNotificationParams;
					yourself)].
		server toolsCall: (lastReq at: 'params') context: reqContext.
		transport enqueueResponse: (
			EsOrderedDictionary new
				at: 'content'
					put: (
						Array with: (
							EsOrderedDictionary
								with: 'type' -> 'text'
								with: 'text' -> 'Backup complete'));
				at: 'isError' put: false;
				yourself)]].

	client
		callTool: 'backup_database'
		arguments: nil
		progressToken: 'backup-1'
		progressCallback: [:prog :tot :msg |
			clientReceivedUpdates add: (Array with: prog with: tot with: msg)].

	self assert: clientReceivedUpdates size = 3.
	self assert: clientReceivedUpdates first = #(25 100 'Exporting tables').
	self assert: clientReceivedUpdates second = #(75 100 'Compressing archive').
	self assert: clientReceivedUpdates third = #(100 100 'Complete')

]

{ #category : 'Testing' }
TestMcpProgress >> testServerRequestContextReportProgress [
	"Verify reportProgress:total:message: populates and fires the progressReporter block."

	| context reported |

	reported := nil.
	context := McpServerRequestContext new.
	context progressToken: 'custom-token-42'.
	context progressReporter: [:params | reported := params].

	context reportProgress: 50 total: 100 message: 'Halfway done'.

	self assert: reported notNil.
	self assert: (reported at: 'progressToken') = 'custom-token-42'.
	self assert: (reported at: 'progress') = 50.
	self assert: (reported at: 'total') = 100.
	self assert: (reported at: 'message') = 'Halfway done'
]

{ #category : 'Testing' }
TestMcpProgress >> testServerRequestContextReportProgressWithoutTokenIsNoOp [
	"Verify reportProgress is a no-op when the caller did not supply a progressToken."

	| context reported |

	reported := nil.
	context := McpServerRequestContext new.
	context progressReporter: [:params | reported := params].

	context reportProgress: 25 total: 100 message: 'Ignored'.

	self assert: reported isNil
]

{ #category : 'Testing' }
TestMcpProgress >> testToolsCallExtractsProgressToken [
	"Verify toolsCall:context: extracts progressToken from parameters _meta."

	| tool context executedToken |

	executedToken := nil.
	tool :=
		McpBlockTool new
			name: 'heavy_task';
			inputSchema: (EsOrderedDictionary with: 'type' -> 'object');
			block: [:args :ctx |
				executedToken := ctx progressToken.
				'done'];
			yourself.
	server toolRegistry registerTool: tool.

	context := McpServerRequestContext new.
	server
		toolsCall: (
			EsOrderedDictionary new
				at: 'name' put: 'heavy_task';
				at: '_meta' put: (EsOrderedDictionary with: 'progressToken' -> 999);
				yourself)
		context: context.

	self assert: executedToken = 999.
	self assert: context progressToken = 999
]
