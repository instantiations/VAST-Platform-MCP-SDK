"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# McpClient

`McpClient` implements the transport-neutral MCP client protocol supporting
modern (`2026-07-28`), handshake-era (`2025-11-25`), and legacy (`2024-11-05`)
connections.

## Responsibilities

- Negotiate connections across multiple modes: `#auto`, `#modern`, `#legacy`.
- Bypass discovery round-trips when reconnecting using saved `priorDiscover`.
- Automatically attach required modern per-request `_meta` envelopes.
- Cache tool schemas during `listTools` and automatically emit `Mcp-Param-*`
  headers for annotated arguments (SEP-2243) on modern connections.
- Support pluggable client extensions via `extensions` and `addExtension:`.
- Drive client-side Multi-Round-Trip Request (MRTR) loops (`driveInputRequired:retryBlock:`).
- Subscribe to change event streams via `listen:do:` (`subscriptions/listen`).
- Cache idempotent responses via `McpClientResponseCache`.

## Lifecycle and boundaries

One client owns one transport and must be closed when disconnected.
"
Class {
	#name : 'McpClient',
	#superclass : 'Object',
	#instVars : [
		'clientInfo',
		'capabilities',
		'isConnected',
		'requestMutex',
		'connectionMutex',
		'nextRequestId',
		'notificationHandlers',
		'requestHandlers',
		'handlerMutex',
		'mode',
		'inputRequiredMaxRounds',
		'protocolVersion',
		'serverCapabilities',
		'serverInfo',
		'transport',
		'elicitationCallback',
		'samplingCallback',
		'rootsCallback',
		'progressCallbacks',
		'progressCallbacksMutex',
		'responseCache',
		'priorDiscover',
		'extensions',
		'knownToolSchemas',
		'knownToolOutputSchemas'
	],
	#pools : [
		'McpJsonRpcConstants'
	],
	#category : 'McpProtocol'
}

