"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# TestMcpHttpServerConfiguration

`TestMcpHttpServerConfiguration` verifies offline HTTP server configuration.

## Responsibilities

- Verify secure listener defaults and validation boundaries.
- Verify detached Origin configuration and active-transport propagation.
- Verify dispatcher, request limit, and context-factory propagation.
- Verify transport ownership without opening a listener.

Each test owns a fresh server. Tests do not start SST, bind ports, create
background work, or depend on timing.
"
Class {
	#name : 'TestMcpHttpServerConfiguration',
	#superclass : 'TestCase',
	#instVars : [
		'server'
	],
	#category : 'McpHttpServerTests'
}

{ #category : 'Initialization' }
TestMcpHttpServerConfiguration >> setUp [
	"Create a fresh server configuration without starting its listener."

	super setUp.
	server := McpHttpServer new
]

{ #category : 'Configuration' }
TestMcpHttpServerConfiguration >> testAllowedHostsAreDetachedAndPropagated [
	"Host allowlist is isolated and propagated to the active transport."

	| transport hosts |

	transport := server transport.
	hosts := OrderedCollection with: 'localhost' with: '127.0.0.1:8080'.
	server allowedHosts: hosts.
	hosts add: 'evil.example'.
	self assert: (server allowedHosts includes: 'localhost').
	self assert: (server allowedHosts includes: '127.0.0.1:8080').
	self deny: (server allowedHosts includes: 'evil.example').
	self assert: (transport allowedHosts includes: 'localhost').
	self assert: (transport allowedHosts includes: '127.0.0.1:8080')
]

{ #category : 'Copying' }
TestMcpHttpServerConfiguration >> testAllowedOriginsAreDeeplyDetachedAndPropagated [
	"Origin values are isolated at assignment and access boundaries."

	| transport source origin returned returnedOrigin |

	transport := server transport.
	origin := 'https://allowed.example' copy.
	source := OrderedCollection with: origin.
	server allowedOrigins: source.
	origin at: 1 put: $X.
	source add: 'https://later.example'.
	self assert: (server allowedOrigins includes: 'https://allowed.example').
	self assert: server allowedOrigins size equals: 1.
	self assert: (transport allowedOrigins includes: 'https://allowed.example').
	returned := server allowedOrigins.
	returnedOrigin := returned detect: [:each | true].
	returnedOrigin at: 1 put: $Y.
	returned add: 'https://returned.example'.
	self assert: (server allowedOrigins includes: 'https://allowed.example').
	self assert: server allowedOrigins size equals: 1
]

{ #category : 'Validation' }
TestMcpHttpServerConfiguration >> testAllowedOriginsRejectInvalidValuesTransactionally [
	"Invalid allowlists leave server and active transport state unchanged."

	| transport |

	transport := server transport.
	server allowedOrigins: #('https://safe.example').
	self should: [server allowedOrigins: 'https://wrong.example'] raise: Error.
	self should: [server allowedOrigins: #('')] raise: Error.
	self should: [server allowedOrigins: #(1)] raise: Error.
	self assert: server allowedOrigins equals: (Set with: 'https://safe.example').
	self assert: transport allowedOrigins equals: (Set with: 'https://safe.example')
]

{ #category : 'Configuration' }
TestMcpHttpServerConfiguration >> testDefaultConfigurationIsSecureAndStopped [
	"A new server uses loopback and conservative request defaults."

	self assert: server host equals: '127.0.0.1'.
	self assert: server port equals: 8080.
	self assert: server endpointPath equals: '/mcp'.
	self assert: server maximumRequestSize equals: 10 * 1024 * 1024.
	self assert: server allowedOrigins isEmpty.
	self assert: server requestContextFactory equals: nil.
	self deny: server isRunning
]

{ #category : 'Validation' }
TestMcpHttpServerConfiguration >> testDispatcherAndServerTypesAreValidated [
	"Only protocol dispatcher and server collaborators may be configured."

	| dispatcher protocolServer transport |

	dispatcher := McpJsonRpcDispatcher new.
	protocolServer := McpServer new.
	transport := server transport.
	self should: [server dispatcher: Object new] raise: Error.
	self should: [server mcpServer: Object new] raise: Error.
	server dispatcher: dispatcher.
	server mcpServer: protocolServer.
	self assert: server dispatcher == dispatcher.
	self assert: server mcpServer == protocolServer.
	self assert: transport dispatcher == dispatcher
]

{ #category : 'Validation' }
TestMcpHttpServerConfiguration >> testEndpointPathIsValidatedAndDetached [
	"The endpoint is an absolute path without query or fragment."

	| path returned |

	path := '/rpc' copy.
	server endpointPath: path.
	path at: 2 put: $X.
	self assert: server endpointPath equals: '/rpc'.
	returned := server endpointPath.
	returned at: 2 put: $Y.
	self assert: server endpointPath equals: '/rpc'.
	self should: [server endpointPath: 'rpc'] raise: Error.
	self should: [server endpointPath: ''] raise: Error.
	self should: [server endpointPath: '/rpc?x=1'] raise: Error.
	self should: [server endpointPath: '/rpc#part'] raise: Error
]

{ #category : 'Validation' }
TestMcpHttpServerConfiguration >> testHostIsValidatedAndDetached [
	"The listener host must be a nonempty string retained by value."

	| host returned |

	host := 'localhost' copy.
	server host: host.
	host at: 1 put: $X.
	self assert: server host equals: 'localhost'.
	returned := server host.
	returned at: 1 put: $Y.
	self assert: server host equals: 'localhost'.
	self should: [server host: ''] raise: Error.
	self should: [server host: 127] raise: Error
]

{ #category : 'Validation' }
TestMcpHttpServerConfiguration >> testLoopbackHostDoesNotWarnOnEmptyAllowedHosts [
	"A server configured with a loopback host does not warn when allowedHosts is empty."

	server host: '127.0.0.1'.
	server validateHostConfiguration.
	server host: 'localhost'.
	server validateHostConfiguration.
	server host: '[::1]'.
	server validateHostConfiguration
]

{ #category : 'Configuration' }
TestMcpHttpServerConfiguration >> testMaximumRequestSizeIsValidatedAndPropagated [
	"A positive byte limit updates an already-created transport."

	| transport |

	transport := server transport.
	server maximumRequestSize: 4096.
	self assert: server maximumRequestSize equals: 4096.
	self assert: transport maximumRequestSize equals: 4096.
	self should: [server maximumRequestSize: 0] raise: Error.
	self should: [server maximumRequestSize: -1] raise: Error.
	self should: [server maximumRequestSize: 1.5] raise: Error
]

{ #category : 'Validation' }
TestMcpHttpServerConfiguration >> testNonLoopbackHostWarnsWhenAllowedHostsIsEmpty [
	"A server bound to 0.0.0.0 or a non-loopback host warns when allowedHosts is empty, but not when configured."

	server host: '0.0.0.0'.
	self should: [server validateHostConfiguration] raise: McpDeprecationWarning.

	server host: '192.168.1.100'.
	self should: [server validateHostConfiguration] raise: McpDeprecationWarning.

	server allowedHosts: #('192.168.1.100').
	server validateHostConfiguration
]

{ #category : 'Validation' }
TestMcpHttpServerConfiguration >> testPortIsValidated [
	"The listener port must be an integer in the TCP port range."

	server port: 65535.
	self assert: server port equals: 65535.
	self should: [server port: 0] raise: Error.
	self should: [server port: 65536] raise: Error.
	self should: [server port: 1.5] raise: Error
]

{ #category : 'Configuration' }
TestMcpHttpServerConfiguration >> testRequestContextFactoryIsValidatedAndPropagated [
	"A two-argument context factory updates the active transport."

	| transport factory |

	transport := server transport.
	factory := [:request :session | McpServerRequestContext new].
	server requestContextFactory: factory.
	self assert: server requestContextFactory == factory.
	self assert: transport requestContextFactory == factory.
	self should: [server requestContextFactory: [:request | request]] raise: Error.
	self should: [server requestContextFactory: Object new] raise: Error.
	server requestContextFactory: nil.
	self assert: transport requestContextFactory equals: nil
]

{ #category : 'Configuration' }
TestMcpHttpServerConfiguration >> testTransportIsInitializedAndMemoized [
	"One initialized transport is reused for the server lifecycle."

	| first second |

	first := server transport.
	second := server transport.
	self assert: first == second.
	self assert: first maximumRequestSize equals: 10 * 1024 * 1024.
	self assert: first allowedOrigins isEmpty.
	self assert: first requestContextFactory equals: nil.
	self assert: first dispatcher == server dispatcher
]
