"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# McpHttpServer

`McpHttpServer` configures and owns an SST HTTP endpoint for an MCP server,
supporting both Streamable HTTP and dual-endpoint SSE.

## Responsibilities

- Bind dispatcher and transport behavior to servlet endpoints:
  - Streamable HTTP at `/mcp` (`McpHttpServlet`)
  - Legacy dual-endpoint SSE at `/sse` and `/messages` (`McpSseServlet`)
- Enforce transport security policies including allowed origins and Host
  header validation (`allowedHosts`) to prevent DNS rebinding attacks.
- Enforce Bearer token authentication via `authSettings`.
- Apply request-size, session, host, and port configuration.

## Lifecycle and boundaries

Start and stop explicitly; one instance owns its engine and endpoint.
"
Class {
	#name : 'McpHttpServer',
	#superclass : 'Object',
	#instVars : [
		'host',
		'port',
		'endpointPath',
		'mcpServer',
		'dispatcher',
		'servletEngine',
		'allowedOrigins',
		'maximumRequestSize',
		'requestContextFactory',
		'activeTransport',
		'allowedHosts',
		'sseTransport',
		'authSettings',
		'sessionIdleTimeout',
		'maxSessions'
	],
	#category : 'McpHttpServerSubApp'
}

{ #category : 'Instance Creation' }
McpHttpServer class >> new [
	"Answer a new initialized HTTP server configuration.

	 Answers:
		<McpHttpServer>."

	^super new initialize
]

{ #category : 'Accessing' }
McpHttpServer >> allowedHosts [
	"Answer the set of allowed Host header values for DNS rebinding protection.

	 Answers:
		<Set> of <String>."

	allowedHosts ifNil: [allowedHosts := Set new].
	^allowedHosts copy
]

{ #category : 'Accessing' }
McpHttpServer >> allowedHosts: aCollection [
	"Set the allowed Host header values for DNS rebinding protection.

	 Arguments:
		aCollection - <Collection> of <String> hostnames or patterns.
	 Answers:
		<McpHttpServer> the receiver."

	| newHosts |

	newHosts := Set new.
	aCollection do: [:each |
		(each isString and: [each isEmpty not])
			ifFalse: [self error: 'Allowed host must be a nonempty string'].
		newHosts add: each copy].
	allowedHosts := newHosts.
	activeTransport ifNotNil: [:t | t allowedHosts: allowedHosts].
	^self
]

{ #category : 'Accessing' }
McpHttpServer >> allowedOrigins [
	"Answer a deeply detached snapshot of allowed HTTP Origin values.

	 Answers:
		<Collection> of <String>."

	| snapshot |

	snapshot := Set new.
	allowedOrigins do: [:origin | snapshot add: origin copy].
	^snapshot
]

{ #category : 'Accessing' }
McpHttpServer >> allowedOrigins: aCollection [
	"Validate and retain a detached Origin allowlist.

	 Arguments:
		aCollection - <Collection> of nonempty <String> origins.
	 Answers:
		<McpHttpServer> the receiver."

	| snapshot |

	(aCollection isCollection and: [aCollection isString not])
		ifFalse: [self error: 'Allowed Origins must be a collection'].
	snapshot := Set new.
	aCollection do: [:origin |
		(origin isString and: [origin isEmpty not])
			ifFalse: [self error: 'Allowed Origins must contain only nonempty strings'].
		snapshot add: origin copy].
	activeTransport ifNotNil: [activeTransport allowedOrigins: snapshot].
	allowedOrigins := snapshot.
	^self
]

{ #category : 'Accessing' }
McpHttpServer >> authSettings [
	"Answer the OAuth authentication settings, or nil.

	 Answers:
		<McpAuthSettings> or nil."

	^authSettings
]

{ #category : 'Configuration' }
McpHttpServer >> authSettings: anAuthSettings [
	"Set the OAuth authentication settings.

	 Arguments:
		anAuthSettings - <McpAuthSettings> or nil.
	 Answers:
		<McpHttpServer> the receiver."

	anAuthSettings ifNotNil: [anAuthSettings validateConfiguration].
	authSettings := anAuthSettings.
	activeTransport ifNotNil: [:t | t authSettings: anAuthSettings].
	sseTransport ifNotNil: [:st | st authSettings: anAuthSettings].
	^self

]

{ #category : 'Dispatching' }
McpHttpServer >> dispatcher [
	"Answer the JSON-RPC dispatcher, creating it when necessary.

	 Answers:
		<McpJsonRpcDispatcher>."

	dispatcher ifNil: [
		dispatcher := McpJsonRpcDispatcher new.
		mcpServer ifNotNil: [dispatcher server: mcpServer]].
	^dispatcher
]

{ #category : 'Dispatching' }
McpHttpServer >> dispatcher: anMcpDispatcher [
	"Set the dispatcher and update the active transport.

	 Arguments:
		anMcpDispatcher - <McpJsonRpcDispatcher> dispatcher.
	 Answers:
		<McpHttpServer> the receiver."

	(anMcpDispatcher isKindOf: McpJsonRpcDispatcher)
		ifFalse: [self error: 'Dispatcher must be an McpJsonRpcDispatcher'].
	dispatcher := anMcpDispatcher.
	mcpServer ifNotNil: [dispatcher server: mcpServer].
	activeTransport ifNotNil: [activeTransport dispatcher: dispatcher].
	^self
]

{ #category : 'Accessing' }
McpHttpServer >> endpointPath [
	"Answer a detached servlet path for the MCP endpoint.

	 Answers:
		<String> absolute HTTP path."

	^endpointPath copy
]

{ #category : 'Accessing' }
McpHttpServer >> endpointPath: aString [
	"Set the servlet path before the listener starts.

	 Arguments:
		aString - <String> nonempty absolute path without query or fragment.
	 Answers:
		<McpHttpServer> the receiver."

	self isRunning ifTrue: [self error: 'MCP endpoint path cannot change while running'].
	(aString isString and: [aString isEmpty not])
		ifFalse: [self error: 'MCP endpoint path must be a nonempty string'].
	aString first = $/ ifFalse: [self error: 'MCP endpoint path must begin with a slash'].
	((aString includes: $?) or: [aString includes: $#])
		ifTrue: [self error: 'MCP endpoint path must not contain query or fragment'].
	endpointPath := aString copy.
	^self
]

{ #category : 'Accessing' }
McpHttpServer >> host [
	"Answer a detached host address used by the SST listener.

	 Answers:
		<String>."

	^host copy
]

{ #category : 'Accessing' }
McpHttpServer >> host: aString [
	"Set the listener host before the listener starts.

	 Arguments:
		aString - <String> nonempty host name or address.
	 Answers:
		<McpHttpServer> the receiver."

	self isRunning ifTrue: [self error: 'MCP listener host cannot change while running'].
	(aString isString and: [aString isEmpty not])
		ifFalse: [self error: 'MCP listener host must be a nonempty string'].
	host := aString copy.
	^self
]

{ #category : 'Initialization',
  #vaVisibility : 'private' }
McpHttpServer >> initialize [
	"Initialize secure listener and request-context defaults.

	 Answers:
		<McpHttpServer> the receiver."

	super initialize.
	host := '127.0.0.1'.
	port := 8080.
	endpointPath := '/mcp'.
	allowedOrigins := Set new.
	allowedHosts := Set new.
	maximumRequestSize := 10 * 1024 * 1024.
	requestContextFactory := nil.
	activeTransport := nil.
	sessionIdleTimeout := 1800.
	maxSessions := 10000.
	^self

]

{ #category : 'Validation' }
McpHttpServer >> isLoopbackHost [
	"Answer whether the configured listener host is a loopback address.

	 Answers:
		<Boolean>."

	^McpHttpServerTransport isLocalhostHost: self host
]

{ #category : 'Accessing' }
McpHttpServer >> isRunning [
	"Answer whether the configured SST servlet engine is running.

	 Answers:
		<Boolean>."

	^servletEngine notNil and: [servletEngine isRunning]
]

{ #category : 'Accessing' }
McpHttpServer >> maxSessions [
	"Answer the maximum retained legacy sessions; nil disables the limit.
	Answers:
		<Number | nil> configured limit."
	^maxSessions

]

{ #category : 'Configuration' }
McpHttpServer >> maxSessions: limit [
	"Set the maximum retained legacy sessions; nil disables it.
	Arguments:
		limit - <Number | nil> positive finite limit.
	Answers:
		<McpHttpServer> the receiver."
	(limit isNil or: [(limit isInteger and: [limit > 0])])
		ifFalse: [self error: 'Invalid maxSessions'].
	maxSessions := limit.
	activeTransport ifNotNil: [:current | current maxSessions: limit]

]

{ #category : 'Accessing' }
McpHttpServer >> maximumRequestSize [
	"Answer the maximum accepted JSON request size in bytes.

	 Answers:
		<Integer>."

	^maximumRequestSize
]

{ #category : 'Accessing' }
McpHttpServer >> maximumRequestSize: byteCount [
	"Set the request limit and update the active transport.

	 Arguments:
		byteCount - <Integer> positive byte count.
	 Answers:
		<McpHttpServer> the receiver."

	byteCount isInteger ifFalse: [self error: 'Maximum request size must be an integer'].
	byteCount > 0 ifFalse: [self error: 'Maximum request size must be positive'].
	maximumRequestSize := byteCount.
	activeTransport ifNotNil: [activeTransport maximumRequestSize: byteCount].
	^self
]

{ #category : 'Accessing' }
McpHttpServer >> mcpServer [
	"Answer the transport-neutral MCP server.

	 Answers:
		<McpServer> or nil."

	^mcpServer
]

{ #category : 'Accessing' }
McpHttpServer >> mcpServer: anMcpServer [
	"Set the transport-neutral MCP server used for dispatch.

	 Arguments:
		anMcpServer - <McpServer> configured protocol server.
	 Answers:
		<McpHttpServer> the receiver."

	(anMcpServer isKindOf: McpServer) ifFalse: [self error: 'MCP server must be an McpServer'].
	mcpServer := anMcpServer.
	self dispatcher server: anMcpServer.
	^self
]

{ #category : 'Accessing' }
McpHttpServer >> port [
	"Answer the TCP port used by the SST listener.

	 Answers:
		<Integer>."

	^port
]

{ #category : 'Accessing' }
McpHttpServer >> port: anInteger [
	"Set the TCP port before the listener starts.

	 Arguments:
		anInteger - <Integer> from 1 through 65535.
	 Answers:
		<McpHttpServer> the receiver."

	self isRunning ifTrue: [self error: 'MCP listener port cannot change while running'].
	anInteger isInteger ifFalse: [self error: 'MCP listener port must be an integer'].
	(anInteger between: 1 and: 65535)
		ifFalse: [self error: 'MCP listener port must be between 1 and 65535'].
	port := anInteger.
	^self
]

{ #category : 'Accessing' }
McpHttpServer >> requestContextFactory [
	"Answer the optional authenticated request-context factory.

	 Answers:
		<Block> accepting request and session, or nil."

	^requestContextFactory
]

{ #category : 'Accessing' }
McpHttpServer >> requestContextFactory: aBlock [
	"Set the request-context factory and update the active transport.

	 Arguments:
		aBlock - <Block> accepting request and session, or nil.
	 Answers:
		<McpHttpServer> the receiver."

	(aBlock notNil and: [aBlock isBlock not or: [aBlock numArgs ~= 2]])
		ifTrue: [self error: 'MCP request-context factory must accept request and session'].
	requestContextFactory := aBlock.
	activeTransport ifNotNil: [activeTransport requestContextFactory: aBlock].
	^self
]

{ #category : 'Configuration' }
McpHttpServer >> servletConfig [

	| appName |

	appName := 'McpApp_' , self port printString.
	^SstWebAppSpecification new
		appName: appName;
		contextPath: '/';
		defineServlet: 'McpHttpServlet' as: 'mcpServlet';
		addServletMap: self endpointPath forServletNamed: 'mcpServlet';
		defineServlet: 'McpSseServlet' as: 'sseServlet';
		addServletMap: self sseTransport sseEndpointPath forServletNamed: 'sseServlet';
		addServletMap: self sseTransport endpointPath forServletNamed: 'sseServlet';
		addServletMap: self sseTransport endpointPath , '/*' forServletNamed: 'sseServlet';
		yourself
]

{ #category : 'Accessing' }
McpHttpServer >> sessionIdleTimeout [
	"Answer the idle timeout in seconds; nil disables the limit.
	Answers:
		<Number | nil> configured limit."
	^sessionIdleTimeout

]

{ #category : 'Configuration' }
McpHttpServer >> sessionIdleTimeout: limit [
	"Set the idle timeout in seconds; nil disables it.
	Arguments:
		limit - <Number | nil> positive finite limit.
	Answers:
		<McpHttpServer> the receiver."
	(limit isNil or: [(limit isNumber and: [limit > 0 and: [limit asFloat
		isFinite]])])
		ifFalse: [self error: 'Invalid sessionIdleTimeout'].
	sessionIdleTimeout := limit.
	activeTransport ifNotNil: [:current | current sessionIdleTimeout: limit]

]

{ #category : 'Configuration' }
McpHttpServer >> sseTransport [
	"Answer the SSE server transport configured for this server.

	 Answers:
		<McpSseServerTransport>."

	sseTransport ifNil: [
		sseTransport :=
			McpSseServerTransport new
				mcpServer: self mcpServer;
				authSettings: self authSettings;
				allowedHosts: self allowedHosts;
				allowedOrigins: self allowedOrigins;
				maximumRequestSize: self maximumRequestSize;
				requestContextFactory: self requestContextFactory;
				yourself].
	^sseTransport

]

{ #category : 'Accessing' }
McpHttpServer >> sseTransport: anSseTransport [
	"Set the SSE server transport.

	 Arguments:
		anSseTransport - <McpSseServerTransport>.
	 Answers:
		<McpHttpServer> the receiver."

	sseTransport := anSseTransport.
	^self
]

{ #category : 'Execution' }
McpHttpServer >> start [
	"Configure and start the SST servlet engine for the MCP endpoints.

	 The transport-neutral server must be set before startup. Failed listener
	 configuration or startup discards the candidate transport and engine.

	 Answers:
		<McpHttpServer> the receiver."

	| config url candidateEngine handlerResult startupResult |

	self isRunning ifTrue: [^self].
	self mcpServer ifNil: [self error: 'MCP server must be configured before startup'].
	self validateHostConfiguration.
	url := ('http://' , self host , ':' , self port printString) sstAsUrl.
	config := self servletConfig.
	config atContextParameter: 'mcpTransport' put: self transport.
	config atContextParameter: 'sseTransport' put: self sseTransport.
	candidateEngine :=
		SstHttpServletEngine new
			addServletContext: (SstServletContext fromConfiguration: config);
			yourself.
	handlerResult := candidateEngine addHandlerUrl: (url copy path: '/').
	handlerResult isSstError
		ifTrue: [
			candidateEngine shutDown.
			activeTransport := nil.
			sseTransport := nil.
			self error: 'Failed to configure the SST HTTP listener: ' ,
				handlerResult printString].
	handlerResult configuration
		marshalWorkerManager: (SstWorkerManager high: 10 low: 2 strict: false).
	startupResult := candidateEngine startUp.
	startupResult isSstError
		ifTrue: [
			candidateEngine shutDown.
			activeTransport := nil.
			sseTransport := nil.
			self error: 'Failed to start the SST HTTP server: ' , startupResult
				printString].
	servletEngine := candidateEngine.
	self transport startSessionMaintenance.
	^self
]

{ #category : 'Resource Management' }
McpHttpServer >> stop [
	"Stop the listener and discard all transport sessions.

	 Answers:
		<McpHttpServer> the receiver."

	servletEngine ifNotNil: [servletEngine shutDown].
	servletEngine := nil.
	activeTransport ifNotNil: [activeTransport close].
	activeTransport := nil.
	sseTransport ifNotNil: [:st |
		st close.
		sseTransport := nil].
	^self

]

{ #category : 'Configuration' }
McpHttpServer >> transport [
	"Answer the one transport configured for the active server lifecycle.

	 Answers:
		<McpStreamableHttpTransport>."

	activeTransport ifNil: [
		activeTransport :=
			McpStreamableHttpTransport new
				dispatcher: self dispatcher;
				authSettings: self authSettings;
				sessionIdleTimeout: self sessionIdleTimeout;
				maxSessions: self maxSessions;
				allowedOrigins: self allowedOrigins;
				allowedHosts: self allowedHosts;
				maximumRequestSize: self maximumRequestSize;
				requestContextFactory: self requestContextFactory;
				yourself].
	^activeTransport

]

{ #category : 'Validation' }
McpHttpServer >> validateHostConfiguration [
	"Validate that the server host configuration provides DNS rebinding protection.
	 When bound to a non-loopback host or wildcard (0.0.0.0), allowedHosts should be explicitly configured.

	 Raises:
		<McpDeprecationWarning> when bound to a non-loopback host without explicit allowedHosts."

	(self isLoopbackHost not and: [self allowedHosts isEmpty])
		ifTrue: [
			McpDeprecationWarning signal:
				'Server bound to non-loopback host without explicit allowedHosts; DNS rebinding protection requires configuring allowedHosts']
]
