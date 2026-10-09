"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# TestMcpClient

`TestMcpClient` verifies client connection lifecycle across modern and legacy
protocol eras.

## Responsibilities

- Verify the ordered `initialize` and `notifications/initialized` handshake.
- Verify modern discovery via `server/discover` without session handshake.
- Verify connection modes (`#auto`, `#modern`, `#legacy`).
- Verify outgoing modern request `_meta` envelope stamping.
- Verify connection, ping gating, closure, and transport ownership behavior.

## Test isolation

Each test receives a new client and scripted transport. Tests perform no network
I/O, create no background work, and make no timing assumptions.
"
Class {
	#name : 'TestMcpClient',
	#superclass : 'TestCase',
	#instVars : [
		'client',
		'transport'
	],
	#category : 'McpProtocolTests'
}

{ #category : 'Initialization' }
TestMcpClient >> setUp [
	"Create an isolated client and scripted transport."

	super setUp.
	transport := McpScriptedClientTransport new.
	client := McpClient new.
	client transport: transport
]

{ #category : 'Protocol Operations' }
TestMcpClient >> testCancelRequestSendsNotification [
	"Client sends notifications/cancelled with requestId and reason."

	| notification params |

	client instVarNamed: 'isConnected' put: true.
	client instVarNamed: 'serverCapabilities' put: Dictionary new.

	client cancelRequest: 'req-42' reason: 'User navigated away'.

	self assert: transport notifications size equals: 1.
	notification := transport notifications first.
	self assert: (notification at: 'method') equals: 'notifications/cancelled'.
	params := notification at: 'params'.
	self assert: (params at: 'requestId') equals: 'req-42'.
	self assert: (params at: 'reason') equals: 'User navigated away'
]

{ #category : 'Protocol Operations' }
TestMcpClient >> testClientSubscriptionListensAndEvictsCacheOnNotification [
	"Client subscribes via subscriptions/listen, receives notifications, and evicts cached responses."

	| server tool inMemoryClient eventsReceived |

	server :=
		McpServer new
			name: 'SubscriptionServer';
			version: '1.0.0';
			yourself.
	tool :=
		McpBlockTool new
			name: 'ping_tool';
			inputSchema: (EsOrderedDictionary with: 'type' -> 'object');
			block: [:args | 'pong'];
			yourself.
	server toolRegistry registerTool: tool.

	inMemoryClient := McpClient forServer: server mode: #modern.
	eventsReceived := OrderedCollection new.
	[
		inMemoryClient responseCache
			set: 'tools/list'
			key: ''
			value: (EsOrderedDictionary with: 'tools' -> #())
			ttlMs: 60000
			scope: 'public'.
		self assert: inMemoryClient responseCache size >= 1.

		inMemoryClient
			listen: (EsOrderedDictionary with: 'tools' -> true)
			do: [:method :params | eventsReceived add: method].

		server notifyToolsChanged.

		self assert: eventsReceived size equals: 1.
		self assert: eventsReceived first equals: 'notifications/tools/list_changed'.
		self assert: (inMemoryClient responseCache get: 'tools/list' key: '') isNil]
			ensure: [inMemoryClient close]
]

{ #category : 'Starting and Stopping' }
TestMcpClient >> testCloseClearsNegotiatedState [
	"Closing clears the completed initialization state."

	transport enqueueResponse: self validInitializeResult.
	client connect.
	client close.

	self deny: client isConnected.
	self assert: client protocolVersion equals: nil.
	self assert: client serverCapabilities isEmpty.
	self assert: client serverInfo isEmpty.
	self assert: transport closed.
	self assert: transport closeCount equals: 1.
	self assert: transport interactions size equals: 3.
	self assert: (transport interactions last at: 'kind') equals: 'close'
]

{ #category : 'Protocol Operations' }
TestMcpClient >> testConnectIsIdempotent [
	"Connecting twice performs the handshake only once."

	transport enqueueResponse: self validInitializeResult.
	client connect.
	client connect.

	self assert: client isConnected.
	self assert: transport requests size equals: 1.
	self assert: transport notifications size equals: 1.
	self assert: transport interactions size equals: 2
]

{ #category : 'Protocol Operations' }
TestMcpClient >> testConnectModernUsesServerDiscover [
	"Connecting with mode #modern uses server/discover without notifications/initialized."

	| discoverResult request |

	discoverResult :=
		EsOrderedDictionary new
			at: 'capabilities' put: (EsOrderedDictionary with: 'tools' -> EsOrderedDictionary new);
			at: 'supportedVersions' put: #('2026-07-28' '2025-11-25');
			at: 'resultType' put: 'complete';
			at: 'cacheScope' put: 'public';
			at: 'ttlMs' put: 0;
			at: '_meta'
				put: (
					EsOrderedDictionary with:
						'io.modelcontextprotocol/serverInfo' -> (
							EsOrderedDictionary
								with: 'name' -> 'ModernServer'
								with: 'version' -> '2.0.0'));
			yourself.
	transport enqueueResponse: discoverResult.
	client mode: #modern.
	client connect.

	self assert: transport interactions size equals: 1.
	request := transport interactions first at: 'message'.
	self assert: (request at: 'method') equals: 'server/discover'.
	self assert: client isConnected.
	self assert: client protocolVersion equals: '2026-07-28'.
	self assert: (client serverCapabilities includesKey: 'tools').
	self assert: (client serverInfo at: 'name') equals: 'ModernServer'.
	self assert: (client serverInfo at: 'version') equals: '2.0.0'
]

{ #category : 'Protocol Operations' }
TestMcpClient >> testConnectModernWithPriorDiscoverSendsNoProbe [
	"Connecting with priorDiscover bypasses the server/discover network round-trip."

	| prior testTransport testClient |

	prior :=
		EsOrderedDictionary new
			at: 'capabilities' put: (Dictionary with: 'tools' -> Dictionary new);
			at: 'resultType' put: 'complete';
			at: '_meta'
				put: (
					EsOrderedDictionary with:
						'io.modelcontextprotocol/serverInfo' ->
							(Dictionary with: 'name' -> 'CachedServer' with: 'version' -> '2.0.0'));
			yourself.
	testTransport := McpScriptedClientTransport new.
	testClient := McpClient modern.
	testClient transport: testTransport.
	testClient priorDiscover: prior.
	testClient connect.
	[
		self assert: testClient isConnected.
		self assert: testClient protocolVersion equals: '2026-07-28'.
		self assert: (testClient serverInfo at: 'name') equals: 'CachedServer'.
		self assert: testTransport requests isEmpty]
			ensure: [testClient close]
]

{ #category : 'Validation' }
TestMcpClient >> testConnectRejectsMissingCapabilities [
	"Initialization requires a server capability object."

	| result |

	result := self validInitializeResult.
	result removeKey: 'capabilities'.
	transport enqueueResponse: result.

	self should: [client connect] raise: Error.
	self deny: client isConnected.
	self assert: transport notifications isEmpty
]

{ #category : 'Validation' }
TestMcpClient >> testConnectRejectsMissingServerInfo [
	"Initialization requires a server implementation object."

	| result |

	result := self validInitializeResult.
	result removeKey: 'serverInfo'.
	transport enqueueResponse: result.

	self should: [client connect] raise: Error.
	self deny: client isConnected.
	self assert: transport notifications isEmpty
]

{ #category : 'Validation' }
TestMcpClient >> testConnectRejectsMissingServerName [
	"Initialization requires a nonempty server name."

	| result |

	result := self validInitializeResult.
	(result at: 'serverInfo') removeKey: 'name'.
	transport enqueueResponse: result.

	self should: [client connect] raise: Error.
	self deny: client isConnected.
	self assert: transport notifications isEmpty
]

{ #category : 'Validation' }
TestMcpClient >> testConnectRejectsMissingServerVersion [
	"Initialization requires a nonempty server version."

	| result |

	result := self validInitializeResult.
	(result at: 'serverInfo') removeKey: 'version'.
	transport enqueueResponse: result.

	self should: [client connect] raise: Error.
	self deny: client isConnected.
	self assert: transport notifications isEmpty
]

{ #category : 'Validation' }
TestMcpClient >> testConnectRejectsNonObjectResult [
	"Initialization requires a JSON object result."

	transport enqueueResponse: #().

	self should: [client connect] raise: Error.
	self deny: client isConnected.
	self assert: transport notifications isEmpty
]

{ #category : 'Validation' }
TestMcpClient >> testConnectRejectsUnsupportedNegotiatedVersion [
	"Initialization rejects a protocol version the client does not support."

	| result |

	result := self validInitializeResult.
	result at: 'protocolVersion' put: '1900-01-01'.
	transport enqueueResponse: result.

	self should: [client connect] raise: Error.
	self deny: client isConnected.
	self assert: transport notifications isEmpty
]

{ #category : 'Protocol Operations' }
TestMcpClient >> testConnectSendsInitializeThenInitialized [
	"Connecting performs the ordered MCP initialization handshake."

	| request notification parameters firstInteraction secondInteraction |

	transport enqueueResponse: self validInitializeResult.
	client connect.

	self assert: transport interactions size equals: 2.
	firstInteraction := transport interactions first.
	secondInteraction := transport interactions last.
	self assert: (firstInteraction at: 'kind') equals: 'request'.
	self assert: (secondInteraction at: 'kind') equals: 'notification'.

	request := firstInteraction at: 'message'.
	self assert: request size equals: 4.
	self assert: (request at: 'jsonrpc') equals: '2.0'.
	self assert: (request at: 'id') equals: 1.
	self assert: (firstInteraction at: 'identifier') equals: 1.
	self assert: (request at: 'method') equals: 'initialize'.
	parameters := request at: 'params'.
	self assert: parameters size equals: 3.
	self
		assert: (parameters at: 'protocolVersion')
		equals: McpClient supportedHandshakeProtocolVersions first.
	self assert: (parameters at: 'capabilities') isEmpty.
	self assert: ((parameters at: 'clientInfo') at: 'name') equals: 'VastMcpClient'.
	self assert: ((parameters at: 'clientInfo') at: 'version') equals: '1.0.0'.

	notification := secondInteraction at: 'message'.
	self assert: notification size equals: 3.
	self assert: (notification at: 'jsonrpc') equals: '2.0'.
	self assert: (notification at: 'method') equals: 'notifications/initialized'.
	self assert: (notification at: 'params') isEmpty.
	self deny: (notification includesKey: 'id').

	self assert: client isConnected.
	self assert: client protocolVersion equals: '2025-11-25'.
	self assert: (client serverCapabilities includesKey: 'tools').
	self assert: (client serverInfo at: 'name') equals: 'ScriptedServer'.
	self assert: (client serverInfo at: 'version') equals: '1.0.0'
]

{ #category : 'Copying' }
TestMcpClient >> testConnectSnapshotsNegotiatedValues [
	"Negotiated state is isolated from response and accessor mutation."

	| result capabilities returnedCapabilities returnedInfo |

	result := self validInitializeResult.
	capabilities := result at: 'capabilities'.
	transport enqueueResponse: result.
	client connect.

	capabilities removeKey: 'tools'.
	(result at: 'serverInfo') at: 'name' put: 'ChangedServer'.
	self assert: (client serverCapabilities includesKey: 'tools').
	self assert: (client serverInfo at: 'name') equals: 'ScriptedServer'.

	returnedCapabilities := client serverCapabilities.
	returnedInfo := client serverInfo.
	returnedCapabilities removeKey: 'tools'.
	returnedInfo at: 'name' put: 'ChangedAgain'.
	self assert: (client serverCapabilities includesKey: 'tools').
	self assert: (client serverInfo at: 'name') equals: 'ScriptedServer'
]

{ #category : 'Protocol Operations' }
TestMcpClient >> testInMemoryClientConnectAndToolExecution [
	"An McpClient connected via in-memory transport executes tools directly."

	| server tool inMemoryClient tools result |

	server :=
		McpServer new
			name: 'InMemoryTestServer';
			version: '1.0.0';
			yourself.
	tool :=
		McpBlockTool new
			name: 'square';
			description: 'Square a number';
			inputSchema: (EsOrderedDictionary with: 'type' -> 'object');
			block: [:args | | n |
				n := args at: 'n'.
				(n * n) printString];
			yourself.
	server toolRegistry registerTool: tool.

	inMemoryClient := McpClient forServer: server mode: #auto.
	[
		self assert: inMemoryClient isConnected.
		self assert: (McpProtocolVersion isModern: inMemoryClient protocolVersion).
		tools := inMemoryClient listTools.
		self assert: (tools anySatisfy: [:each | (each at: 'name') = 'square']).
		result := inMemoryClient callTool: 'square' arguments: (EsOrderedDictionary with: 'n' -> 5).
		self assert: (result at: 'isError') equals: false.
		self assert: (((result at: 'content') first at: 'text') includesSubstring: '25')]
			ensure: [inMemoryClient close]
]

{ #category : 'Testing' }
TestMcpClient >> testModernRequestStampsMetaEnvelope [
	"Requests in 2026-07-28 stamp io.modelcontextprotocol/* metadata keys."

	| discoverResult toolResult request params meta content |

	discoverResult :=
		EsOrderedDictionary new
			at: 'capabilities' put: (EsOrderedDictionary with: 'tools' ->
				EsOrderedDictionary new);
			at: 'supportedVersions' put: #('2026-07-28' '2025-11-25');
			at: 'resultType' put: 'complete';
			at: 'cacheScope' put: 'public';
			at: 'ttlMs' put: 0;
			at: '_meta'
				put: (
					EsOrderedDictionary with:
						'io.modelcontextprotocol/serverInfo' -> (
							EsOrderedDictionary
								with: 'name' -> 'ModernServer'
								with: 'version' -> '2.0.0'));
			yourself.
	content :=
		EsOrderedDictionary new
			at: 'type' put: 'text';
			at: 'text' put: 'ok';
			yourself.
	toolResult :=
		EsOrderedDictionary new
			at: 'content' put: (Array with: content);
			at: 'resultType' put: 'complete';
			at: 'isError' put: false;
			yourself.
	transport enqueueResponse: discoverResult.
	transport enqueueResponse: toolResult.
	transport enqueueResponse: (EsOrderedDictionary with: 'tools' -> #()).
	client mode: #modern.
	client connect.
	client callTool: 'test.tool' arguments: (EsOrderedDictionary with: 'arg' ->
		'value').

	request := transport interactions second at: 'message'.
	self assert: (request at: 'method') equals: 'tools/call'.
	params := request at: 'params'.
	self assert: (params at: 'name') equals: 'test.tool'.
	meta := params at: '_meta'.
	self assert: (meta at: 'io.modelcontextprotocol/protocolVersion') equals:
		'2026-07-28'.
	self assert: (meta includesKey:
		'io.modelcontextprotocol/clientCapabilities').
	self assert: ((meta at: 'io.modelcontextprotocol/clientInfo') at: 'name')
		equals: 'VastMcpClient'

]

{ #category : 'Protocol Operations' }
TestMcpClient >> testPingFailsWhenConnectedInModernMode [
	"Client ping is removed in protocol version 2026-07-28."

	| discoverResult |

	discoverResult :=
		EsOrderedDictionary new
			at: 'capabilities' put: (EsOrderedDictionary with: 'tools' -> EsOrderedDictionary new);
			at: 'supportedVersions' put: #('2026-07-28');
			at: 'resultType' put: 'complete';
			at: 'cacheScope' put: 'public';
			at: 'ttlMs' put: 0;
			at: '_meta'
				put: (
					EsOrderedDictionary with:
						'io.modelcontextprotocol/serverInfo' -> (
							EsOrderedDictionary
								with: 'name' -> 'ModernServer'
								with: 'version' -> '2.0.0'));
			yourself.
	transport enqueueResponse: discoverResult.
	client mode: #modern.
	client connect.
	self should: [client ping] raise: Error
]

{ #category : 'Protocol Operations' }
TestMcpClient >> testPingRequiresConnection [
	"Ping is unavailable before protocol initialization completes."

	self should: [client ping] raise: Error.
	self assert: transport interactions isEmpty
]

{ #category : 'Protocol Operations' }
TestMcpClient >> testPingUsesNextRequestIdentifier [
	"Ping follows initialization in the request identifier sequence."

	| pingRequest |

	transport enqueueResponse: self validInitializeResult.
	transport enqueueResponse: EsOrderedDictionary new.
	client connect.
	client ping.

	self assert: transport requests size equals: 2.
	self assert: (transport requests first at: 'id') equals: 1.
	pingRequest := transport requests last.
	self assert: pingRequest size equals: 4.
	self assert: (pingRequest at: 'jsonrpc') equals: '2.0'.
	self assert: (pingRequest at: 'id') equals: 2.
	self assert: (pingRequest at: 'method') equals: 'ping'.
	self assert: (pingRequest at: 'params') isEmpty
]

{ #category : 'Configuration' }
TestMcpClient >> testTransportCannotBeSharedBetweenClients [
	"A transport has at most one owning client."

	| anotherClient |

	anotherClient := McpClient new.
	self should: [anotherClient transport: transport] raise: Error.
	self assert: client transport == transport.
	self assert: transport client == client
]

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpClient >> validInitializeResult [
	"Answer a valid MCP initialization result for client lifecycle tests.

	 Answers:
		<KeyedCollection>."

	^EsOrderedDictionary new
		at: 'protocolVersion' put: '2025-11-25';
		at: 'capabilities' put: (EsOrderedDictionary with: 'tools' -> EsOrderedDictionary new);
		at: 'serverInfo'
			put: (EsOrderedDictionary with: 'name' -> 'ScriptedServer' with: 'version' -> '1.0.0');
		yourself
]
