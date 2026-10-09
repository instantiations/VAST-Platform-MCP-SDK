"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# TestMcpServerLifecycle

`TestMcpServerLifecycle` verifies server initialization, discovery, and base
operations.

## Responsibilities

- Verify modern discovery answering `DiscoverResult` over `server/discover`.
- Verify legacy protocol-version negotiation via `initialize`.
- Verify required initialization fields and parameter validation.
- Verify `ping` is supported on legacy but returns method not found on modern.

## Test isolation

Each test creates a fresh server and dispatcher. Transport session gating is
tested separately with the Streamable HTTP lifecycle.
"
Class {
	#name : 'TestMcpServerLifecycle',
	#superclass : 'TestCase',
	#instVars : [
		'server',
		'dispatcher'
	],
	#category : 'McpProtocolTests'
}

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpServerLifecycle >> assertErrorResponse: response code: expectedCode id: expectedIdentifier [
	"Assert the complete structural contract of a JSON-RPC error response."

	| error |

	self assert: response size equals: 3.
	self assert: (response at: 'jsonrpc') equals: '2.0'.
	self assert: (response at: 'id') equals: expectedIdentifier.
	self deny: (response includesKey: 'result').
	error := response at: 'error'.
	self assert: (error at: 'code') equals: expectedCode.
	self assert: (error at: 'message') isString.
	self deny: (error at: 'message') isEmpty
]

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpServerLifecycle >> initializeRequest [
	"Answer a valid initialize request with identifier one."

	^self requestMethod: 'initialize' params: self validInitializeParameters id: 1
]

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpServerLifecycle >> notificationMethod: methodName params: parameters [
	"Answer a JSON-RPC notification fixture."

	| notification |

	notification :=
		EsOrderedDictionary new
			at: 'jsonrpc' put: '2.0';
			at: 'method' put: methodName;
			yourself.
	parameters ifNotNil: [notification at: 'params' put: parameters].
	^notification
]

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpServerLifecycle >> requestMethod: methodName params: parameters id: identifier [
	"Answer a JSON-RPC request fixture."

	| request |

	request :=
		EsOrderedDictionary new
			at: 'jsonrpc' put: '2.0';
			at: 'id' put: identifier;
			at: 'method' put: methodName;
			yourself.
	parameters ifNotNil: [request at: 'params' put: parameters].
	^request
]