{ #category : 'Instance Creation' }
McpClient class >> auto [
	"Answer a new client instance configured for automatic discovery with fallback.

	 Answers:
		<McpClient>."

	^self new
		mode: #auto;
		yourself
]

{ #category : 'Instance Creation' }
McpClient class >> forServer: anMcpServer [
	"Answer a new McpClient connected in-memory to anMcpServer using auto mode.

	 Arguments:
		anMcpServer - <McpServer> server to connect to.
	 Answers:
		<McpClient> connected client."

	^self forServer: anMcpServer mode: #auto
]

{ #category : 'Instance Creation' }
McpClient class >> forServer: anMcpServer mode: aMode [
	"Answer a new McpClient connected in-memory to anMcpServer using aMode.

	 Arguments:
		anMcpServer - <McpServer> server to connect to.
		aMode - <Symbol> or <String> #auto, #modern, #legacy, or specific version string.
	 Answers:
		<McpClient> connected client."

	| client transport |

	client :=
		self new
			mode: aMode;
			yourself.
	transport := McpInMemoryClientTransport server: anMcpServer.
	client transport: transport.
	client connect.
	^client
]

{ #category : 'Instance Creation' }
McpClient class >> legacy [
	"Answer a new client instance configured for the legacy handshake era.

	 Answers:
		<McpClient>."

	^self new
		mode: #legacy;
		yourself
]

{ #category : 'Instance Creation' }
McpClient class >> modern [
	"Answer a new client instance configured for the modern 2026-07-28 protocol era.

	 Answers:
		<McpClient>."

	^self new
		mode: #modern;
		yourself
]

{ #category : 'Instance Creation' }
McpClient class >> new [
	"Answer a new initialized native MCP client.

	 Answers:
		<McpClient>."

	^super new initialize
]

{ #category : 'Accessing' }
McpClient class >> supportedHandshakeProtocolVersions [
	"Answer protocol versions supported via the initialize handshake in preference order.

	 Answers:
		<Array> of <String>."

	^McpProtocolVersion handshakeProtocolVersions
]

{ #category : 'Accessing' }
McpClient class >> supportedProtocolVersions [
	"Answer protocol versions supported by this client in preference order.

	 Answers:
		<Array> of <String>."

	^McpProtocolVersion supportedProtocolVersions
]

{ #category : 'Registration' }
McpClient >> addExtension: anExtension [
	"Register an extension on this client.

	 Arguments:
		anExtension - <McpExtension>.
	 Answers:
		<McpClient> the receiver."

	self extensions add: anExtension.
	^self
]

{ #category : 'Accessing' }
McpClient >> cacheMode [
	"Answer the active cache mode (#use, #refresh, #bypass).

	 Answers:
		<Symbol>."

	^self responseCache mode
]

{ #category : 'Accessing' }
McpClient >> cacheMode: aSymbol [
	"Set the active cache mode (#use, #refresh, #bypass).

	 Arguments:
		aSymbol - <Symbol> #use, #refresh, or #bypass.
	 Answers:
		<McpClient> the receiver."

	self responseCache mode: aSymbol.
	^self
]

{ #category : 'Caching',
  #vaVisibility : 'private' }
McpClient >> cacheParamsKeyFor: methodName params: parameters [
	"Compute the cache params key discriminator for this request.

	 Arguments:
		methodName - <String> MCP method.
		parameters - <KeyedCollection> parameters, or nil.
	 Answers:
		<String>."

	(parameters isNil or: [(parameters isKindOf: KeyedCollection) not]) ifTrue: [^''].
	methodName = 'resources/read' ifTrue: [^(parameters at: 'uri' ifAbsent: ['']) asString].
	parameters at: 'cursor' ifPresent: [:c | ^'cursor:' , c asString].
	^''
]

{ #category : 'Protocol Operations' }
McpClient >> callTool: toolName arguments: arguments [
	"Call a server tool without request-scoped headers.

	 Arguments:
		toolName - <String> nonempty tool name.
		arguments - <KeyedCollection> tool arguments, or nil.
	 Answers:
		<KeyedCollection> MCP CallToolResult."

	^self callTool: toolName arguments: arguments headers: nil
]

{ #category : 'Execution' }
McpClient >> callTool: toolName arguments: arguments headers: requestHeaders [
	"Call a server tool and answer a validated detached result, driving any InputRequiredResult rounds."

	^self
		callTool: toolName
		arguments: arguments
		headers: requestHeaders
		progressToken: nil
		progressCallback: nil
]

{ #category : 'Execution' }
McpClient >> callTool: toolName
	arguments: arguments
	headers: requestHeaders
	progressToken: aToken
	progressCallback: aBlock [
	"Call a server tool and answer a validated detached result with progress tracking.
	 On modern connections with header-capable transports, automatically emits Mcp-Param-* headers for annotated arguments.

	 Arguments:
		toolName - <String> nonempty tool name.
		arguments - <KeyedCollection> tool arguments, or nil.
		requestHeaders - <KeyedCollection> transport headers, or nil.
		aToken - <String> or <Integer> or nil.
		aBlock - <Block> or nil.
	 Answers:
		<KeyedCollection> detached MCP CallToolResult."

	| parameters initialResult result effectiveHeaders paramHeaders |

	(toolName isString and: [toolName isEmpty not])
		ifFalse: [self error: 'MCP tool name must be a nonempty string'].
	(arguments isNil or: [arguments isKindOf: KeyedCollection])
		ifFalse: [self error: 'MCP tool arguments must be a keyed collection or nil'].
	self requireServerCapability: 'tools' forOperation: 'tools/call'.
	parameters := EsOrderedDictionary with: 'name' -> toolName.
	arguments ifNotNil: [parameters at: 'arguments' put: arguments].

	effectiveHeaders :=
		requestHeaders ifNotNil: [requestHeaders copy] ifNil: [EsOrderedDictionary new].
	((McpProtocolVersion isModern: self protocolVersion)
		and: [self transport notNil and: [self transport supportsRequestHeaders]])
			ifTrue: [
				paramHeaders := self resolveParamHeadersForTool: toolName arguments: arguments.
				paramHeaders keysAndValuesDo: [:k :v |
					(effectiveHeaders includesKey: k) ifFalse: [effectiveHeaders at: k put: v]]].
	effectiveHeaders isEmpty ifTrue: [effectiveHeaders := nil].

	initialResult :=
		self
			sendRequest: 'tools/call'
			params: parameters
			headers: effectiveHeaders
			progressToken: aToken
			progressCallback: aBlock.
	result :=
		self
			driveInputRequired: initialResult
			retryBlock: [:inputResponses :requestState | | retryParams |
				retryParams := parameters copy.
				inputResponses ifNotNil: [retryParams at: 'inputResponses' put: inputResponses].
				requestState ifNotNil: [retryParams at: 'requestState' put: requestState].
				self
					sendRequest: 'tools/call'
					params: retryParams
					headers: effectiveHeaders
					progressToken: aToken
					progressCallback: aBlock].
	^self validatedToolResult: result forTool: toolName headers: requestHeaders
]

{ #category : 'Protocol Operations' }
McpClient >> callTool: toolName arguments: arguments progressCallback: aBlock [
	"Call a server tool with an asynchronous progress notification callback.

	 Arguments:
		toolName - <String> nonempty tool name.
		arguments - <KeyedCollection> tool arguments, or nil.
		aBlock - <Block> [:progress :total :message | ...].
	 Answers:
		<KeyedCollection> detached MCP CallToolResult."

	^self
		callTool: toolName
		arguments: arguments
		headers: nil
		progressToken: nil
		progressCallback: aBlock
]

{ #category : 'Protocol Operations' }
McpClient >> callTool: toolName arguments: arguments progressToken: aToken progressCallback: aBlock [
	"Call a server tool with an explicit progress token and progress callback.

	 Arguments:
		toolName - <String> nonempty tool name.
		arguments - <KeyedCollection> tool arguments, or nil.
		aToken - <String> or <Integer> progress correlation token.
		aBlock - <Block> [:progress :total :message | ...], or nil.
	 Answers:
		<KeyedCollection> detached MCP CallToolResult."

	^self
		callTool: toolName
		arguments: arguments
		headers: nil
		progressToken: aToken
		progressCallback: aBlock
]

{ #category : 'Protocol Operations' }
McpClient >> cancelRequest: anIdentifier [
	"Send a notifications/cancelled event to abort an active server request.

	 Arguments:
		anIdentifier - <String> or <Integer> request identifier to cancel.
	 Answers:
		<McpClient> the receiver."

	^self cancelRequest: anIdentifier reason: nil
]

{ #category : 'Protocol Operations' }
McpClient >> cancelRequest: anIdentifier reason: aReasonString [
	"Send a notifications/cancelled event to abort an active server request.

	 Arguments:
		anIdentifier - <String> or <Integer> request identifier to cancel.
		aReasonString - <String> or nil, optional explanation.
	 Answers:
		<McpClient> the receiver."

	| params |

	params := EsOrderedDictionary with: 'requestId' -> anIdentifier.
	aReasonString ifNotNil: [params at: 'reason' put: aReasonString copy].
	self sendNotification: 'notifications/cancelled' params: params.
	^self
]

{ #category : 'Accessing' }
McpClient >> capabilities [
	"Answer a detached snapshot of the configured client capabilities.

	 Answers:
		<KeyedCollection> JSON-compatible capability declaration."

	self extensions notEmpty
		ifTrue: [| extDict |
			extDict := EsOrderedDictionary new.
			self extensions do: [:ext | extDict at: ext identifier put: ext settings].
			capabilities at: 'extensions' put: extDict].
	^self detachedProtocolValue: capabilities
]

{ #category : 'Accessing' }
McpClient >> capabilities: aDictionary [
	"Validate and retain detached client capabilities before connection.

	 Arguments:
		aDictionary - <KeyedCollection> JSON-compatible capabilities.
	 Answers:
		<McpClient> the receiver."

	self isConnected ifTrue: [self error: 'Client capabilities cannot change while connected'].
	(aDictionary isKindOf: KeyedCollection)
		ifFalse: [self error: 'Client capabilities must be a keyed collection'].
	capabilities := self detachedProtocolValue: aDictionary.
	^self
]

{ #category : 'Validation',
  #vaVisibility : 'private' }
McpClient >> checkConnected [
	"Require completed MCP initialization before a protocol operation.

	 Answers:
		<McpClient> the receiver."

	self isConnected ifFalse: [self error: 'MCP client is not connected'].
	^self
]

{ #category : 'Session Management' }
McpClient >> clearCache [
	"Clear all cached response entries.

	 Answers:
		<McpClient> the receiver."

	self responseCache clear.
	^self
]

{ #category : 'Accessing' }
McpClient >> clientInfo [
	"Answer a detached snapshot of the configured client information.

	 Answers:
		<KeyedCollection> JSON-compatible implementation information."

	^self detachedProtocolValue: clientInfo
]

{ #category : 'Accessing' }
McpClient >> clientInfo: aDictionary [
	"Validate and retain detached client implementation information.

	 Arguments:
		aDictionary - <KeyedCollection> implementation name and version.
	 Answers:
		<McpClient> the receiver."

	| snapshot name version |

	self isConnected ifTrue: [self error: 'Client information cannot change while connected'].
	(aDictionary isKindOf: KeyedCollection)
		ifFalse: [self error: 'Client information must be a keyed collection'].
	snapshot := self detachedProtocolValue: aDictionary.
	name := snapshot at: 'name' ifAbsent: [nil].
	version := snapshot at: 'version' ifAbsent: [nil].
	(name isString and: [name isEmpty not])
		ifFalse: [self error: 'Client information requires a nonempty name'].
	(version isString and: [version isEmpty not])
		ifFalse: [self error: 'Client information requires a nonempty version'].
	clientInfo := snapshot.
	^self
]

{ #category : 'Execution' }
McpClient >> close [
	"Disconnect the client, terminate its transport, and clear negotiation.

	 The client becomes logically disconnected before transport shutdown but
	 retains negotiated values until the transport has sent session DELETE.
	 State cleanup completes even when transport shutdown signals.

	 Answers:
		<McpClient>."

	| transportToClose |

	self requestMutex critical: [
		isConnected := false.
		transportToClose := transport].
	[transportToClose ifNotNil: [transportToClose close]] ensure: [
		self requestMutex critical: [
			serverInfo := EsOrderedDictionary new.
			serverCapabilities := EsOrderedDictionary new.
			protocolVersion := nil.
			knownToolOutputSchemas := nil.
			knownToolSchemas := nil]].
	^self

]

{ #category : 'Execution' }
McpClient >> collectPaginatedMethod: methodName resultKey: resultKey [
	"Collect validated detached definitions from a paginated operation.

	 Arguments:
		methodName - <String> JSON-RPC method name.
		resultKey - <String> array field in each result page.
	 Answers:
		<Array> detached protocol definitions."

	| items cursor seenCursors parameters result pageItems nextCursor |

	self checkConnected.
	items := OrderedCollection new.
	seenCursors := Set new.
	cursor := nil.
	[
		parameters := EsOrderedDictionary new.
		cursor ifNotNil: [parameters at: 'cursor' put: cursor].
		result := self sendRequest: methodName params: parameters.
		(result isKindOf: KeyedCollection)
			ifFalse: [self error: 'Invalid ' , methodName ,
				' result: expected an object'].
		pageItems := result at: resultKey ifAbsent: [nil].
		(self isProtocolArray: pageItems)
			ifFalse: [self error: 'Invalid ' , methodName ,
				' result: expected an array'].
		pageItems do: [:item |
			self validateListedDefinition: item forMethod: methodName.
			(methodName = 'tools/list' and: [item isKindOf: KeyedCollection])
				ifTrue: [
					(item at: 'name' ifAbsent: [nil]) ifNotNil: [:n |
						(item at: 'inputSchema' ifAbsent: [nil]) ifNotNil: [:s |
							self knownToolSchemas at: n put: (self
				detachedProtocolValue: s)]]].
			methodName = 'tools/list' ifTrue: [
				self knownToolOutputSchemas at: (item at: 'name') copy
					put: (self detachedProtocolValue:
						(item at: 'outputSchema' ifAbsent: [nil]))].
			items add: (self detachedProtocolValue: item)].
		nextCursor := result at: 'nextCursor' ifAbsent: [nil].
		nextCursor ifNil: [^items asArray].
		(nextCursor isString and: [nextCursor isEmpty not])
			ifFalse: [self error: 'Invalid ' , methodName ,
				' result: invalid nextCursor'].
		(seenCursors includes: nextCursor)
			ifTrue: [self error: 'Invalid ' , methodName ,
				' result: repeated nextCursor'].
		seenCursors add: nextCursor.
		cursor := nextCursor.
		true]
			whileTrue: []

]

{ #category : 'Protocol Operations' }
McpClient >> completePrompt: aPromptName argument: anArgumentName value: aValueString [
	"Request autocompletions for a prompt argument.

	 Arguments:
		aPromptName - <String> prompt name.
		anArgumentName - <String> argument name.
		aValueString - <String> current value or prefix.
	 Answers:
		<KeyedCollection> completion dictionary with values and optional total/hasMore."

	^self completePrompt: aPromptName argument: anArgumentName value: aValueString context: nil
]

{ #category : 'Protocol Operations' }
McpClient >> completePrompt: aPromptName argument: anArgumentName value: aValueString context: aContextDictionary [
	"Request autocompletions for a prompt argument with context.

	 Arguments:
		aPromptName - <String> prompt name.
		anArgumentName - <String> argument name.
		aValueString - <String> current value or prefix.
		aContextDictionary - <KeyedCollection> optional context, or nil.
	 Answers:
		<KeyedCollection> completion dictionary with values and optional total/hasMore."

	| ref |

	(aPromptName isString and: [aPromptName isEmpty not])
		ifFalse: [self error: 'Prompt name must be a nonempty string'].
	ref :=
		EsOrderedDictionary new
			at: 'type' put: 'ref/prompt';
			at: 'name' put: aPromptName;
			yourself.
	^self completeRef: ref argument: anArgumentName value: aValueString context: aContextDictionary
]

{ #category : 'Protocol Operations' }
McpClient >> completeRef: aRefDictionary argument: anArgumentName value: aValueString context: aContextDictionary [
	"Send a completion/complete request for a reference and answer validated completion data.

	 Arguments:
		aRefDictionary - <KeyedCollection> ref/prompt or ref/resource reference.
		anArgumentName - <String> argument name.
		aValueString - <String> current value or prefix.
		aContextDictionary - <KeyedCollection> optional context, or nil.
	 Answers:
		<KeyedCollection> completion dictionary with values and optional total/hasMore."

	| argument params result |

	(aRefDictionary isKindOf: KeyedCollection)
		ifFalse: [self error: 'Completion ref must be a keyed collection'].
	(anArgumentName isString and: [anArgumentName isEmpty not])
		ifFalse: [self error: 'Completion argument name must be a nonempty string'].
	aValueString isString ifFalse: [self error: 'Completion argument value must be a string'].
	self requireServerCapability: 'completions' forOperation: 'completion/complete'.
	argument :=
		EsOrderedDictionary new
			at: 'name' put: anArgumentName copy;
			at: 'value' put: aValueString copy;
			yourself.
	params :=
		EsOrderedDictionary new
			at: 'ref' put: aRefDictionary;
			at: 'argument' put: argument;
			yourself.
	aContextDictionary
		ifNotNil: [params at: 'context' put: (self detachedProtocolValue: aContextDictionary)].
	result := self sendRequest: 'completion/complete' params: params.
	^self validatedCompletionResult: result
]

{ #category : 'Protocol Operations' }
McpClient >> completeResource: aUriString argument: anArgumentName value: aValueString [
	"Request autocompletions for a resource URI template variable.

	 Arguments:
		aUriString - <String> resource URI or template.
		anArgumentName - <String> variable name.
		aValueString - <String> current value or prefix.
	 Answers:
		<KeyedCollection> completion dictionary with values and optional total/hasMore."

	^self completeResource: aUriString argument: anArgumentName value: aValueString context: nil
]

{ #category : 'Protocol Operations' }
McpClient >> completeResource: aUriString argument: anArgumentName value: aValueString context: aContextDictionary [
	"Request autocompletions for a resource URI template variable with context.

	 Arguments:
		aUriString - <String> resource URI or template.
		anArgumentName - <String> variable name.
		aValueString - <String> current value or prefix.
		aContextDictionary - <KeyedCollection> optional context, or nil.
	 Answers:
		<KeyedCollection> completion dictionary with values and optional total/hasMore."

	| ref |

	(aUriString isString and: [aUriString isEmpty not])
		ifFalse: [self error: 'Resource URI must be a nonempty string'].
	ref :=
		EsOrderedDictionary new
			at: 'type' put: 'ref/resource';
			at: 'uri' put: aUriString;
			yourself.
	^self completeRef: ref argument: anArgumentName value: aValueString context: aContextDictionary
]

{ #category : 'Starting and Stopping' }
McpClient >> connect [
	"Connect using the transport's persistent HTTP configuration.

	 Answers:
		<McpClient> the connected receiver."

	^self connectWithHeaders: nil
]

{ #category : 'Starting and Stopping',
  #vaVisibility : 'private' }
McpClient >> connectLegacyWithHeaders: requestHeaders [
	"Connect using legacy initialize handshake.

	 Arguments:
		requestHeaders - <KeyedCollection> HTTP headers, or nil.
	 Answers:
		<McpClient> the receiver."

	| parameters initialization negotiatedVersion negotiatedCapabilities negotiatedInfo serverName
	  serverVersion |

	parameters :=
		EsOrderedDictionary new
			at: 'protocolVersion' put: self class supportedHandshakeProtocolVersions first;
			at: 'capabilities' put: self capabilities;
			at: 'clientInfo' put: self clientInfo;
			yourself.
	initialization :=
		requestHeaders
			ifNil: [self sendRequest: 'initialize' params: parameters]
			ifNotNil: [self sendRequest: 'initialize' params: parameters headers: requestHeaders].
	(initialization isKindOf: KeyedCollection)
		ifFalse: [self error: 'Invalid initialize result: expected an object'].
	negotiatedVersion := initialization at: 'protocolVersion' ifAbsent: [nil].
	(negotiatedVersion isString
		and: [self class supportedProtocolVersions includes: negotiatedVersion])
			ifFalse: [self error: 'Unsupported or missing MCP protocol version'].
	negotiatedCapabilities := initialization at: 'capabilities' ifAbsent: [nil].
	(negotiatedCapabilities isKindOf: KeyedCollection)
		ifFalse: [self error: 'Invalid initialize result: capabilities are required'].
	negotiatedInfo := initialization at: 'serverInfo' ifAbsent: [nil].
	(negotiatedInfo isKindOf: KeyedCollection)
		ifFalse: [self error: 'Invalid initialize result: serverInfo is required'].
	serverName := negotiatedInfo at: 'name' ifAbsent: [nil].
	serverVersion := negotiatedInfo at: 'version' ifAbsent: [nil].
	(serverName isString and: [serverName isEmpty not])
		ifFalse: [self error: 'Invalid initialize result: server name is required'].
	(serverVersion isString and: [serverVersion isEmpty not])
		ifFalse: [self error: 'Invalid initialize result: server version is required'].
	protocolVersion := negotiatedVersion copy.
	serverCapabilities := self detachedProtocolValue: negotiatedCapabilities.
	serverInfo := self detachedProtocolValue: negotiatedInfo.
	self
		sendNotification: 'notifications/initialized'
		params: EsOrderedDictionary new
		headers: requestHeaders.
	isConnected := true.
	^self
]

{ #category : 'Starting and Stopping',
  #vaVisibility : 'private' }
McpClient >> connectModernWithHeaders: requestHeaders [
	"Connect using protocol 2026-07-28 server/discover probe or adopt priorDiscover.

	 Arguments:
		requestHeaders - <KeyedCollection> HTTP headers, or nil.
	 Answers:
		<McpClient> the receiver."

	| discoverResult negotiatedCapabilities serverMetadata |

	protocolVersion := '2026-07-28'.
	discoverResult :=
		self priorDiscover
			ifNotNil: [:prior | prior]
			ifNil: [
				requestHeaders
					ifNil: [self sendRequest: 'server/discover' params: EsOrderedDictionary new]
					ifNotNil: [
						self
							sendRequest: 'server/discover'
							params: EsOrderedDictionary new
							headers: requestHeaders]].
	(discoverResult isKindOf: KeyedCollection)
		ifFalse: [self error: 'Invalid discover result: expected an object'].
	negotiatedCapabilities := discoverResult at: 'capabilities' ifAbsent: [nil].
	(negotiatedCapabilities isKindOf: KeyedCollection)
		ifFalse: [self error: 'Invalid discover result: capabilities are required'].
	serverCapabilities := self detachedProtocolValue: negotiatedCapabilities.
	serverMetadata := nil.
	(discoverResult at: '_meta' ifAbsent: [nil]) ifNotNil: [:meta |
		(meta isKindOf: KeyedCollection)
			ifTrue: [serverMetadata := meta at: 'io.modelcontextprotocol/serverInfo' ifAbsent: [nil]]].
	serverMetadata ifNil: [serverMetadata := discoverResult at: 'serverInfo' ifAbsent: [nil]].
	serverInfo :=
		(serverMetadata isKindOf: KeyedCollection)
			ifTrue: [self detachedProtocolValue: serverMetadata]
			ifFalse: [EsOrderedDictionary new].
	isConnected := true.
	^self
]

{ #category : 'Starting and Stopping' }
McpClient >> connectWithHeaders: requestHeaders [
	"Initialize using configured negotiation mode (#auto, #modern, #legacy).

	 Arguments:
		requestHeaders - <KeyedCollection> HTTP headers, or nil.
	 Answers:
		<McpClient> the connected receiver."

	connectionMutex critical: [
		self isConnected ifTrue: [^self].
		self transport ifNil: [self error: 'MCP client transport is not configured'].
		self mode == #legacy
			ifTrue: [self connectLegacyWithHeaders: requestHeaders]
			ifFalse: [
				self mode == #modern
					ifTrue: [self connectModernWithHeaders: requestHeaders]
					ifFalse: [
						[self connectModernWithHeaders: requestHeaders]
							on: Error
							do: [:err |
								protocolVersion := nil.
								serverCapabilities := nil.
								serverInfo := nil.
								isConnected := false.
								err return: (self connectLegacyWithHeaders: requestHeaders)]]]].
	^self
]

{ #category : 'Serialization',
  #vaVisibility : 'private' }
McpClient >> detachedProtocolValue: anObject [
	"Answer an isolated copy of a JSON-compatible protocol value.

	 Arguments:
		anObject - <Object> JSON-compatible value.
	 Answers:
		<Object> detached value."

	^self detachedProtocolValue: anObject visited: IdentitySet new
]

{ #category : 'Serialization',
  #vaVisibility : 'private' }
McpClient >> detachedProtocolValue: anObject visited: visitedObjects [
	"Recursively copy a protocol value while rejecting cycles and objects.

	 Arguments:
		anObject - <Object> value being copied.
		visitedObjects - <IdentitySet> active containers.
	 Answers:
		<Object> detached JSON-compatible value."

	| detached |

	anObject ifNil: [^nil].
	anObject isBoolean ifTrue: [^anObject].
	anObject isNumber ifTrue: [^anObject].
	anObject isString ifTrue: [^anObject copy].
	(visitedObjects includes: anObject) ifTrue: [self error: 'MCP protocol value contains a cycle'].
	(anObject isKindOf: KeyedCollection)
		ifTrue: [
			visitedObjects add: anObject.
			[
				detached := EsOrderedDictionary new.
				anObject keysAndValuesDo: [:key :value |
					key isString ifFalse: [self error: 'MCP protocol object keys must be strings'].
					detached
						at: key copy
						put: (self detachedProtocolValue: value visited: visitedObjects)]]
							ensure: [visitedObjects remove: anObject ifAbsent: []].
			^detached].
	(anObject isKindOf: SequenceableCollection)
		ifTrue: [
			visitedObjects add: anObject.
			[
				detached :=
					anObject
						collect: [:value | self detachedProtocolValue: value visited: visitedObjects]]
							ensure: [visitedObjects remove: anObject ifAbsent: []].
			^detached asArray].
	self error: 'MCP protocol metadata contains a non-JSON-compatible value'
]

{ #category : 'Protocol Operations',
  #vaVisibility : 'private' }
McpClient >> dispatchInputRequest: inputRequest named: requestKey [
	"Dispatch one embedded input request to registered client callbacks.

	 Arguments:
		inputRequest - <KeyedCollection> embedded input request object.
		requestKey - <String> correlation key for this request.
	 Answers:
		<Object> client response for this input request."

	| method callbackResult |

	(inputRequest isKindOf: KeyedCollection)
		ifFalse: [self error: 'Invalid embedded input request: expected an object'].
	method := inputRequest at: 'method' ifAbsent: [nil].
	method = 'elicitation/create'
		ifTrue: [
			self elicitationCallback ifNil: [
				self error:
					'No client elicitationCallback registered for input request: ' , requestKey].
			callbackResult := self elicitationCallback value: inputRequest value: self.
			(callbackResult isKindOf: KeyedCollection) ifFalse: [
				self error: 'Elicitation callback must return an ElicitResult object (KeyedCollection)'.
			].
			^callbackResult].
	method = 'sampling/createMessage'
		ifTrue: [
			self samplingCallback ifNil: [
				self error: 'No client samplingCallback registered for input request: ' , requestKey].
			^self samplingCallback value: inputRequest value: self].
	method = 'roots/list'
		ifTrue: [
			self rootsCallback ifNil: [
				self error: 'No client rootsCallback registered for input request: ' , requestKey].
			^self rootsCallback value: inputRequest value: self].
	self error: 'Unrecognized input request method: ' , method printString
]

{ #category : 'Protocol Operations',
  #vaVisibility : 'private' }
McpClient >> driveInputRequired: initialResult retryBlock: aRetryBlock [
	"Drive multi-round-trip resolution when initialResult is an InputRequiredResult.

	 Arguments:
		initialResult - <KeyedCollection> initial result candidate.
		aRetryBlock - <BlockClosure> [:inputResponses :requestState | ...] returning next result.
	 Answers:
		<KeyedCollection> terminal result."

	| current rounds requests responses state resultType |

	current := initialResult.
	rounds := 0.
	[
		(current isKindOf: KeyedCollection) and: [
			resultType := current at: 'resultType' ifAbsent: [nil].
			resultType = 'input_required' or: [resultType = 'inputRequired']]]
				whileTrue: [
					rounds := rounds + 1.
					rounds > self inputRequiredMaxRounds
						ifTrue: [
							self error:
								'Server exceeded maximum inputRequired rounds: ' ,
									self inputRequiredMaxRounds printString].
					requests := current at: 'inputRequests' ifAbsent: [nil].
					state := current at: 'requestState' ifAbsent: [nil].
					responses := nil.
					(requests isKindOf: KeyedCollection)
						ifTrue: [
							responses := EsOrderedDictionary new.
							requests keysAndValuesDo: [:key :req |
								responses at: key put: (self dispatchInputRequest: req named: key)]].
					current := aRetryBlock value: responses value: state].
	^current
]

{ #category : 'Accessing' }
McpClient >> elicitationCallback [
	"Answer the block for handling elicitation input requests.

	 Answers:
		<BlockClosure> or nil."

	^elicitationCallback
]

{ #category : 'Accessing' }
McpClient >> elicitationCallback: aBlock [
	"Set the block for handling elicitation input requests.

	 Arguments:
		aBlock - <BlockClosure> or nil.
	 Answers:
		<McpClient> the receiver."

	elicitationCallback := aBlock.
	^self
]

{ #category : 'Private',
  #vaVisibility : 'private' }
McpClient >> encodeHeaderValue: aString [
	"Encode a string value using the Base64 sentinel format =?base64?{value}?=
	 if it contains non-ASCII characters, control characters, leading/trailing whitespace,
	 or matches the sentinel prefix/suffix per SEP-2243.

	 Arguments:
		aString - <String>.
	 Answers:
		<String> plain ASCII or sentinel-encoded header value."

	| str needsEncoding b64 |

	aString ifNil: [^''].
	str := aString isString ifTrue: [aString] ifFalse: [aString printString].
	str isEmpty ifTrue: [^''].
	needsEncoding :=
		(str first = $  or: [str last = $ ]) or: [
			(str anySatisfy: [:c | c codePoint < 16r20 or: [c codePoint > 16r7E]]) or: [
				(str size >= 11 and: [
					(str beginsWithSubCollection: '=?base64?')
						and: [(str copyFrom: str size - 1 to: str size) = '?=']])]].
	needsEncoding ifFalse: [^(str asEsString ifNil: [str asString])].
	b64 := (Base64Coder current encode: str asUtf8Bytes) asString.
	^'=?base64?' , b64 , '?='
]

{ #category : 'Accessing' }
McpClient >> extensions [
	"Answer the collection of registered client extensions.

	 Answers:
		<OrderedCollection> of <McpExtension>."

	extensions ifNil: [extensions := OrderedCollection new].
	^extensions
]

{ #category : 'Private',
  #vaVisibility : 'private' }
McpClient >> extractParamHeadersFromSchema: schema arguments: args into: headers [
	"Extract Mcp-Param-* headers for primitive properties annotated with x-mcp-header,
	 following statically reachable chains of 'properties' keys per SEP-2243.

	 Arguments:
		schema - <KeyedCollection> schema or subschema.
		args - <KeyedCollection> corresponding argument values.
		headers - <KeyedCollection> destination headers map."

	| properties |

	(schema isKindOf: KeyedCollection) ifFalse: [^self].
	properties := schema at: 'properties' ifAbsent: [nil].
	(properties isKindOf: KeyedCollection) ifFalse: [^self].
	(args isKindOf: KeyedCollection) ifFalse: [^self].

	properties keysAndValuesDo: [:propName :propDef |
		(propDef isKindOf: KeyedCollection) ifTrue: [
			(propDef at: 'x-mcp-header' ifAbsent: [nil])
				ifNotNil: [:headerToken | | token headerName bodyVal valStr |
					token := headerToken isString ifTrue: [headerToken] ifFalse: [propName].
					headerName := 'Mcp-Param-' , token.
					bodyVal := args at: propName ifAbsent: [nil].
					bodyVal ifNotNil: [
						valStr :=
							bodyVal isBoolean
								ifTrue: [bodyVal ifTrue: ['true'] ifFalse: ['false']]
								ifFalse: [
									bodyVal isString
										ifTrue: [bodyVal]
										ifFalse: [bodyVal printString]].
						headers at: headerName put: (self encodeHeaderValue: valStr)]]
				ifNil: [
					(propDef includesKey: 'properties') ifTrue: [
						(args at: propName ifAbsent: [nil]) ifNotNil: [:nestedArgs |
							self extractParamHeadersFromSchema: propDef arguments: nestedArgs into: headers]]]]]
]

{ #category : 'Protocol Operations' }
McpClient >> getPrompt: promptName arguments: arguments [
	"Get a prompt definition from the connected server, driving any InputRequiredResult rounds.

	 Arguments:
		promptName - <String> nonempty prompt name.
		arguments - <KeyedCollection> prompt arguments, or nil.
	 Answers:
		<KeyedCollection> MCP GetPromptResult."

	| parameters initialResult result |

	(promptName isString and: [promptName isEmpty not])
		ifFalse: [self error: 'MCP prompt name must be a nonempty string'].
	(arguments isNil or: [arguments isKindOf: KeyedCollection])
		ifFalse: [self error: 'MCP prompt arguments must be a keyed collection or nil'].
	self requireServerCapability: 'prompts' forOperation: 'prompts/get'.
	parameters := EsOrderedDictionary with: 'name' -> promptName.
	arguments ifNotNil: [parameters at: 'arguments' put: arguments].
	initialResult := self sendRequest: 'prompts/get' params: parameters.
	result :=
		self
			driveInputRequired: initialResult
			retryBlock: [:inputResponses :requestState | | retryParams |
				retryParams := parameters copy.
				inputResponses ifNotNil: [retryParams at: 'inputResponses' put: inputResponses].
				requestState ifNotNil: [retryParams at: 'requestState' put: requestState].
				self sendRequest: 'prompts/get' params: retryParams].
	^self validatedPromptResult: result
]

{ #category : 'Message Handling' }
McpClient >> handleIncomingMessage: aDictionary [
	"Validate and dispatch one server-originated JSON-RPC message.

	 Responses not owned by the current transport request are ignored. This
	 method handles only notifications and requests containing a method.

	 Arguments:
		aDictionary - <KeyedCollection> decoded JSON-RPC message.
	 Answers:
		<McpClient> the receiver."

	| method parameters identifier |

	(aDictionary isKindOf: KeyedCollection)
		ifFalse: [self error: 'Invalid incoming MCP message: expected an object'].
	(aDictionary at: 'jsonrpc' ifAbsent: [nil]) = '2.0'
		ifFalse: [self error: 'Invalid incoming MCP message: invalid jsonrpc version'].
	method := aDictionary at: 'method' ifAbsent: [^self].
	method isString ifFalse: [self error: 'Invalid incoming MCP message: method must be a string'].
	parameters := aDictionary at: 'params' ifAbsent: [EsOrderedDictionary new].
	(parameters isKindOf: KeyedCollection)
		ifFalse: [self error: 'Invalid incoming MCP message: params must be an object'].
	(aDictionary includesKey: 'id')
		ifTrue: [
			identifier := aDictionary at: 'id'.
			(identifier isString or: [identifier isInteger])
				ifFalse: [self error: 'Invalid incoming MCP request: invalid identifier'].
			self handleRequestMethod: method params: parameters id: identifier]
		ifFalse: [self handleNotificationMethod: method params: parameters].
	^self
]

{ #category : 'Execution',
  #vaVisibility : 'private' }
McpClient >> handleNotificationMethod: methodName params: parameters [
	"Invoke the registered notification handler and evict matching cache
		entries.

	 Arguments:
		methodName - <String> MCP notification method.
		parameters - <KeyedCollection> notification parameters.
	 Answers:
		<McpClient> the receiver."

	| handler |

	methodName = 'notifications/tools/list_changed' ifTrue: [
		knownToolOutputSchemas := nil. knownToolSchemas := nil].
	self responseCache evictForNotification: methodName params: parameters.
	methodName = 'notifications/progress' ifTrue: [self
		handleProgressNotification: parameters].
	handler := handlerMutex critical: [notificationHandlers at: methodName
		ifAbsent: [nil]].
	handler ifNotNil: [handler value: parameters].
	^self

]

{ #category : 'Message Handling',
  #vaVisibility : 'private' }
McpClient >> handleProgressNotification: parameters [
	"Dispatch a notifications/progress payload to the registered progress callback.

	 Arguments:
		parameters - <KeyedCollection> progress notification parameters.
	 Answers:
		<McpClient> the receiver."

	| token progress total message |

	(parameters isKindOf: KeyedCollection) ifFalse: [^self].
	token := parameters at: 'progressToken' ifAbsent: [^self].
	progress := parameters at: 'progress' ifAbsent: [0].
	total := parameters at: 'total' ifAbsent: [nil].
	message := parameters at: 'message' ifAbsent: [nil].
	progressCallbacksMutex critical: [
		progressCallbacks
			at: token
			ifPresent: [:callback |
				[callback cull: progress cull: total cull: message cull: parameters]
					on: Error
					do: [:err | nil]]].
	^self
]

{ #category : 'Message Handling',
  #vaVisibility : 'private' }
McpClient >> handleRequestMethod: methodName params: parameters id: identifier [
	"Invoke a request handler and return a JSON-RPC result or error.

	 Arguments:
		methodName - <String> MCP request method.
		parameters - <KeyedCollection> request parameters.
		identifier - <String> or <Integer> request identifier.
	 Answers:
		<McpClient> the receiver."

	| handler result |

	handler := handlerMutex critical: [requestHandlers at: methodName ifAbsent: [nil]].
	handler ifNil: [
		^self
			sendErrorCode: McpJsonRpcMethodNotFoundCode
			message: 'Method not found: ' , methodName
			data: nil
			id: identifier].
	[
		[result := handler value: parameters]
			on: McpJsonRpcError
			do: [:rpcError |
				^self
					sendErrorCode: rpcError code
					message: rpcError messageText
					data: rpcError data
					id: identifier]]
						on: Error
						do: [:unexpectedError |
							^self
								sendErrorCode: McpJsonRpcInternalErrorCode
								message: 'Internal error'
								data: nil
								id: identifier].
	^self sendResult: result id: identifier
]

{ #category : 'Initialization',
  #vaVisibility : 'private' }
McpClient >> initialize [
	"Initialize lifecycle synchronization, caches, and message-handler registries.

	 Answers:
		<McpClient> the receiver."

	super initialize.
	clientInfo := EsOrderedDictionary with: 'name' -> 'VastMcpClient' with: 'version' -> '1.0.0'.
	capabilities := EsOrderedDictionary new.
	isConnected := false.
	requestMutex := Semaphore forMutualExclusion.
	connectionMutex := Semaphore forMutualExclusion.
	nextRequestId := 1.
	notificationHandlers := Dictionary new.
	requestHandlers := Dictionary new.
	handlerMutex := Semaphore forMutualExclusion.
	mode := #legacy.
	inputRequiredMaxRounds := 10.
	progressCallbacks := Dictionary new.
	progressCallbacksMutex := Semaphore forMutualExclusion.
	responseCache := McpClientResponseCache new.
	^self
]

{ #category : 'Accessing' }
McpClient >> inputRequiredMaxRounds [
	"Answer maximum retry rounds before aborting an InputRequiredResult loop.

	 Answers:
		<Integer>."

	^inputRequiredMaxRounds
]

{ #category : 'Accessing' }
McpClient >> inputRequiredMaxRounds: anInteger [
	"Set maximum retry rounds before aborting an InputRequiredResult loop.

	 Arguments:
		anInteger - <Integer> positive number of rounds.
	 Answers:
		<McpClient> the receiver."

	anInteger isInteger ifFalse: [self error: 'inputRequiredMaxRounds must be an integer'].
	anInteger > 0 ifFalse: [self error: 'inputRequiredMaxRounds must be positive'].
	inputRequiredMaxRounds := anInteger.
	^self
]

{ #category : 'Accessing' }
McpClient >> isConnected [
	"Answer whether protocol initialization completed successfully.

	 Answers:
		<Boolean>."

	^self requestMutex critical: [isConnected]
]

{ #category : 'Validation' }
McpClient >> isPrimitiveTypeAllowedForParamHeader: propDef [
	"Answer whether the property definition is a primitive type (string, boolean, integer, number)."

	| type |
	type := propDef at: 'type' ifAbsent: [nil].
	^#('string' 'boolean' 'integer' 'number') includes: type
]

{ #category : 'Accessing',
  #vaVisibility : 'private' }
McpClient >> isProtocolArray: anObject [
	"Answer whether an object has the structural shape of a JSON array.

	 Arguments:
		anObject - <Object> candidate value.
	 Answers:
		<Boolean>."

	^(anObject isKindOf: SequenceableCollection)
		and: [anObject isString not and: [(anObject isKindOf: KeyedCollection) not]]
]

{ #category : 'Validation',
  #vaVisibility : 'private' }
McpClient >> isValidAbsoluteResourceUri: anObject [
	"Answer whether an object is a syntactically absolute resource URI.

	 Arguments:
		anObject - <Object> URI candidate.
	 Answers:
		<Boolean>."

	| colonIndex scheme index |

	(anObject isString and: [anObject isEmpty not]) ifFalse: [^false].
	colonIndex := anObject indexOf: $:.
	colonIndex > 1 ifFalse: [^false].
	scheme := anObject copyFrom: 1 to: colonIndex - 1.
	index := 0.
	^scheme allSatisfy: [:character |
		index := index + 1.
		self isValidResourceUriSchemeCharacter: character first: index = 1]
]

{ #category : 'Validation' }
McpClient >> isValidHeaderToken: aString [
	"Answer true if aString contains only valid RFC 9110 token characters."

	| validChars |
	validChars := '!#$%&''*+-.^_`|~'.
	^aString allSatisfy: [:char |
		char isAlphaNumeric or: [validChars includes: char]]
]

{ #category : 'Validation',
  #vaVisibility : 'private' }
McpClient >> isValidResourceUriSchemeCharacter: aCharacter first: isFirst [
	"Answer whether a character is valid in an absolute URI scheme.

	 Arguments:
		aCharacter - <Character> scheme character.
		isFirst - <Boolean> whether this begins the scheme.
	 Answers:
		<Boolean>."

	| codePoint isLetter |

	codePoint := aCharacter codePoint.
	isLetter :=
		(codePoint between: $A codePoint and: $Z codePoint)
			or: [codePoint between: $a codePoint and: $z codePoint].
	isFirst ifTrue: [^isLetter].
	^isLetter or: [
		(codePoint between: $0 codePoint and: $9 codePoint)
			or: [aCharacter = $+ or: [aCharacter = $- or: [aCharacter = $.]]]]
]

{ #category : 'Validation',
  #vaVisibility : 'private' }
McpClient >> isValidToolNameCharacter: aCharacter [
	"Answer whether a character belongs to the MCP tool-name alphabet.

	 Arguments:
		aCharacter - <Character> name character.
	 Answers:
		<Boolean>."

	| codePoint |

	codePoint := aCharacter codePoint.
	^(codePoint between: $A codePoint and: $Z codePoint) or: [
		(codePoint between: $a codePoint and: $z codePoint) or: [
			(codePoint between: $0 codePoint and: $9 codePoint)
				or: [aCharacter = $. or: [aCharacter = $- or: [aCharacter = $_]]]]]
]

{ #category : 'Accessing',
  #vaVisibility : 'private' }
McpClient >> knownToolOutputSchemas [
	"Answer the private cache; nil values mean no advertised output schema.
	Answers:
		<Dictionary> tool names to detached schemas."
	knownToolOutputSchemas ifNil: [knownToolOutputSchemas := Dictionary new].
	^knownToolOutputSchemas

]

{ #category : 'Accessing' }
McpClient >> knownToolSchemas [
	"Answer the dictionary caching known tool schemas discovered from listTools.

	 Answers:
		<Dictionary> of <String> -> <KeyedCollection>."

	knownToolSchemas ifNil: [knownToolSchemas := Dictionary new].
	^knownToolSchemas
]

{ #category : 'Protocol Operations' }
McpClient >> listPrompts [
	"Answer every prompt advertised by a capable MCP server.

	 Answers:
		<Array> of <KeyedCollection> prompt definitions."

	self requireServerCapability: 'prompts' forOperation: 'prompts/list'.
	^self collectPaginatedMethod: 'prompts/list' resultKey: 'prompts'
]

{ #category : 'Protocol Operations' }
McpClient >> listResourceTemplates [
	"Answer every resource template advertised by a capable server.

	 Answers:
		<Array> of <KeyedCollection> resource-template definitions."

	self requireServerCapability: 'resources' forOperation: 'resources/templates/list'.
	^self collectPaginatedMethod: 'resources/templates/list' resultKey: 'resourceTemplates'
]

{ #category : 'Protocol Operations' }
McpClient >> listResources [
	"Answer every resource advertised by a capable MCP server.

	 Answers:
		<Array> of <KeyedCollection> resource definitions."

	self requireServerCapability: 'resources' forOperation: 'resources/list'.
	^self collectPaginatedMethod: 'resources/list' resultKey: 'resources'
]

{ #category : 'Protocol Operations' }
McpClient >> listTools [
	"Answer every tool advertised by a capable MCP server.

	 Answers:
		<Array> of <KeyedCollection> tool definitions."

	self requireServerCapability: 'tools' forOperation: 'tools/list'.
	^self collectPaginatedMethod: 'tools/list' resultKey: 'tools'
]

{ #category : 'Protocol Operations' }
McpClient >> listen: aFilterDictionary do: aBlock [
	"Open a subscription stream for change events and evaluate aBlock for each received notification.

	 Arguments:
		aFilterDictionary - <KeyedCollection> filter options (tools, prompts, resources, resourceSubscriptions).
		aBlock - <Block> [:method :params | ...] event block.
	 Answers:
		<KeyedCollection> subscription acknowledgment result."

	| parameters result |

	self isConnected
		ifFalse: [self error: 'Client must be connected before listening for subscriptions'].
	parameters :=
		EsOrderedDictionary
			with: 'notifications' -> (aFilterDictionary ifNil: [EsOrderedDictionary new]).
	self
		onNotification: 'notifications/tools/list_changed'
		do: [:params |
			self responseCache ifNotNil: [:c | c evictMethod: 'tools/list'].
			aBlock cull: 'notifications/tools/list_changed' cull: params].
	self
		onNotification: 'notifications/prompts/list_changed'
		do: [:params |
			self responseCache ifNotNil: [:c | c evictMethod: 'prompts/list'].
			aBlock cull: 'notifications/prompts/list_changed' cull: params].
	self
		onNotification: 'notifications/resources/list_changed'
		do: [:params |
			self responseCache ifNotNil: [:c | c evictMethod: 'resources/list'].
			aBlock cull: 'notifications/resources/list_changed' cull: params].
	self
		onNotification: 'notifications/resources/updated'
		do: [:params | | uri |
			uri :=
				(params isKindOf: KeyedCollection)
					ifTrue: [params at: 'uri' ifAbsent: ['']]
					ifFalse: [''].
			self responseCache ifNotNil: [:c |
				uri isEmpty
					ifTrue: [c evictMethod: 'resources/read']
					ifFalse: [c evictMethod: 'resources/read' key: uri]].
			aBlock cull: 'notifications/resources/updated' cull: params].
	result := self sendRequest: 'subscriptions/listen' params: parameters.
	^result
]

{ #category : 'Execution' }
McpClient >> markDisconnected [
	"Atomically mark the client disconnected.

	 This operation intentionally retains negotiated values so transport
	 teardown can still use the active protocol and session information.

	 Answers:
		<McpClient> the receiver."

	self requestMutex critical: [isConnected := false. knownToolOutputSchemas :=
		nil. knownToolSchemas := nil].
	^self

]

{ #category : 'Accessing' }
McpClient >> mode [
	"Answer the connection negotiation mode (#auto, #modern, #legacy).

	 Answers:
		<Symbol>."

	^mode
]

{ #category : 'Accessing' }
McpClient >> mode: aSymbol [
	"Set the connection negotiation mode (#auto, #modern, #legacy).

	 Arguments:
		aSymbol - <Symbol>.
	 Answers:
		<McpClient> the receiver."

	(#(auto modern legacy) includes: aSymbol)
		ifFalse: [self error: 'Invalid MCP client mode: must be #auto, #modern, or #legacy'].
	mode := aSymbol.
	^self
]

{ #category : 'Accessing' }
McpClient >> onNotification: methodName do: aBlock [
	"Register a block to receive the named server notification.

	 The block receives the notification parameter dictionary.

	 Arguments:
		methodName - <String> nonempty MCP method name.
		aBlock - <Block> accepting one argument.
	 Answers:
		<McpClient> the receiver."

	(methodName isString and: [methodName isEmpty not])
		ifFalse: [self error: 'Notification method must be a nonempty string'].
	aBlock isBlock ifFalse: [self error: 'Notification handler must be a block'].
	aBlock numArgs = 1 ifFalse: [self error: 'Notification handler must accept one argument'].
	handlerMutex critical: [notificationHandlers at: methodName put: aBlock].
	^self
]

{ #category : 'Accessing' }
McpClient >> onRequest: methodName do: aBlock [
	"Register a block to answer the named server request.

	 The block receives the request parameter dictionary. Registering it does
	 not advertise the corresponding client capability.

	 Arguments:
		methodName - <String> nonempty MCP method name.
		aBlock - <Block> accepting one argument.
	 Answers:
		<McpClient> the receiver."

	(methodName isString and: [methodName isEmpty not])
		ifFalse: [self error: 'Request method must be a nonempty string'].
	aBlock isBlock ifFalse: [self error: 'Request handler must be a block'].
	aBlock numArgs = 1 ifFalse: [self error: 'Request handler must accept one argument'].
	handlerMutex critical: [requestHandlers at: methodName put: aBlock].
	^self
]

{ #category : 'Protocol Operations' }
McpClient >> ping [
	"Send a ping request and answer whether the server acknowledged.

	 Answers:
		<Boolean>."

	self checkConnected.
	(McpProtocolVersion isModern: self protocolVersion)
		ifTrue: [self error: 'MCP ping is removed in protocol version ' , self protocolVersion].
	self sendRequest: 'ping' params: EsOrderedDictionary new.
	^true
]

{ #category : 'Accessing' }
McpClient >> priorDiscover [
	"Answer the previously saved DiscoverResult, or nil.

	 Answers:
		<KeyedCollection> or nil."

	^priorDiscover
]

{ #category : 'Accessing' }
McpClient >> priorDiscover: aDiscoverResult [
	"Set a previously saved DiscoverResult to bypass discovery when reconnecting in modern mode.

	 Arguments:
		aDiscoverResult - <KeyedCollection> or nil.
	 Answers:
		<McpClient> the receiver."

	(aDiscoverResult isNil or: [aDiscoverResult isKindOf: KeyedCollection])
		ifFalse: [self error: 'Prior discover must be a keyed collection or nil'].
	priorDiscover := aDiscoverResult ifNotNil: [self detachedProtocolValue: aDiscoverResult].
	^self
]

{ #category : 'Accessing' }
McpClient >> protocolVersion [
	"Answer the negotiated MCP protocol version.

	 Answers:
		<String> or nil when no version is negotiated."

	^self requestMutex critical: [protocolVersion]
]

{ #category : 'Protocol Operations' }
McpClient >> readResource: resourceUri [
	"Read a resource from the connected server, driving any InputRequiredResult rounds.

	 Arguments:
		resourceUri - <String> absolute resource URI.
	 Answers:
		<KeyedCollection> MCP ReadResourceResult."

	| parameters initialResult result |

	(resourceUri isString and: [resourceUri isEmpty not])
		ifFalse: [self error: 'MCP resource URI must be a nonempty string'].
	(self isValidAbsoluteResourceUri: resourceUri)
		ifFalse: [self error: 'MCP resource URI must be absolute'].
	self requireServerCapability: 'resources' forOperation: 'resources/read'.
	parameters := EsOrderedDictionary with: 'uri' -> resourceUri.
	initialResult := self sendRequest: 'resources/read' params: parameters.
	result :=
		self
			driveInputRequired: initialResult
			retryBlock: [:inputResponses :requestState | | retryParams |
				retryParams := parameters copy.
				inputResponses ifNotNil: [retryParams at: 'inputResponses' put: inputResponses].
				requestState ifNotNil: [retryParams at: 'requestState' put: requestState].
				self sendRequest: 'resources/read' params: retryParams].
	^self validatedResourceResult: result
]

{ #category : 'Validation' }
McpClient >> refreshOutputSchemasWithHeaders: requestHeaders [
	"Discover output contracts under the same credentials as the tool call.
	Arguments:
		requestHeaders - <KeyedCollection | nil> scoped headers.
	Answers:
		<Dictionary> detached output-schema snapshot."
	| cursor seen parameters page nextCursor definitions snapshot |
	cursor := nil.
	seen := Set new.
	snapshot := Dictionary new.
	[
		parameters := EsOrderedDictionary new.
		cursor ifNotNil: [parameters at: 'cursor' put: cursor].
		page := self sendRequest: 'tools/list' params: parameters
			headers: requestHeaders.
		(page isKindOf: KeyedCollection)
			ifFalse: [self error: 'Invalid tools/list result: expected object'].
		definitions := page at: 'tools' ifAbsent: [nil].
		(self isProtocolArray: definitions)
			ifFalse: [self error: 'Invalid tools/list result: expected array'].
		definitions do: [:definition |
			self validateToolDefinition: definition.
			snapshot at: (definition at: 'name') copy put:
				(self detachedProtocolValue:
					(definition at: 'outputSchema' ifAbsent: [nil]))].
		nextCursor := page at: 'nextCursor' ifAbsent: [nil].
		nextCursor ifNil: [(requestHeaders isNil or: [requestHeaders isEmpty])
				ifTrue: [knownToolOutputSchemas := snapshot].
			^snapshot].
		(nextCursor isString and: [nextCursor isEmpty not])
			ifFalse: [self error: 'Invalid tools/list cursor'].
		(seen includes: nextCursor)
			ifTrue: [self error: 'Repeated tools/list cursor'].
		seen add: nextCursor.
		cursor := nextCursor.
		true
	] whileTrue: []

]

{ #category : 'Accessing' }
McpClient >> removeNotificationHandlerFor: methodName [
	"Remove the handler for the named server notification.

	 Arguments:
		methodName - <String> MCP method name.
	 Answers:
		<McpClient> the receiver."

	handlerMutex critical: [notificationHandlers removeKey: methodName ifAbsent: []].
	^self
]

{ #category : 'Accessing' }
McpClient >> removeRequestHandlerFor: methodName [
	"Remove the handler for the named server request.

	 Arguments:
		methodName - <String> MCP method name.
	 Answers:
		<McpClient> the receiver."

	handlerMutex critical: [requestHandlers removeKey: methodName ifAbsent: []].
	^self
]

{ #category : 'Accessing',
  #vaVisibility : 'private' }
McpClient >> requestMutex [
	"Answer the mutex protecting request identifiers and connection state.

	 Answers:
		<Semaphore>."

	^requestMutex
]

{ #category : 'Validation',
  #vaVisibility : 'private' }
McpClient >> requireServerCapability: capabilityName forOperation: operationName [
	"Require a negotiated server capability before an operation.

	 Arguments:
		capabilityName - <String> capability dictionary key.
		operationName - <String> JSON-RPC operation name.
	 Answers:
		<McpClient> the receiver."

	(self serverSupportsCapability: capabilityName)
		ifFalse: [self error: 'MCP server does not support ' , operationName].
	^self
]

{ #category : 'Private',
  #vaVisibility : 'private' }
McpClient >> resolveParamHeadersForTool: toolName arguments: arguments [
	"Answer a dictionary of Mcp-Param-* headers for arguments annotated with x-mcp-header (SEP-2243)."

	| headers schema |

	headers := EsOrderedDictionary new.
	(arguments isNil or: [(arguments isKindOf: KeyedCollection) not]) ifTrue: [^headers].
	schema := self knownToolSchemas at: toolName ifAbsent: [nil].
	schema ifNil: [^headers].
	self extractParamHeadersFromSchema: schema arguments: arguments into: headers.
	^headers
]

{ #category : 'Accessing' }
McpClient >> responseCache [
	"Answer the response cache store.

	 Answers:
		<McpClientResponseCache>."

	responseCache ifNil: [responseCache := McpClientResponseCache new].
	^responseCache
]

{ #category : 'Accessing' }
McpClient >> responseCache: aCache [
	"Set the response cache store.

	 Arguments:
		aCache - <McpClientResponseCache>."

	(aCache isKindOf: McpClientResponseCache)
		ifFalse: [self error: 'Response cache must be an McpClientResponseCache'].
	responseCache := aCache.
	^self
]

{ #category : 'Accessing' }
McpClient >> rootsCallback [
	"Answer the block for handling roots/list input requests.

	 Answers:
		<BlockClosure> or nil."

	^rootsCallback
]

{ #category : 'Accessing' }
McpClient >> rootsCallback: aBlock [
	"Set the block for handling roots/list input requests.

	 Arguments:
		aBlock - <BlockClosure> or nil.
	 Answers:
		<McpClient> the receiver."

	rootsCallback := aBlock.
	^self
]

{ #category : 'Accessing' }
McpClient >> samplingCallback [
	"Answer the block for handling sampling createMessage input requests.

	 Answers:
		<BlockClosure> or nil."

	^samplingCallback
]

{ #category : 'Accessing' }
McpClient >> samplingCallback: aBlock [
	"Set the block for handling sampling createMessage input requests.

	 Arguments:
		aBlock - <BlockClosure> or nil.
	 Answers:
		<McpClient> the receiver."

	samplingCallback := aBlock.
	^self
]

{ #category : 'Protocol Operations',
  #vaVisibility : 'private' }
McpClient >> sendErrorCode: code message: message data: data id: identifier [
	"Send a validated JSON-RPC error for a server-originated request.

	 Arguments:
		code - <Integer> JSON-RPC error code.
		message - <String> nonempty error message.
		data - <Object> optional JSON-compatible error data.
		identifier - <String> or <Integer> request identifier.
	 Answers:
		<McpClient> the receiver."

	| errorDictionary response dataSnapshot |

	code isInteger ifFalse: [self error: 'JSON-RPC error code must be an integer'].
	(message isString and: [message isEmpty not])
		ifFalse: [self error: 'JSON-RPC error message must be nonempty'].
	(identifier isString or: [identifier isInteger])
		ifFalse: [self error: 'JSON-RPC response identifier is invalid'].
	dataSnapshot := data ifNotNil: [self detachedProtocolValue: data].
	errorDictionary :=
		EsOrderedDictionary new
			at: 'code' put: code;
			at: 'message' put: message copy;
			yourself.
	dataSnapshot ifNotNil: [errorDictionary at: 'data' put: dataSnapshot].
	response :=
		EsOrderedDictionary new
			at: 'jsonrpc' put: '2.0';
			at: 'id' put: identifier;
			at: 'error' put: errorDictionary;
			yourself.
	self transport sendNotification: response.
	^self
]

{ #category : 'Protocol Operations' }
McpClient >> sendNotification: methodName params: parameters [
	"Send a notification without request-scoped headers.

	 Arguments:
		methodName - <String> nonempty JSON-RPC method name.
		parameters - <KeyedCollection> parameters, or nil.
	 Answers:
		<McpClient> the receiver."

	^self sendNotification: methodName params: parameters headers: nil
]

{ #category : 'Protocol Operations' }
McpClient >> sendNotification: methodName params: parameters headers: requestHeaders [
	"Validate, snapshot, and send one JSON-RPC notification.

	 Arguments:
		methodName - <String> nonempty JSON-RPC method name.
		parameters - <KeyedCollection> parameters, or nil.
		requestHeaders - <KeyedCollection> transport headers, or nil.
	 Answers:
		<McpClient> the receiver."

	| notification parameterSnapshot headerSnapshot |

	(methodName isString and: [methodName isEmpty not])
		ifFalse: [self error: 'JSON-RPC method must be a nonempty string'].
	(parameters isNil or: [parameters isKindOf: KeyedCollection])
		ifFalse: [self error: 'MCP notification params must be keyed or nil'].
	(requestHeaders isNil or: [requestHeaders isKindOf: KeyedCollection])
		ifFalse: [self error: 'MCP request headers must be keyed or nil'].
	self transport ifNil: [self error: 'MCP client transport is not configured'].
	parameterSnapshot := parameters ifNotNil: [self detachedProtocolValue: parameters].
	headerSnapshot := requestHeaders ifNotNil: [self detachedProtocolValue: requestHeaders].
	(headerSnapshot notNil
		and: [headerSnapshot isEmpty not and: [self transport supportsRequestHeaders not]])
			ifTrue: [self error: 'MCP transport does not support scoped headers'].
	notification :=
		EsOrderedDictionary new
			at: 'jsonrpc' put: '2.0';
			at: 'method' put: methodName copy;
			yourself.
	parameterSnapshot ifNotNil: [notification at: 'params' put: parameterSnapshot].
	(headerSnapshot isNil
		or: [headerSnapshot isEmpty and: [self transport supportsRequestHeaders not]])
			ifTrue: [self transport sendNotification: notification]
			ifFalse: [self transport sendNotification: notification headers: headerSnapshot].
	^self
]

{ #category : 'Protocol Operations' }
McpClient >> sendRequest: methodName params: parameters [
	"Send a request without request-scoped headers.

	 Arguments:
		methodName - <String> nonempty JSON-RPC method name.
		parameters - <KeyedCollection> parameters, or nil.
	 Answers:
		<Object> decoded JSON-RPC result."

	^self sendRequest: methodName params: parameters headers: nil
]

{ #category : 'Protocol Operations' }
McpClient >> sendRequest: methodName params: parameters headers: requestHeaders [
	"Validate, snapshot, and send one JSON-RPC request.

	 Arguments:
		methodName - <String> nonempty JSON-RPC method name.
		parameters - <KeyedCollection> parameters, or nil.
		requestHeaders - <KeyedCollection> transport headers, or nil.
	 Answers:
		<Object> decoded JSON-RPC result."

	^self
		sendRequest: methodName
		params: parameters
		headers: requestHeaders
		progressToken: nil
		progressCallback: nil
]

{ #category : 'Protocol Operations' }
McpClient >> sendRequest: methodName
	params: parameters
	headers: requestHeaders
	progressToken: aProgressToken
	progressCallback: aProgressCallback [
	"Validate, snapshot, and send one JSON-RPC request with optional progress tracking and caching.

	 Arguments:
		methodName - <String> nonempty JSON-RPC method name.
		parameters - <KeyedCollection> parameters, or nil.
		requestHeaders - <KeyedCollection> transport headers, or nil.
		aProgressToken - <String> or <Integer> progress correlation token, or nil.
		aProgressCallback - <Block> [:progress :total :message | ...], or nil.
	 Answers:
		<Object> decoded JSON-RPC result."

	| identifier request parameterSnapshot headerSnapshot result effectiveToken meta paramsKey
	  cachedResult ttl scope |

	(methodName isString and: [methodName isEmpty not])
		ifFalse: [self error: 'JSON-RPC method must be a nonempty string'].
	(parameters isNil or: [parameters isKindOf: KeyedCollection])
		ifFalse: [self error: 'MCP request params must be keyed or nil'].
	(requestHeaders isNil or: [requestHeaders isKindOf: KeyedCollection])
		ifFalse: [self error: 'MCP request headers must be keyed or nil'].
	self transport ifNil: [self error: 'MCP client transport is not configured'].
	parameterSnapshot := parameters ifNotNil: [self detachedProtocolValue: parameters].
	headerSnapshot := requestHeaders ifNotNil: [self detachedProtocolValue: requestHeaders].
	paramsKey := self cacheParamsKeyFor: methodName params: parameterSnapshot.
	(aProgressCallback isNil and: [headerSnapshot isNil or: [headerSnapshot isEmpty]])
		ifTrue: [
			cachedResult := self responseCache get: methodName key: paramsKey.
			cachedResult ifNotNil: [^cachedResult]].
	effectiveToken := aProgressToken.
	(effectiveToken isNil and: [aProgressCallback notNil])
		ifTrue: [effectiveToken := 'progress-' , UUID new asString].
	effectiveToken ifNotNil: [
		parameterSnapshot ifNil: [parameterSnapshot := EsOrderedDictionary new].
		meta := parameterSnapshot at: '_meta' ifAbsentPut: [EsOrderedDictionary new].
		(meta isKindOf: KeyedCollection) ifTrue: [meta at: 'progressToken' put: effectiveToken]].
	(McpProtocolVersion isModern: self protocolVersion)
		ifTrue: [
			parameterSnapshot ifNil: [parameterSnapshot := EsOrderedDictionary new].
			meta := parameterSnapshot at: '_meta' ifAbsentPut: [EsOrderedDictionary new].
			(meta isKindOf: KeyedCollection)
				ifTrue: [
					(meta includesKey: 'io.modelcontextprotocol/protocolVersion')
						ifFalse: [
							meta
								at: 'io.modelcontextprotocol/protocolVersion'
								put: self protocolVersion].
					(meta includesKey: 'io.modelcontextprotocol/clientCapabilities')
						ifFalse: [
							meta
								at: 'io.modelcontextprotocol/clientCapabilities'
								put: self capabilities].
					(meta includesKey: 'io.modelcontextprotocol/clientInfo')
						ifFalse: [meta at: 'io.modelcontextprotocol/clientInfo' put: self clientInfo]]].
	(headerSnapshot notNil
		and: [headerSnapshot isEmpty not and: [self transport supportsRequestHeaders not]])
			ifTrue: [self error: 'MCP transport does not support scoped headers'].
	self requestMutex critical: [
		identifier := nextRequestId.
		nextRequestId := nextRequestId + 1].
	request :=
		EsOrderedDictionary new
			at: 'jsonrpc' put: '2.0';
			at: 'id' put: identifier;
			at: 'method' put: methodName copy;
			yourself.
	parameterSnapshot ifNotNil: [request at: 'params' put: parameterSnapshot].
	(effectiveToken notNil and: [aProgressCallback notNil])
		ifTrue: [
			progressCallbacksMutex
				critical: [progressCallbacks at: effectiveToken put: aProgressCallback]].
	[
		result :=
			(headerSnapshot isNil
				or: [headerSnapshot isEmpty and: [self transport supportsRequestHeaders not]])
					ifTrue: [self transport sendRequest: request id: identifier]
					ifFalse: [
						self transport sendRequest: request id: identifier headers: headerSnapshot]]
							ensure: [
								effectiveToken ifNotNil: [
									progressCallbacksMutex critical: [
										progressCallbacks removeKey: effectiveToken ifAbsent: [nil]]]].
	(result isKindOf: KeyedCollection)
		ifTrue: [
			ttl := result at: 'ttlMs' ifAbsent: [nil].
			scope := result at: 'cacheScope' ifAbsent: [nil].
			ttl ifNil: [
				(result at: '_meta' ifAbsent: [nil]) ifNotNil: [:resMeta |
					(resMeta isKindOf: KeyedCollection)
						ifTrue: [
							ttl := resMeta at: 'ttlMs' ifAbsent: [nil].
							scope := resMeta at: 'cacheScope' ifAbsent: [nil]]]].
			(ttl notNil and: [ttl > 0])
				ifTrue: [
					self responseCache
						set: methodName
						key: paramsKey
						value: result
						ttlMs: ttl
						scope: scope].
			(result at: '_meta' ifAbsent: [nil]) ifNotNil: [:resMeta |
				(resMeta isKindOf: KeyedCollection)
					ifTrue: [
						(resMeta at: 'io.modelcontextprotocol/serverInfo' ifAbsent: [nil]) ifNotNil: [
							:info |
							(info isKindOf: KeyedCollection)
								ifTrue: [serverInfo := self detachedProtocolValue: info]]]]].
	^result
]

{ #category : 'Protocol Operations',
  #vaVisibility : 'private' }
McpClient >> sendResult: result id: identifier [
	"Send a detached JSON-RPC result for a server-originated request.

	 Arguments:
		result - <Object> JSON-compatible request result.
		identifier - <String> or <Integer> request identifier.
	 Answers:
		<McpClient> the receiver."

	| response resultSnapshot |

	(identifier isString or: [identifier isInteger])
		ifFalse: [self error: 'JSON-RPC response identifier is invalid'].
	resultSnapshot := self detachedProtocolValue: result.
	response :=
		EsOrderedDictionary new
			at: 'jsonrpc' put: '2.0';
			at: 'id' put: identifier;
			at: 'result' put: resultSnapshot;
			yourself.
	self transport sendNotification: response.
	^self
]

{ #category : 'Accessing' }
McpClient >> serverCapabilities [
	"Answer a detached snapshot of negotiated server capabilities.

	 Answers:
		<KeyedCollection> JSON-compatible capability declaration."

	^self detachedProtocolValue: serverCapabilities
]

{ #category : 'Accessing' }
McpClient >> serverInfo [
	"Answer a detached snapshot of negotiated server information.

	 Answers:
		<KeyedCollection> JSON-compatible implementation information."

	^self detachedProtocolValue: serverInfo
]

{ #category : 'Accessing' }
McpClient >> serverSupportsCapability: capabilityName [
	"Answer whether the connected server advertised one capability.

	 Arguments:
		capabilityName - <String> nonempty capability name.
	 Answers:
		<Boolean>."

	| capability |

	(capabilityName isString and: [capabilityName isEmpty not])
		ifFalse: [self error: 'MCP capability name must be a nonempty string'].
	self checkConnected.
	capability := serverCapabilities at: capabilityName ifAbsent: [^false].
	(capability isKindOf: KeyedCollection)
		ifFalse: [self error: 'Invalid server capability declaration: ' , capabilityName].
	^true
]

{ #category : 'Accessing' }
McpClient >> serverVersion [
	"Answer the negotiated server implementation version.

	 Answers:
		<String>, or `unknown` when the server did not supply one."

	^self serverInfo at: 'version' ifAbsent: ['unknown']
]

{ #category : 'Accessing' }
McpClient >> transport [
	"Answer the configured client transport.

	 Answers:
		<McpClientTransport> or nil."

	^transport
]

{ #category : 'Accessing' }
McpClient >> transport: aTransport [
	"Replace the client transport after safely closing the prior transport.

	 A transport already owned by another client is rejected. Passing nil
	 detaches the current transport after closing it.

	 Arguments:
		aTransport - <McpClientTransport> or nil.
	 Answers:
		<McpClient> the receiver."

	| priorTransport |

	(aTransport isNil or: [aTransport isKindOf: McpClientTransport])
		ifFalse: [self error: 'MCP client transport has an invalid type'].
	priorTransport := transport.
	priorTransport == aTransport ifTrue: [^self].
	aTransport ifNotNil: [| priorOwner |
		priorOwner := aTransport client.
		(priorOwner notNil and: [priorOwner ~~ self])
			ifTrue: [self error: 'MCP transport already belongs to another client']].
	priorTransport ifNotNil: [
		self close.
		priorTransport client: nil].
	transport := aTransport.
	transport ifNotNil: [transport client: self].
	^self
]

{ #category : 'Validation',
  #vaVisibility : 'private' }
McpClient >> validateContentBlock: content [
	"Validate one MCP content block received from the server.

	 Arguments:
		content - <Object> content candidate.
	 Answers:
		<McpClient> the receiver."

	| type resource value |

	(content isKindOf: KeyedCollection) ifFalse: [self error: 'MCP content block must be keyed'].
	type := content at: 'type' ifAbsent: [nil].
	type = 'text'
		ifTrue: [
			((content at: 'text' ifAbsent: [nil]) isString)
				ifFalse: [self error: 'MCP text content requires text'].
			^self].
	(type = 'image' or: [type = 'audio'])
		ifTrue: [
			#('data' 'mimeType') do: [:field |
				value := content at: field ifAbsent: [nil].
				value isString ifFalse: [self error: 'MCP media content requires data and MIME type']].
			^self].
	type = 'resource'
		ifTrue: [
			resource := content at: 'resource' ifAbsent: [nil].
			self validateResourceContents: resource.
			^self].
	type = 'resource_link'
		ifTrue: [
			#('uri' 'name') do: [:field |
				value := content at: field ifAbsent: [nil].
				(value isString and: [value isEmpty not])
					ifFalse: [self error: 'MCP resource link requires URI and name']].
			(self isValidAbsoluteResourceUri: (content at: 'uri'))
				ifFalse: [self error: 'MCP resource link URI must be absolute'].
			^self].
	self error: 'MCP content block has an unsupported type'
]

{ #category : 'Validation',
  #vaVisibility : 'private' }
McpClient >> validateIconsIn: definition label: label [
	"Validate optional icon definitions in one advertised definition.

	 Arguments:
		definition - <KeyedCollection> advertised definition.
		label - <String> diagnostic subject.
	 Answers:
		<McpClient> the receiver."

	| icons sizes |

	icons := definition at: 'icons' ifAbsent: [nil].
	icons ifNil: [^self].
	(self isProtocolArray: icons) ifFalse: [self error: label , ' icons must be an array'].
	icons do: [:icon | | source mimeType theme |
		(icon isKindOf: KeyedCollection) ifFalse: [self error: label , ' icons must be keyed'].
		source := icon at: 'src' ifAbsent: [nil].
		(source isString and: [source isEmpty not])
			ifFalse: [self error: label , ' icon requires a source'].
		(self isValidAbsoluteResourceUri: source)
			ifFalse: [self error: label , ' icon source must be an absolute URI'].
		mimeType := icon at: 'mimeType' ifAbsent: [nil].
		(mimeType isNil or: [mimeType isString])
			ifFalse: [self error: label , ' icon mimeType must be a string'].
		sizes := icon at: 'sizes' ifAbsent: [nil].
		sizes ifNotNil: [
			(self isProtocolArray: sizes)
				ifFalse: [self error: label , ' icon sizes must be an array'].
			(sizes allSatisfy: [:sizeString | sizeString isString and: [sizeString isEmpty not]])
				ifFalse: [self error: label , ' icon sizes must contain strings']].
		theme := icon at: 'theme' ifAbsent: [nil].
		(theme isNil or: [#('light' 'dark') includes: theme])
			ifFalse: [self error: label , ' icon theme is invalid']].
	^self
]

{ #category : 'Validation',
  #vaVisibility : 'private' }
McpClient >> validateListedDefinition: definition forMethod: methodName [
	"Validate one definition according to its listing operation.

	 Arguments:
		definition - <Object> advertised definition candidate.
		methodName - <String> JSON-RPC listing method.
	 Answers:
		<McpClient> the receiver."

	methodName = 'tools/list' ifTrue: [^self validateToolDefinition: definition].
	methodName = 'prompts/list' ifTrue: [^self validatePromptDefinition: definition].
	methodName = 'resources/list' ifTrue: [^self validateResourceDefinition: definition].
	methodName = 'resources/templates/list'
		ifTrue: [^self validateResourceTemplateDefinition: definition].
	self error: 'Unsupported MCP pagination method: ' , methodName
]

{ #category : 'Validation',
  #vaVisibility : 'private' }
McpClient >> validateNamedDefinition: definition label: label [
	"Validate the common name and metadata fields of a definition.

	 Arguments:
		definition - <Object> advertised definition candidate.
		label - <String> diagnostic subject.
	 Answers:
		<McpClient> the receiver."

	| name value |

	(definition isKindOf: KeyedCollection) ifFalse: [self error: label , ' definition must be keyed'].
	name := definition at: 'name' ifAbsent: [nil].
	(name isString and: [name isEmpty not])
		ifFalse: [self error: label , ' name must be a nonempty string'].
	#('title' 'description') do: [:field |
		value := definition at: field ifAbsent: [nil].
		(value isNil or: [value isString])
			ifFalse: [self error: label , ' ' , field , ' must be a string']].
	#('annotations' '_meta') do: [:field |
		value := definition at: field ifAbsent: [nil].
		(value isNil or: [value isKindOf: KeyedCollection])
			ifFalse: [self error: label , ' ' , field , ' must be keyed']].
	self validateIconsIn: definition label: label.
	^self
]

{ #category : 'Validation',
  #vaVisibility : 'private' }
McpClient >> validateObjectSchema: schema label: label [
	"Validate the object-root requirement of an MCP tool schema.

	 Arguments:
		schema - <Object> JSON Schema candidate.
		label - <String> diagnostic field name.
	 Answers:
		<McpClient> the receiver."

	(schema isKindOf: KeyedCollection) ifFalse: [self error: label , ' must be keyed'].
	(schema at: 'type' ifAbsent: [nil]) = 'object'
		ifFalse: [self error: label , ' must declare object type'].
	^self
]

{ #category : 'Validation',
  #vaVisibility : 'private' }
McpClient >> validatePromptArguments: arguments [
	"Validate optional prompt argument declarations and unique names.

	 Arguments:
		arguments - <Object> argument definitions, or nil.
	 Answers:
		<McpClient> the receiver."

	| names value |

	arguments ifNil: [^self].
	(self isProtocolArray: arguments) ifFalse: [self error: 'Prompt arguments must be an array'].
	names := Set new.
	arguments do: [:argument | | argumentName |
		(argument isKindOf: KeyedCollection)
			ifFalse: [self error: 'Prompt argument definition must be keyed'].
		argumentName := argument at: 'name' ifAbsent: [nil].
		(argumentName isString and: [argumentName isEmpty not])
			ifFalse: [self error: 'Prompt argument name must be nonempty'].
		(names includes: argumentName)
			ifTrue: [self error: 'Duplicate prompt argument: ' , argumentName].
		names add: argumentName.
		#('title' 'description') do: [:field |
			value := argument at: field ifAbsent: [nil].
			(value isNil or: [value isString])
				ifFalse: [self error: 'Prompt argument ' , field , ' must be a string']].
		value := argument at: 'required' ifAbsent: [nil].
		(value isNil or: [value isBoolean])
			ifFalse: [self error: 'Prompt argument required must be boolean']].
	^self
]

{ #category : 'Validation',
  #vaVisibility : 'private' }
McpClient >> validatePromptDefinition: definition [
	"Validate one advertised MCP prompt definition.

	 Arguments:
		definition - <Object> prompt definition candidate.
	 Answers:
		<McpClient> the receiver."

	self validateNamedDefinition: definition label: 'Prompt'.
	self validatePromptArguments: (definition at: 'arguments' ifAbsent: [nil]).
	^self
]

{ #category : 'Validation',
  #vaVisibility : 'private' }
McpClient >> validatePromptMessage: message [
	"Validate one prompt message received from the server.

	 Arguments:
		message - <Object> prompt message candidate.
	 Answers:
		<McpClient> the receiver."

	| role content |

	(message isKindOf: KeyedCollection) ifFalse: [self error: 'MCP prompt message must be keyed'].
	role := message at: 'role' ifAbsent: [nil].
	(#('user' 'assistant') includes: role)
		ifFalse: [self error: 'MCP prompt message role is invalid'].
	content := message at: 'content' ifAbsent: [nil].
	self validateContentBlock: content.
	^self
]

{ #category : 'Validation',
  #vaVisibility : 'private' }
McpClient >> validateResourceContents: content [
	"Validate one text or blob resource-contents object.

	 Arguments:
		content - <Object> resource contents candidate.
	 Answers:
		<McpClient> the receiver."

	| uri mimeType hasText hasBlob value |

	(content isKindOf: KeyedCollection) ifFalse: [self error: 'MCP resource contents must be keyed'].
	uri := content at: 'uri' ifAbsent: [nil].
	(self isValidAbsoluteResourceUri: uri)
		ifFalse: [self error: 'MCP resource contents requires an absolute URI'].
	mimeType := content at: 'mimeType' ifAbsent: [nil].
	(mimeType isNil or: [mimeType isString and: [mimeType isEmpty not]])
		ifFalse: [self error: 'MCP resource contents MIME type is invalid'].
	hasText := content includesKey: 'text'.
	hasBlob := content includesKey: 'blob'.
	hasText = hasBlob ifTrue: [self error: 'MCP resource contents requires either text or blob'].
	value := content at: (hasText ifTrue: ['text'] ifFalse: ['blob']).
	value isString ifFalse: [self error: 'MCP resource contents payload must be a string'].
	^self
]

{ #category : 'Validation',
  #vaVisibility : 'private' }
McpClient >> validateResourceDefinition: definition [
	"Validate one advertised MCP resource definition.

	 Arguments:
		definition - <Object> resource definition candidate.
	 Answers:
		<McpClient> the receiver."

	| uri mimeType size |

	self validateNamedDefinition: definition label: 'Resource'.
	uri := definition at: 'uri' ifAbsent: [nil].
	(self isValidAbsoluteResourceUri: uri)
		ifFalse: [self error: 'Resource definition requires an absolute URI'].
	mimeType := definition at: 'mimeType' ifAbsent: [nil].
	(mimeType isNil or: [mimeType isString and: [mimeType isEmpty not]])
		ifFalse: [self error: 'Resource MIME type is invalid'].
	size := definition at: 'size' ifAbsent: [nil].
	(size isNil or: [size isInteger and: [size >= 0]])
		ifFalse: [self error: 'Resource size must be a nonnegative integer'].
	^self
]

{ #category : 'Validation',
  #vaVisibility : 'private' }
McpClient >> validateResourceTemplateDefinition: definition [
	"Validate one advertised MCP resource-template definition.

	 Arguments:
		definition - <Object> template definition candidate.
	 Answers:
		<McpClient> the receiver."

	| uriTemplate mimeType |

	self validateNamedDefinition: definition label: 'Resource template'.
	uriTemplate := definition at: 'uriTemplate' ifAbsent: [nil].
	(uriTemplate isString and: [uriTemplate isEmpty not])
		ifFalse: [self error: 'Resource template requires uriTemplate'].
	self validateUriTemplate: uriTemplate.
	mimeType := definition at: 'mimeType' ifAbsent: [nil].
	(mimeType isNil or: [mimeType isString and: [mimeType isEmpty not]])
		ifFalse: [self error: 'Resource-template MIME type is invalid'].
	^self
]

{ #category : 'Validation',
  #vaVisibility : 'private' }
McpClient >> validateToolDefinition: definition [
	"Validate one advertised MCP tool definition.

	 Arguments:
		definition - <Object> tool definition candidate.
	 Answers:
		<McpClient> the receiver."

	| name schema execution |

	self validateNamedDefinition: definition label: 'Tool'.
	name := definition at: 'name'.
	name size <= 128 ifFalse: [self error:
		'Tool name must not exceed 128 characters'].
	schema := definition at: 'inputSchema' ifAbsent: [nil].
	self validateObjectSchema: schema label: 'Tool inputSchema'.
	self validateToolParamHeaders: schema.
	schema := definition at: 'outputSchema' ifAbsent: [nil].
	(schema notNil and: [(schema isKindOf: KeyedCollection) not])
		ifTrue: [self error: 'Tool outputSchema must be keyed'].
	execution := definition at: 'execution' ifAbsent: [nil].
	execution ifNotNil: [| taskSupport |
		(execution isKindOf: KeyedCollection)
			ifFalse: [self error: 'Tool execution metadata must be keyed'].
		taskSupport := execution at: 'taskSupport' ifAbsent: [nil].
		(taskSupport isNil or: [#('forbidden' 'optional' 'required') includes:
			taskSupport])
			ifFalse: [self error: 'Tool taskSupport value is invalid']].
	^self
]

{ #category : 'Validation' }
McpClient >> validateToolParamHeaders: schema [
	"Traverse a tool schema properties and validate x-mcp-header annotations."

	| properties |
	schema ifNil: [^self].
	(schema isKindOf: KeyedCollection) ifFalse: [^self].
	properties := schema at: 'properties' ifAbsent: [nil].
	(properties isKindOf: KeyedCollection) ifFalse: [^self].

	properties keysAndValuesDo: [:propName :propDef |
		(propDef isKindOf: KeyedCollection) ifTrue: [
			(propDef includesKey: 'x-mcp-header') ifTrue: [ | headerVal |
				headerVal := propDef at: 'x-mcp-header'.
				(headerVal isString or: [headerVal = true]) ifFalse: [
					self error: 'Tool x-mcp-header must be true or a string'.
				].
				headerVal isString ifTrue: [
					(headerVal isEmpty) ifTrue: [
						self error: 'Tool x-mcp-header string must not be empty'.
					].
					(self isValidHeaderToken: headerVal) ifFalse: [
						self error: 'Tool x-mcp-header contains invalid characters'.
					].
				].
				(self isPrimitiveTypeAllowedForParamHeader: propDef) ifFalse: [
					self error: 'Tool x-mcp-header only allowed on primitive types'.
				].
			] ifFalse: [
				(propDef includesKey: 'properties') ifTrue: [
					self validateToolParamHeaders: propDef
				]
			]
		]
	]
]

{ #category : 'Validation',
  #vaVisibility : 'private' }
McpClient >> validateUriTemplate: uriTemplate [
	"Validate the basic structure of an absolute RFC 6570 URI template.

	 Arguments:
		uriTemplate - <String> URI-template candidate.
	 Answers:
		<McpClient> the receiver."

	| colonIndex scheme index insideExpression expressionHasContent |

	colonIndex := uriTemplate indexOf: $:.
	colonIndex > 1 ifFalse: [self error: 'Resource template must use an absolute URI scheme'].
	scheme := uriTemplate copyFrom: 1 to: colonIndex - 1.
	index := 0.
	(scheme allSatisfy: [:character |
		index := index + 1.
		self isValidResourceUriSchemeCharacter: character first: index = 1])
			ifFalse: [self error: 'Resource template has an invalid URI scheme'].
	insideExpression := false.
	expressionHasContent := false.
	uriTemplate do: [:character |
		character = ${
			ifTrue: [
				insideExpression ifTrue: [self error: 'Resource template expressions cannot nest'].
				insideExpression := true.
				expressionHasContent := false]
			ifFalse: [
				character = $}
					ifTrue: [
						(insideExpression and: [expressionHasContent])
							ifFalse: [self error: 'Resource template expression is malformed'].
						insideExpression := false]
					ifFalse: [insideExpression ifTrue: [expressionHasContent := true]]]].
	insideExpression ifTrue: [self error: 'Resource template expression is not closed'].
	^self
]

{ #category : 'Validation',
  #vaVisibility : 'private' }
McpClient >> validatedCompletionResult: aDictionary [
	"Validate and answer the detached completion payload from a CompleteResult.

	 Arguments:
		aDictionary - <KeyedCollection> decoded JSON-RPC result.
	 Answers:
		<KeyedCollection> completion dictionary containing values, and optional total/hasMore."

	| completion values |

	(aDictionary isKindOf: KeyedCollection)
		ifFalse: [self error: 'Invalid CompleteResult: expected an object'].
	completion :=
		aDictionary
			at: 'completion'
			ifAbsent: [self error: 'Invalid CompleteResult: missing completion property'].
	(completion isKindOf: KeyedCollection)
		ifFalse: [self error: 'Invalid CompleteResult: completion must be an object'].
	values :=
		completion
			at: 'values'
			ifAbsent: [self error: 'Invalid CompleteResult: missing completion values'].
	(values isKindOf: Collection)
		ifFalse: [self error: 'Invalid CompleteResult: completion values must be a collection'].
	values size > 100
		ifTrue: [self error: 'Invalid CompleteResult: completion values must not exceed 100 items'].
	^self detachedProtocolValue: completion
]

{ #category : 'Validation',
  #vaVisibility : 'private' }
McpClient >> validatedPromptResult: result [
	"Validate and detach one MCP GetPromptResult.

	 Arguments:
		result - <Object> result candidate.
	 Answers:
		<KeyedCollection> detached result."

	| description messages |

	(result isKindOf: KeyedCollection) ifFalse: [self error: 'MCP prompt result must be keyed'].
	description := result at: 'description' ifAbsent: [nil].
	(description isNil or: [description isString])
		ifFalse: [self error: 'MCP prompt result description must be a string'].
	messages := result at: 'messages' ifAbsent: [nil].
	(self isProtocolArray: messages)
		ifFalse: [self error: 'MCP prompt result messages must be an array'].
	messages do: [:message | self validatePromptMessage: message].
	^self detachedProtocolValue: result
]

{ #category : 'Validation',
  #vaVisibility : 'private' }
McpClient >> validatedResourceResult: result [
	"Validate and detach one MCP ReadResourceResult.

	 Arguments:
		result - <Object> result candidate.
	 Answers:
		<KeyedCollection> detached result."

	| contents |

	(result isKindOf: KeyedCollection) ifFalse: [self error: 'MCP resource result must be keyed'].
	contents := result at: 'contents' ifAbsent: [nil].
	(self isProtocolArray: contents)
		ifFalse: [self error: 'MCP resource result contents must be an array'].
	contents do: [:content | self validateResourceContents: content].
	^self detachedProtocolValue: result
]

{ #category : 'Validation',
  #vaVisibility : 'private' }
McpClient >> validatedToolResult: result [
	"Validate and detach one MCP CallToolResult.

	 Arguments:
		result - <Object> result candidate.
	 Answers:
		<KeyedCollection> detached result."

	| content isError structured |

	(result isKindOf: KeyedCollection) ifFalse: [self error: 'MCP tool result must be keyed'].
	content := result at: 'content' ifAbsent: [nil].
	(self isProtocolArray: content) ifFalse: [self error: 'MCP tool result content must be an array'].
	content do: [:item | self validateContentBlock: item].
	isError := result at: 'isError' ifAbsent: [false].
	isError isBoolean ifFalse: [self error: 'MCP tool result isError must be boolean'].
	^self detachedProtocolValue: result
]

{ #category : 'Validation' }
McpClient >> validatedToolResult: result forTool: toolName headers: requestHeaders [
	"Validate successful structured output with no external schema access.
	Arguments:
		result - <Object> tool response.
		toolName - <String> requested tool.
		requestHeaders - <KeyedCollection | nil> discovery credentials.
	Answers:
		<KeyedCollection> detached result.
	Raises:
		<Error> missing output, invalid content, or unresolvable schema."
	| checked schema structured schemas |
	checked := self validatedToolResult: result.
	(checked at: 'isError' ifAbsent: [false]) ifTrue: [^checked].
	schemas := self knownToolOutputSchemas.
	((requestHeaders notNil and: [requestHeaders isEmpty not]) or: [
		(self knownToolOutputSchemas includesKey: toolName) not]) ifTrue: [
		schemas := self refreshOutputSchemasWithHeaders: requestHeaders].
	schema := schemas at: toolName ifAbsent: [nil].
	schema ifNil: [^checked].
	structured := checked at: 'structuredContent' ifAbsent: [nil].
	structured ifNil: [
		self error: 'Tool ' , toolName ,
			' has an output schema but no structured content'].
	[
		[McpSchemaValidator new validate: structured against: schema]
			on: McpJsonRpcError do: [:mismatch |
				self error: 'Invalid structured content returned by tool ' ,
				toolName]
	] on: Error do: [:failure |
		(failure messageText beginsWithSubCollection:
			'Invalid structured content returned by tool ') ifTrue: [failure
				pass].
		self error: 'Invalid schema for tool ' , toolName , ': ' , failure
			messageText].
	^checked

]