{ #category : 'Initialization' }
TestMcpServerLifecycle >> setUp [
	"Create a fresh configured server and dispatcher."

	super setUp.
	server := McpServer new.
	server
		name: 'LifecycleServer';
		version: '2.0.0'.
	dispatcher := McpJsonRpcDispatcher new.
	dispatcher server: server
]

{ #category : 'Protocol Operations' }
TestMcpServerLifecycle >> testInitializeNegotiatesRequestedSupportedVersion [
	"Initialization returns the requested version and server metadata."

	| response result capabilities |

	response := dispatcher dispatch: self initializeRequest.
	self assert: (response at: 'jsonrpc') equals: '2.0'.
	self assert: (response at: 'id') equals: 1.
	self deny: (response includesKey: 'error').
	result := response at: 'result'.
	self assert: result size equals: 3.
	self assert: (result at: 'protocolVersion') equals: '2025-11-25'.
	self assert: ((result at: 'serverInfo') at: 'name') equals: 'LifecycleServer'.
	self assert: ((result at: 'serverInfo') at: 'version') equals: '2.0.0'.
	capabilities := result at: 'capabilities'.
	self assert: (capabilities includesKey: 'tools').
	self assert: (capabilities includesKey: 'prompts').
	self assert: (capabilities includesKey: 'resources')
]

{ #category : 'Validation' }
TestMcpServerLifecycle >> testInitializeRejectsMalformedClientInfo [
	"Initialization requires nonempty client name and version strings."

	| invalidValues response |

	invalidValues :=
		Array
			with: (EsOrderedDictionary with: 'version' -> '1.0.0')
			with: (EsOrderedDictionary with: 'name' -> 'LifecycleClient')
			with: (EsOrderedDictionary with: 'name' -> '' with: 'version' -> '1.0.0')
			with: (EsOrderedDictionary with: 'name' -> 'LifecycleClient' with: 'version' -> '').
	invalidValues do: [:clientInfo | | parameters |
		parameters := self validInitializeParameters.
		parameters at: 'clientInfo' put: clientInfo.
		response := dispatcher dispatch: (self requestMethod: 'initialize' params: parameters id: 2).
		self assertErrorResponse: response code: -32602 id: 2]
]

{ #category : 'Validation' }
TestMcpServerLifecycle >> testInitializeRejectsMissingRequiredFields [
	"Initialization rejects each missing required parameter."

	| response |

	#('protocolVersion' 'capabilities' 'clientInfo') do: [:fieldName | | parameters |
		parameters := self validInitializeParameters.
		parameters removeKey: fieldName.
		response :=
			dispatcher dispatch: (self requestMethod: 'initialize' params: parameters id: fieldName).
		self assertErrorResponse: response code: -32602 id: fieldName]
]

{ #category : 'Validation' }
TestMcpServerLifecycle >> testInitializeRejectsNonStringProtocolVersion [
	"Initialization rejects a non-string protocol version."

	| parameters response |

	parameters := self validInitializeParameters.
	parameters at: 'protocolVersion' put: 20251125.
	response := dispatcher dispatch: (self requestMethod: 'initialize' params: parameters id: 3).
	self assertErrorResponse: response code: -32602 id: 3
]

{ #category : 'Protocol Operations' }
TestMcpServerLifecycle >> testInitializeSelectsSupportedVersionForUnknownProposal [
	"The server selects a supported version when the proposal is unknown."

	| parameters response result |

	parameters := self validInitializeParameters.
	parameters at: 'protocolVersion' put: '1900-01-01'.
	response := dispatcher dispatch: (self requestMethod: 'initialize' params: parameters id: 4).
	result := response at: 'result'.
	self
		assert: (result at: 'protocolVersion')
		equals: server supportedHandshakeProtocolVersions first
]

{ #category : 'Protocol Operations' }
TestMcpServerLifecycle >> testInitializedNotificationHasNoResponse [
	"The initialized lifecycle message is a one-way notification."

	| notification |

	notification :=
		self notificationMethod: 'notifications/initialized' params: EsOrderedDictionary new.
	self assert: (dispatcher dispatch: notification) equals: nil
]

{ #category : 'Protocol Operations' }
TestMcpServerLifecycle >> testPingFailsInModernProtocolVersion [
	"A ping request under protocol 2026-07-28 returns Method not found (-32601)."

	| response context |

	context :=
		McpServerRequestContext new
			protocolVersion: '2026-07-28';
			transportRequest: Object new;
			yourself.
	response :=
		dispatcher
			dispatch: (self requestMethod: 'ping' params: EsOrderedDictionary new id: 12)
			context: context.
	self assertErrorResponse: response code: -32601 id: 12
]

{ #category : 'Protocol Operations' }
TestMcpServerLifecycle >> testPingReturnsEmptyResult [
	"A ping request returns one correlated empty result object."

	| response |

	response :=
		dispatcher dispatch: (self requestMethod: 'ping' params: EsOrderedDictionary new id: 5).
	self assert: (response at: 'jsonrpc') equals: '2.0'.
	self assert: (response at: 'id') equals: 5.
	self assert: (response at: 'result') isEmpty.
	self deny: (response includesKey: 'error')
]

{ #category : 'Protocol Operations' }
TestMcpServerLifecycle >> testServerDiscoverAnswersCapabilitiesAndVersions [
	"server/discover answers capabilities, supportedVersions, and 2026 metadata."

	| response result meta |

	response :=
		dispatcher
			dispatch: (self requestMethod: 'server/discover' params: EsOrderedDictionary new id: 1).
	self assert: (response at: 'jsonrpc') equals: '2.0'.
	self assert: (response at: 'id') equals: 1.
	result := response at: 'result'.
	self assert: (result at: 'resultType') equals: 'complete'.
	self assert: (result at: 'cacheScope') equals: 'public'.
	self assert: (result at: 'ttlMs') equals: 0.
	self
		assert: (result at: 'supportedVersions')
		equals: McpProtocolVersion supportedProtocolVersions.
	self assert: (result includesKey: 'capabilities').
	meta := result at: '_meta'.
	self
		assert: ((meta at: 'io.modelcontextprotocol/serverInfo') at: 'name')
		equals: 'LifecycleServer'
]

{ #category : 'Protocol Operations' }
TestMcpServerLifecycle >> testSubscriptionsListenWithCanonicalFilterKeys [
	"Verify subscriptions/listen acknowledges canonical 2026-07-28 filter keys."

	| request response result notifications |

	request :=
		EsOrderedDictionary new
			at: 'jsonrpc' put: '2.0';
			at: 'id' put: 401;
			at: 'method' put: 'subscriptions/listen';
			at: 'params'
				put: (
					EsOrderedDictionary with:
						'notifications' -> (
							EsOrderedDictionary new
								at: 'toolsListChanged' put: true;
								at: 'promptsListChanged' put: true;
								at: 'resourcesListChanged' put: true;
								at: 'resourceSubscriptions' put: #('file:///test.txt');
								yourself));
			yourself.
	response := dispatcher dispatch: request.
	self assert: (response at: 'id') equals: 401.
	result := response at: 'result'.
	self assert: (result at: 'resultType') equals: 'complete'.
	notifications := result at: 'notifications'.
	self assert: (notifications at: 'toolsListChanged') equals: true.
	self assert: (notifications at: 'promptsListChanged') equals: true.
	self assert: (notifications at: 'resourcesListChanged') equals: true.
	self assert: (notifications at: 'resourceSubscriptions') equals: #('file:///test.txt')
]

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpServerLifecycle >> validInitializeParameters [
	"Answer valid client initialization parameters."

	^EsOrderedDictionary new
		at: 'protocolVersion' put: '2025-11-25';
		at: 'capabilities' put: EsOrderedDictionary new;
		at: 'clientInfo'
			put: (EsOrderedDictionary with: 'name' -> 'LifecycleClient' with: 'version' -> '1.0.0');
		yourself
]
