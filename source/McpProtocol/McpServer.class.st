"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# McpServer

`McpServer` implements transport-neutral MCP server operations supporting
dual-era negotiation.

## Responsibilities

- Own prompt, resource, template, and tool registries.
- Support pluggable extensions via `extensions` and `addExtension:`.
- Enforce client extension requirements via `requireClientExtension:context:` (-32021).
- Support modern discovery via `serverDiscover:context:`.
- Format modern response envelopes with `resultType: 'complete'` or `'input_required'`.
- Enforce cryptographic integrity of `requestState` tokens via `McpRequestStateSecurity`.
- Manage change subscriptions via `McpSubscriptionBus`.

## Lifecycle and boundaries

A host owns the server; registries remain live until host shutdown.
"
Class {
	#name : 'McpServer',
	#superclass : 'Object',
	#instVars : [
		'name',
		'version',
		'toolRegistry',
		'capabilities',
		'listPageSize',
		'promptRegistry',
		'resourceRegistry',
		'resourceTemplateRegistry',
		'completionBlock',
		'subscriptionBus',
		'requestStateSecurity',
		'extensions'
	],
	#pools : [
		'McpJsonRpcConstants'
	],
	#category : 'McpProtocol'
}

{ #category : 'Instance Creation' }
McpServer class >> new [
	"Answer a new initialized transport-neutral MCP server.

	 Answers:
		<McpServer>."

	^super new initialize
]

{ #category : 'Registration' }
McpServer >> addExtension: anExtension [
	"Register an MCP extension, importing its contributed tools and resources.

	 Arguments:
		anExtension - <McpExtension>.
	 Answers:
		<McpServer> the receiver."

	self extensions add: anExtension.
	anExtension tools do: [:tool | self toolRegistry registerTool: tool].
	anExtension resources do: [:res | self resourceRegistry registerResource: res].
	^self
]

{ #category : 'Protocol Operations' }
McpServer >> cancelledNotification: parameters context: requestContext [
	"Handle a client notifications/cancelled event for an in-flight request.

	 Arguments:
		parameters - <KeyedCollection> cancellation parameters (requestId, reason).
		requestContext - <McpServerRequestContext> or nil.
	 Answers:
		<McpServer> the receiver."

	| targetRequestId reason |

	(parameters isKindOf: KeyedCollection) ifFalse: [^self].
	targetRequestId := parameters at: 'requestId' ifAbsent: [nil].
	targetRequestId ifNil: [^self].
	reason := parameters at: 'reason' ifAbsent: ['Cancelled by client'].
	^self
]

{ #category : 'Accessing' }
McpServer >> capabilities [
	"Answer a detached copy of the implemented server capabilities.

	 Answers:
		<KeyedCollection> JSON-compatible capabilities."

	(capabilities includesKey: 'prompts')
		ifFalse: [capabilities at: 'prompts' put: (EsOrderedDictionary with: 'listChanged' -> false)].
	(capabilities includesKey: 'resources')
		ifFalse: [capabilities at: 'resources' put: EsOrderedDictionary new].
	(capabilities includesKey: 'completions')
		ifFalse: [capabilities at: 'completions' put: EsOrderedDictionary new].
	self extensions notEmpty
		ifTrue: [| extDict |
			extDict := EsOrderedDictionary new.
			self extensions do: [:ext | extDict at: ext identifier put: ext settings].
			capabilities at: 'extensions' put: extDict].
	^self detachedProtocolValue: capabilities
]

{ #category : 'Accessing' }
McpServer >> completionBlock [
	"Answer the optional global completion block handler.

	 Answers:
		<Block> or nil."

	^completionBlock
]

{ #category : 'Accessing' }
McpServer >> completionBlock: aBlock [
	"Set the global completion block handler.

	 Arguments:
		aBlock - <Block> or nil.
	 Answers:
		<McpServer> the receiver."

	(aBlock isNil or: [aBlock isKindOf: Block])
		ifFalse: [self error: 'MCP completion handler must be a block or nil'].
	completionBlock := aBlock.
	^self
]

{ #category : 'Protocol Operations' }
McpServer >> completionComplete: parameters [
	"Handle a completion/complete request without explicit context.

	 Arguments:
		parameters - <KeyedCollection> CompleteRequestParams.
	 Answers:
		<KeyedCollection> CompleteResult."

	^self completionComplete: parameters context: nil
]

{ #category : 'Protocol Operations' }
McpServer >> completionComplete: parameters context: requestContext [
	"Handle a completion/complete request according to the MCP specification.

	 Arguments:
		parameters - <KeyedCollection> CompleteRequestParams.
		requestContext - <McpServerRequestContext> or nil.
	 Answers:
		<KeyedCollection> CompleteResult."

	| ref argument context refType promptName uri rawResult prompt template result |

	(parameters isKindOf: KeyedCollection)
		ifFalse: [
			McpJsonRpcError
				signalCode: McpJsonRpcInvalidParamsCode
				message: 'Invalid params: expected an object'].
	ref :=
		parameters
			at: 'ref'
			ifAbsent: [
				McpJsonRpcError
					signalCode: McpJsonRpcInvalidParamsCode
					message: 'Missing completion ref'].
	(ref isKindOf: KeyedCollection)
		ifFalse: [
			McpJsonRpcError
				signalCode: McpJsonRpcInvalidParamsCode
				message: 'Invalid completion ref: expected an object'].
	refType :=
		ref
			at: 'type'
			ifAbsent: [
				McpJsonRpcError
					signalCode: McpJsonRpcInvalidParamsCode
					message: 'Missing completion ref type'].
	(#('ref/prompt' 'ref/resource') includes: refType)
		ifFalse: [
			McpJsonRpcError
				signalCode: McpJsonRpcInvalidParamsCode
				message: 'Unsupported completion ref type: ' , refType printString].
	argument :=
		parameters
			at: 'argument'
			ifAbsent: [
				McpJsonRpcError
					signalCode: McpJsonRpcInvalidParamsCode
					message: 'Missing completion argument'].
	(argument isKindOf: KeyedCollection)
		ifFalse: [
			McpJsonRpcError
				signalCode: McpJsonRpcInvalidParamsCode
				message: 'Invalid completion argument: expected an object'].
	(argument at: 'name' ifAbsent: [nil]) ifNil: [
		McpJsonRpcError
			signalCode: McpJsonRpcInvalidParamsCode
			message: 'Missing completion argument name'].
	context := parameters at: 'context' ifAbsent: [nil].
	(context notNil and: [(context isKindOf: KeyedCollection) not])
		ifTrue: [
			McpJsonRpcError
				signalCode: McpJsonRpcInvalidParamsCode
				message: 'Invalid completion context: expected an object'].

	self completionBlock ifNotNil: [:block |
		rawResult := block cull: ref cull: argument cull: context cull: self.
		result := self normalizeCompletionResult: rawResult.
		(self isModernContext: requestContext orParams: parameters) ifTrue: [ result at: 'resultType' put: 'complete' ].
		^result].

	refType = 'ref/prompt'
		ifTrue: [
			promptName :=
				ref
					at: 'name'
					ifAbsent: [
						McpJsonRpcError
							signalCode: McpJsonRpcInvalidParamsCode
							message: 'Missing prompt name in completion ref'].
			prompt :=
				self promptRegistry
					promptNamed: promptName
					ifAbsent: [
						McpJsonRpcError
							signalCode: McpJsonRpcInvalidParamsCode
							message: 'Unknown prompt: ' , promptName].
			rawResult :=
				(prompt respondsTo: #completeArgument:value:context:)
					ifTrue: [
						prompt
							completeArgument: (argument at: 'name')
							value: (argument at: 'value' ifAbsent: [''])
							context: context]
					ifFalse: [#()].
			result := self normalizeCompletionResult: rawResult.
			(self isModernContext: requestContext orParams: parameters) ifTrue: [ result at: 'resultType' put: 'complete' ].
			^result].

	refType = 'ref/resource'
		ifTrue: [
			uri :=
				ref
					at: 'uri'
					ifAbsent: [
						McpJsonRpcError
							signalCode: McpJsonRpcInvalidParamsCode
							message: 'Missing resource URI in completion ref'].
			template :=
				self resourceTemplateRegistry templates
					at: uri
					ifAbsent: [
						self resourceTemplateRegistry templateMatchingUri: uri ifAbsent: [nil]].
			template ifNil: [
				McpJsonRpcError
					signalCode: McpJsonRpcInvalidParamsCode
					message: 'Unknown resource template: ' , uri].
			rawResult :=
				(template respondsTo: #completeArgument:value:context:)
					ifTrue: [
						template
							completeArgument: (argument at: 'name')
							value: (argument at: 'value' ifAbsent: [''])
							context: context]
					ifFalse: [#()].
			result := self normalizeCompletionResult: rawResult.
			(self isModernContext: requestContext orParams: parameters) ifTrue: [ result at: 'resultType' put: 'complete' ].
			^result].

	result := self normalizeCompletionResult: #().
	(self isModernContext: requestContext orParams: parameters) ifTrue: [ result at: 'resultType' put: 'complete' ].
	^result
]

{ #category : 'Accessing',
  #vaVisibility : 'private' }
McpServer >> cursorOffsetFrom: cursor totalSize: totalSize [
	"Decode and validate one opaque list cursor.

	 Arguments:
		cursor - <String> decimal offset, or nil.
		totalSize - <Integer> current definition count.
	 Answers:
		<Integer> zero-based list offset."

	| offset |

	cursor ifNil: [^0].
	(cursor isString and: [
		cursor isEmpty not
			and: [cursor allSatisfy: [:character | self isDecimalCursorCharacter: character]]])
				ifFalse: [
					McpJsonRpcError
						signalCode: McpJsonRpcInvalidParamsCode
						message: 'Invalid params: malformed cursor'
						data: nil].
	offset := cursor asNumber.
	(offset between: 0 and: totalSize)
		ifFalse: [
			McpJsonRpcError
				signalCode: McpJsonRpcInvalidParamsCode
				message: 'Invalid params: expired cursor'
				data: nil].
	^offset
]

{ #category : 'Serialization',
  #vaVisibility : 'private' }
McpServer >> detachedProtocolValue: anObject [
	"Answer an isolated copy of a JSON-compatible protocol value.

	 Arguments:
		anObject - <Object> JSON-compatible value.
	 Answers:
		<Object> detached value."

	^self detachedProtocolValue: anObject visited: IdentitySet new
]

{ #category : 'Serialization',
  #vaVisibility : 'private' }
McpServer >> detachedProtocolValue: anObject visited: visitedObjects [
	"Copy a protocol value while rejecting cycles and arbitrary objects.

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
	self error: 'MCP server metadata contains a non-JSON-compatible value'
]

{ #category : 'Accessing' }
McpServer >> extensions [
	"Answer the collection of registered MCP extensions.

	 Answers:
		<OrderedCollection> of <McpExtension>."

	extensions ifNil: [extensions := OrderedCollection new].
	^extensions
]

{ #category : 'Initialization',
  #vaVisibility : 'private' }
McpServer >> initialize [
	"Initialize identity, registries, capabilities, and pagination.

	 Answers:
		<McpServer> the receiver."

	| toolCapability promptCapability |

	super initialize.
	toolRegistry := McpToolRegistry new.
	promptRegistry := McpPromptRegistry new.
	resourceRegistry := McpResourceRegistry new.
	resourceTemplateRegistry := McpResourceTemplateRegistry new.
	subscriptionBus := McpSubscriptionBus new.
	name := 'VastMcpServer'.
	version := '1.0.0'.
	listPageSize := 100.
	toolCapability := EsOrderedDictionary with: 'listChanged' -> false.
	promptCapability := EsOrderedDictionary with: 'listChanged' -> false.
	capabilities :=
		EsOrderedDictionary new
			at: 'tools' put: toolCapability;
			at: 'prompts' put: promptCapability;
			at: 'resources' put: EsOrderedDictionary new;
			yourself.
	^self
]

{ #category : 'Initialization' }
McpServer >> initializeProtocol: parameters [
	"Validate initialization and answer negotiated server metadata.
	 The initialize handshake negotiates among supported handshake-era versions.

	 Arguments:
		parameters - <KeyedCollection> client initialization parameters.
	 Answers:
		<KeyedCollection> MCP InitializeResult."

	| result serverMetadata clientVersion clientCapabilities clientMetadata clientName
	  clientVersionName negotiatedVersion |

	clientVersion :=
		parameters
			at: 'protocolVersion'
			ifAbsent: [
				McpJsonRpcError
					signalCode: McpJsonRpcInvalidParamsCode
					message: 'Missing protocolVersion'
					data: nil].
	clientVersion isString
		ifFalse: [
			McpJsonRpcError
				signalCode: McpJsonRpcInvalidParamsCode
				message: 'protocolVersion must be a string'
				data: nil].
	clientCapabilities :=
		parameters
			at: 'capabilities'
			ifAbsent: [
				McpJsonRpcError
					signalCode: McpJsonRpcInvalidParamsCode
					message: 'Missing capabilities'
					data: nil].
	(clientCapabilities isKindOf: KeyedCollection)
		ifFalse: [
			McpJsonRpcError
				signalCode: McpJsonRpcInvalidParamsCode
				message: 'capabilities must be a keyed collection'
				data: nil].
	clientMetadata :=
		parameters
			at: 'clientInfo'
			ifAbsent: [
				McpJsonRpcError
					signalCode: McpJsonRpcInvalidParamsCode
					message: 'Missing clientInfo'
					data: nil].
	(clientMetadata isKindOf: KeyedCollection)
		ifFalse: [
			McpJsonRpcError
				signalCode: McpJsonRpcInvalidParamsCode
				message: 'clientInfo must be a keyed collection'
				data: nil].
	clientName := clientMetadata at: 'name' ifAbsent: [nil].
	clientVersionName := clientMetadata at: 'version' ifAbsent: [nil].
	(clientName isString and: [clientName isEmpty not])
		ifFalse: [
			McpJsonRpcError
				signalCode: McpJsonRpcInvalidParamsCode
				message: 'clientInfo requires a nonempty name'
				data: nil].
	(clientVersionName isString and: [clientVersionName isEmpty not])
		ifFalse: [
			McpJsonRpcError
				signalCode: McpJsonRpcInvalidParamsCode
				message: 'clientInfo requires a nonempty version'
				data: nil].
	negotiatedVersion :=
		(self supportedHandshakeProtocolVersions includes: clientVersion)
			ifTrue: [clientVersion]
			ifFalse: [self supportedHandshakeProtocolVersions first].
	serverMetadata :=
		EsOrderedDictionary new
			at: 'name' put: self name;
			at: 'version' put: self version;
			yourself.
	result :=
		EsOrderedDictionary new
			at: 'protocolVersion' put: negotiatedVersion;
			at: 'serverInfo' put: serverMetadata;
			at: 'capabilities' put: self capabilities;
			yourself.
	^result
]

{ #category : 'Initialization' }
McpServer >> initializedNotification: parameters [
	"Accept the client notification that initialization completed.

	 Session lifecycle enforcement belongs to the server transport.

	 Arguments:
		parameters - <KeyedCollection> notification parameters.
	 Answers:
		nil."

	^nil
]

{ #category : 'Accessing',
  #vaVisibility : 'private' }
McpServer >> isDecimalCursorCharacter: aCharacter [
	"Answer whether a character is an ASCII decimal digit.

	 Arguments:
		aCharacter - <Character> cursor character.
	 Answers:
		<Boolean>."

	| codePoint |

	codePoint := aCharacter codePoint.
	^codePoint between: $0 codePoint and: $9 codePoint
]

{ #category : 'Testing' }
McpServer >> isModernContext: requestContext orParams: parameters [
	"Answer whether the current invocation is under a modern protocol era.

	 Arguments:
		requestContext - <McpServerRequestContext> or nil.
		parameters - <KeyedCollection> or nil.
	 Answers:
		<Boolean>."

	(requestContext notNil and: [McpProtocolVersion isModern: requestContext protocolVersion])
		ifTrue: [^true].
	(parameters isKindOf: KeyedCollection)
		ifTrue: [
			(parameters at: '_meta' ifAbsent: [nil]) ifNotNil: [:meta |
				(meta isKindOf: KeyedCollection)
					ifTrue: [
						(meta at: 'io.modelcontextprotocol/protocolVersion' ifAbsent: [nil])
							ifNotNil: [:v | (McpProtocolVersion isModern: v) ifTrue: [^true]]]]].
	^false
]

{ #category : 'Validation',
  #vaVisibility : 'private' }
McpServer >> isValidAbsoluteResourceUri: anObject [
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

{ #category : 'Validation',
  #vaVisibility : 'private' }
McpServer >> isValidResourceUriSchemeCharacter: aCharacter first: isFirst [
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

{ #category : 'Protocol Operations' }
McpServer >> listPageSize [
	"Answer the maximum number of definitions in one list result.

	 Answers:
		<Integer> positive page limit."

	listPageSize ifNil: [listPageSize := 100].
	^listPageSize
]

{ #category : 'Protocol Operations' }
McpServer >> listPageSize: anInteger [
	"Set the maximum number of definitions in one list result.

	 Arguments:
		anInteger - <Integer> positive page limit.
	 Answers:
		<McpServer> the receiver."

	(anInteger isInteger and: [anInteger > 0])
		ifFalse: [self error: 'MCP list page size must be a positive integer'].
	listPageSize := anInteger.
	^self
]

{ #category : 'Accessing' }
McpServer >> name [
	"Answer a copy of the server implementation name.

	 Answers:
		<String>."

	^name copy
]

{ #category : 'Accessing' }
McpServer >> name: aString [
	"Set the server implementation name.

	 Arguments:
		aString - <String> nonempty name.
	 Answers:
		<McpServer> the receiver."

	(aString isString and: [aString isEmpty not])
		ifFalse: [self error: 'MCP server name must be a nonempty string'].
	name := aString copy.
	^self
]

{ #category : 'Serialization',
  #vaVisibility : 'private' }
McpServer >> normalizeCompletionResult: rawResult [
	"Normalize a completion handler result into a valid MCP CompleteResult dictionary.

	 Arguments:
		rawResult - <Collection of String> or <KeyedCollection>.
	 Answers:
		<KeyedCollection> CompleteResult."

	| completionDict values total hasMore |

	(rawResult isKindOf: KeyedCollection)
		ifTrue: [
			(rawResult includesKey: 'completion') ifTrue: [^self detachedProtocolValue: rawResult].
			values := rawResult at: 'values' ifAbsent: [#()].
			total := rawResult at: 'total' ifAbsent: [nil].
			hasMore := rawResult at: 'hasMore' ifAbsent: [nil]]
		ifFalse: [
			(rawResult isKindOf: Collection)
				ifTrue: [values := rawResult]
				ifFalse: [
					self error: 'Invalid completion handler result: expected a collection or object']].
	values := (values asArray collect: [:each | each asString])
		copyFrom: 1
		to: (values size min: 100).
	completionDict := EsOrderedDictionary new.
	completionDict at: 'values' put: values.
	total ifNotNil: [completionDict at: 'total' put: total].
	hasMore ifNotNil: [completionDict at: 'hasMore' put: hasMore].
	^EsOrderedDictionary with: 'completion' -> completionDict
]

{ #category : 'Serialization',
  #vaVisibility : 'private' }
McpServer >> normalizeToolResult: executionResult [
	"Normalize a raw tool value into an MCP CallToolResult or InputRequiredResult.

	 Existing CallToolResult and InputRequiredResult candidates are retained for later validation.
	 Other values become text content encoded as JSON when necessary.

	 Arguments:
		executionResult - <Object> raw tool execution value.
	 Answers:
		<KeyedCollection> CallToolResult or InputRequiredResult candidate."

	| response contentBlock jsonText resultType |

	(executionResult isKindOf: KeyedCollection)
		ifTrue: [
			(executionResult includesKey: 'content') ifTrue: [^executionResult].
			resultType := executionResult at: 'resultType' ifAbsent: [nil].
			(resultType = 'input_required' or: [resultType = 'inputRequired'])
				ifTrue: [^executionResult]].
	response := EsOrderedDictionary new.
	contentBlock :=
		EsOrderedDictionary new
			at: 'type' put: 'text';
			yourself.
	executionResult isString
		ifTrue: [contentBlock at: 'text' put: executionResult]
		ifFalse: [
			jsonText :=
				[
					String streamContents: [:stream |
						(McpJSONWriter on: stream) nextPut: executionResult]]
							on: Error
							do: [:serializationError |
								contentBlock
									at: 'text'
									put: 'Serialization error: ' , serializationError messageText.
								response
									at: 'content' put: (Array with: contentBlock);
									at: 'isError' put: true.
								^response].
			contentBlock at: 'text' put: jsonText].
	response
		at: 'content' put: (Array with: contentBlock);
		at: 'isError' put: false.
	^response
]

{ #category : 'Serialization',
  #vaVisibility : 'private' }
McpServer >> normalizeToolResult: executionResult for: aTool [
	"Normalize raw execution output using the tool result contract.

	 Arguments:
		executionResult - <Object> raw tool result.
		aTool - <McpTool> executed tool.
	 Answers:
		<KeyedCollection> MCP CallToolResult or InputRequiredResult candidate."

	| response content text resultType |

	(executionResult isKindOf: KeyedCollection)
		ifTrue: [
			resultType := executionResult at: 'resultType' ifAbsent: [nil].
			(resultType = 'input_required' or: [resultType = 'inputRequired'])
				ifTrue: [^executionResult].
			(executionResult includesKey: 'content')
				ifTrue: [^executionResult]].
	aTool outputSchema ifNil: [^self normalizeToolResult: executionResult].
	text := String streamContents: [:stream | (McpJSONWriter on: stream) nextPut: executionResult].
	content :=
		EsOrderedDictionary new
			at: 'type' put: 'text';
			at: 'text' put: text;
			yourself.
	response :=
		EsOrderedDictionary new
			at: 'content' put: (Array with: content);
			at: 'structuredContent' put: executionResult;
			at: 'isError' put: false;
			yourself.
	^response
]

{ #category : 'Protocol Operations' }
McpServer >> notifyPromptsChanged [
	"Broadcast a prompts list changed notification to all active subscribers.

	 Answers:
		<McpServer> the receiver."

	self subscriptionBus publishPromptsListChanged.
	^self
]

{ #category : 'Protocol Operations' }
McpServer >> notifyResourceUpdated: aResourceUri [
	"Broadcast a resource updated notification for a specific URI to all active subscribers.

	 Arguments:
		aResourceUri - <String> URI of the updated resource.
	 Answers:
		<McpServer> the receiver."

	self subscriptionBus publishResourceUpdated: aResourceUri.
	^self
]

{ #category : 'Protocol Operations' }
McpServer >> notifyResourcesChanged [
	"Broadcast a resources list changed notification to all active subscribers.

	 Answers:
		<McpServer> the receiver."

	self subscriptionBus publishResourcesListChanged.
	^self
]

{ #category : 'Protocol Operations' }
McpServer >> notifyToolsChanged [
	"Broadcast a tools list changed notification to all active subscribers.

	 Answers:
		<McpServer> the receiver."

	self subscriptionBus publishToolsListChanged.
	^self
]

{ #category : 'Protocol Operations' }
McpServer >> ping: parameters [
	"Execute ping without request context.

	 Arguments:
		parameters - <KeyedCollection> ping parameters.
	 Answers:
		<KeyedCollection> empty object on legacy, signals error on modern."

	^self ping: parameters context: nil
]

{ #category : 'Protocol Operations' }
McpServer >> ping: parameters context: requestContext [
	"Execute ping. In protocol version 2026-07-28, ping is removed from the specification.

	 Arguments:
		parameters - <KeyedCollection> ping parameters.
		requestContext - <McpServerRequestContext> or nil.
	 Answers:
		<KeyedCollection> empty object on legacy, signals error on modern."

	(self isModernContext: requestContext orParams: parameters)
		ifTrue: [
			McpJsonRpcError
				signalCode: McpJsonRpcMethodNotFoundCode
				message: 'Method not found: ping'
				data: nil].
	^EsOrderedDictionary new
]

{ #category : 'Accessing' }
McpServer >> promptRegistry [
	"Answer the prompt registry, lazily creating it for existing servers.

	 Answers:
		<McpPromptRegistry>."

	promptRegistry ifNil: [promptRegistry := McpPromptRegistry new].
	^promptRegistry
]

{ #category : 'Accessing' }
McpServer >> promptRegistry: aRegistry [
	"Set the prompt registry used by prompt operations.

	 Arguments:
		aRegistry - <McpPromptRegistry> registry.
	 Answers:
		<McpServer> the receiver."

	(aRegistry isKindOf: McpPromptRegistry)
		ifFalse: [self error: 'MCP server prompt registry has an invalid type'].
	promptRegistry := aRegistry.
	^self
]

{ #category : 'Protocol Operations' }
McpServer >> promptsGet: parameters [
	"Render a named prompt without transport request context.

	 Arguments:
		parameters - <KeyedCollection> prompt request parameters.
	 Answers:
		<KeyedCollection> MCP GetPromptResult."

	^self promptsGet: parameters context: nil
]

{ #category : 'Protocol Operations' }
McpServer >> promptsGet: parameters context: requestContext [
	"Validate and render a named prompt with request-scoped state.

	 Arguments:
		parameters - <KeyedCollection> prompt request parameters.
		requestContext - <McpServerRequestContext> or nil.
	 Answers:
		<KeyedCollection> MCP GetPromptResult or InputRequiredResult."

	| promptName argumentValues prompt result |

	promptName :=
		parameters
			at: 'name'
			ifAbsent: [
				McpJsonRpcError
					signalCode: McpJsonRpcInvalidParamsCode
					message: 'Invalid params: missing prompt name'
					data: nil].
	(promptName isString and: [promptName isEmpty not])
		ifFalse: [
			McpJsonRpcError
				signalCode: McpJsonRpcInvalidParamsCode
				message: 'Invalid params: prompt name must be nonempty'
				data: nil].
	argumentValues := parameters at: 'arguments' ifAbsent: [EsOrderedDictionary new].
	(argumentValues isKindOf: KeyedCollection)
		ifFalse: [
			McpJsonRpcError
				signalCode: McpJsonRpcInvalidParamsCode
				message: 'Invalid params: prompt arguments must be keyed'
				data: nil].
	requestContext ifNotNil: [
		parameters
			at: 'inputResponses'
			ifPresent: [:responses | requestContext inputResponses: responses].
		parameters
			at: 'requestState'
			ifPresent: [:rawState | | unsealed |
				unsealed :=
					(self isModernContext: requestContext orParams: parameters)
						ifTrue: [
							self requestStateSecurity
								unsealState: rawState
								expectedMethod: 'prompts/get'
								expectedTarget: promptName
								arguments: argumentValues
								expectedPrincipal: requestContext principal]
						ifFalse: [rawState].
				requestContext requestState: unsealed].
		parameters
			at: '_meta'
			ifPresent: [:meta |
				(meta isKindOf: KeyedCollection)
					ifTrue: [
						meta
							at: 'progressToken'
							ifPresent: [:token | requestContext progressToken: token]]].
		parameters
			at: 'progressToken'
			ifPresent: [:token |
				requestContext progressToken ifNil: [requestContext progressToken: token]]].
	prompt :=
		self promptRegistry
			promptNamed: promptName
			ifAbsent: [
				McpJsonRpcError
					signalCode: McpJsonRpcInvalidParamsCode
					message: 'Unknown prompt: ' , promptName
					data: nil].
	self validatePromptArguments: argumentValues for: prompt.
	result :=
		prompt
			renderWithArguments: (self detachedProtocolValue: argumentValues)
			context: requestContext.
	(self isModernContext: requestContext orParams: parameters)
		ifTrue: [| type |
			type :=
				(result isKindOf: KeyedCollection)
					ifTrue: [result at: 'resultType' ifAbsent: [nil]]
					ifFalse: [nil].
			(type = 'input_required' or: [type = 'inputRequired'])
				ifTrue: [| rawState |
					result at: 'resultType' put: 'input_required'.
					rawState := result at: 'requestState' ifAbsent: [nil].
					rawState ifNotNil: [
						result
							at: 'requestState'
							put: (
								self requestStateSecurity
									sealState: rawState
									method: 'prompts/get'
									target: promptName
									arguments: argumentValues
									principal: (requestContext ifNotNil: [:ctx | ctx principal]))]]
				ifFalse: [
					(result isKindOf: KeyedCollection)
						ifTrue: [result at: 'resultType' put: 'complete']]].
	self validatePromptResult: result.
	^self detachedProtocolValue: result
]

{ #category : 'Protocol Operations' }
McpServer >> promptsList: parameters [
	"Answer one stable, cursor-selected page of prompt definitions.

	 Arguments:
		parameters - <KeyedCollection> optional cursor parameters.
	 Answers:
		<KeyedCollection> MCP ListPromptsResult."

	^self promptsList: parameters context: nil
]

{ #category : 'Protocol Operations' }
McpServer >> promptsList: parameters context: requestContext [
	"Answer one stable, cursor-selected page of prompt definitions with optional modern metadata.

	 Arguments:
		parameters - <KeyedCollection> optional cursor parameters.
		requestContext - <McpServerRequestContext> or nil.
	 Answers:
		<KeyedCollection> MCP ListPromptsResult."

	| cursor prompts definitions offset limit endIndex page result |

	cursor := parameters at: 'cursor' ifAbsent: [nil].
	prompts :=
		self promptRegistry prompts values
			asSortedCollection: [:left :right | left name <= right name].
	definitions := (prompts collect: [:prompt | prompt asMcpDefinition]) asArray.
	offset := self cursorOffsetFrom: cursor totalSize: definitions size.
	limit := self listPageSize.
	endIndex := (offset + limit) min: definitions size.
	page := offset = endIndex ifTrue: [#()] ifFalse: [definitions copyFrom: offset + 1 to: endIndex].
	result := EsOrderedDictionary with: 'prompts' -> page.
	endIndex < definitions size ifTrue: [result at: 'nextCursor' put: endIndex printString].
	(self isModernContext: requestContext orParams: parameters)
		ifTrue: [
			result
				at: 'resultType' put: 'complete';
				at: 'cacheScope' put: 'public';
				at: 'ttlMs' put: 0].
	^result
]

{ #category : 'Accessing' }
McpServer >> requestStateSecurity [
	"Answer the security boundary used to seal and verify requestState tokens.

	 Answers:
		<McpRequestStateSecurity>."

	requestStateSecurity ifNil: [requestStateSecurity := McpRequestStateSecurity new].
	^requestStateSecurity
]

{ #category : 'Accessing' }
McpServer >> requestStateSecurity: aSecurity [
	"Set the security boundary used to seal and verify requestState tokens.

	 Arguments:
		aSecurity - <McpRequestStateSecurity>.
	 Answers:
		<McpServer> the receiver."

	(aSecurity isKindOf: McpRequestStateSecurity)
		ifFalse: [self error: 'Request state security must be an McpRequestStateSecurity'].
	requestStateSecurity := aSecurity.
	^self
]

{ #category : 'Validation' }
McpServer >> requireClientExtension: anIdentifier context: requestContext [
	"Assert that the connected client declared support for the specified extension,
	 raising JSON-RPC error -32021 if not advertised.

	 Arguments:
		anIdentifier - <String> required extension identifier.
		requestContext - <McpServerRequestContext> or nil.
	 Answers:
		<McpServer> the receiver."

	| clientCaps extMap errorData reqCaps |

	clientCaps := requestContext ifNotNil: [:ctx | ctx clientCapabilities].
	extMap := clientCaps ifNotNil: [clientCaps at: 'extensions' ifAbsent: [nil]].
	(extMap notNil and: [extMap includesKey: anIdentifier]) ifTrue: [^self].

	reqCaps :=
		EsOrderedDictionary
			with: 'extensions' -> (EsOrderedDictionary with: anIdentifier -> EsOrderedDictionary new).
	errorData := EsOrderedDictionary with: 'requiredCapabilities' -> reqCaps.
	McpJsonRpcError
		signalCode: -32021
		message: 'Client did not declare required extension: ' , anIdentifier
		data: errorData
]

{ #category : 'Accessing' }
McpServer >> resourceRegistry [
	"Answer the resource registry, lazily creating it for existing servers.

	 Answers:
		<McpResourceRegistry>."

	resourceRegistry ifNil: [resourceRegistry := McpResourceRegistry new].
	^resourceRegistry
]

{ #category : 'Accessing' }
McpServer >> resourceRegistry: aRegistry [
	"Set the resource registry used by concrete resource operations.

	 Arguments:
		aRegistry - <McpResourceRegistry> registry.
	 Answers:
		<McpServer> the receiver."

	(aRegistry isKindOf: McpResourceRegistry)
		ifFalse: [self error: 'MCP server resource registry has an invalid type'].
	resourceRegistry := aRegistry.
	^self
]

{ #category : 'Accessing' }
McpServer >> resourceTemplateRegistry [
	"Answer the template registry, lazily creating it for existing servers.

	 Answers:
		<McpResourceTemplateRegistry>."

	resourceTemplateRegistry ifNil: [resourceTemplateRegistry := McpResourceTemplateRegistry new].
	^resourceTemplateRegistry
]

{ #category : 'Accessing' }
McpServer >> resourceTemplateRegistry: aRegistry [
	"Set the registry used by resource-template operations.

	 Arguments:
		aRegistry - <McpResourceTemplateRegistry> registry.
	 Answers:
		<McpServer> the receiver."

	(aRegistry isKindOf: McpResourceTemplateRegistry)
		ifFalse: [self error: 'MCP resource-template registry has an invalid type'].
	resourceTemplateRegistry := aRegistry.
	^self
]

{ #category : 'Protocol Operations' }
McpServer >> resourceTemplatesList: parameters [
	"Answer one cursor-selected page of resource-template definitions.

	 Arguments:
		parameters - <KeyedCollection> optional cursor parameters.
	 Answers:
		<KeyedCollection> MCP ListResourceTemplatesResult."

	^self resourceTemplatesList: parameters context: nil
]

{ #category : 'Protocol Operations' }
McpServer >> resourceTemplatesList: parameters context: requestContext [
	"Answer one cursor-selected page of resource-template definitions with optional modern metadata.

	 Arguments:
		parameters - <KeyedCollection> optional cursor parameters.
		requestContext - <McpServerRequestContext> or nil.
	 Answers:
		<KeyedCollection> MCP ListResourceTemplatesResult."

	| cursor templates definitions offset limit endIndex page result |

	cursor := parameters at: 'cursor' ifAbsent: [nil].
	templates :=
		self resourceTemplateRegistry templates values
			asSortedCollection: [:left :right | left uriTemplate <= right uriTemplate].
	definitions := (templates collect: [:template | template asMcpDefinition]) asArray.
	offset := self cursorOffsetFrom: cursor totalSize: definitions size.
	limit := self listPageSize.
	endIndex := (offset + limit) min: definitions size.
	page := offset = endIndex ifTrue: [#()] ifFalse: [definitions copyFrom: offset + 1 to: endIndex].
	result := EsOrderedDictionary with: 'resourceTemplates' -> page.
	endIndex < definitions size ifTrue: [result at: 'nextCursor' put: endIndex printString].
	(self isModernContext: requestContext orParams: parameters)
		ifTrue: [
			result
				at: 'resultType' put: 'complete';
				at: 'cacheScope' put: 'public';
				at: 'ttlMs' put: 0].
	^result
]

{ #category : 'Protocol Operations' }
McpServer >> resourcesList: parameters [
	"Answer one stable, cursor-selected page of resource definitions.

	 Arguments:
		parameters - <KeyedCollection> optional cursor parameters.
	 Answers:
		<KeyedCollection> MCP ListResourcesResult."

	^self resourcesList: parameters context: nil
]

{ #category : 'Protocol Operations' }
McpServer >> resourcesList: parameters context: requestContext [
	"Answer one stable, cursor-selected page of resource definitions with optional modern metadata.

	 Arguments:
		parameters - <KeyedCollection> optional cursor parameters.
		requestContext - <McpServerRequestContext> or nil.
	 Answers:
		<KeyedCollection> MCP ListResourcesResult."

	| cursor resources definitions offset limit endIndex page result |

	cursor := parameters at: 'cursor' ifAbsent: [nil].
	resources :=
		self resourceRegistry resources values
			asSortedCollection: [:left :right | left uri <= right uri].
	definitions := (resources collect: [:resource | resource asMcpDefinition]) asArray.
	offset := self cursorOffsetFrom: cursor totalSize: definitions size.
	limit := self listPageSize.
	endIndex := (offset + limit) min: definitions size.
	page := offset = endIndex ifTrue: [#()] ifFalse: [definitions copyFrom: offset + 1 to: endIndex].
	result := EsOrderedDictionary with: 'resources' -> page.
	endIndex < definitions size ifTrue: [result at: 'nextCursor' put: endIndex printString].
	(self isModernContext: requestContext orParams: parameters)
		ifTrue: [
			result
				at: 'resultType' put: 'complete';
				at: 'cacheScope' put: 'public';
				at: 'ttlMs' put: 0].
	^result
]

{ #category : 'Protocol Operations' }
McpServer >> resourcesRead: parameters [
	"Read a resource without transport request context.

	 Arguments:
		parameters - <KeyedCollection> resource request parameters.
	 Answers:
		<KeyedCollection> MCP ReadResourceResult."

	^self resourcesRead: parameters context: nil
]

{ #category : 'Protocol Operations' }
McpServer >> resourcesRead: parameters context: requestContext [
	"Read a concrete or template-backed resource with request state and cache hints.

	 Arguments:
		parameters - <KeyedCollection> resource request parameters.
		requestContext - <McpServerRequestContext> or nil.
	 Answers:
		<KeyedCollection> MCP ReadResourceResult or InputRequiredResult."

	| resourceUri resource result |

	resourceUri :=
		parameters
			at: 'uri'
			ifAbsent: [
				McpJsonRpcError
					signalCode: McpJsonRpcInvalidParamsCode
					message: 'Invalid params: missing resource URI'
					data: nil].
	(self isValidAbsoluteResourceUri: resourceUri)
		ifFalse: [
			McpJsonRpcError
				signalCode: McpJsonRpcInvalidParamsCode
				message: 'Invalid params: malformed resource URI'
				data: nil].
	requestContext ifNotNil: [
		parameters
			at: 'inputResponses'
			ifPresent: [:responses | requestContext inputResponses: responses].
		parameters
			at: 'requestState'
			ifPresent: [:rawState | | unsealed |
				unsealed :=
					(self isModernContext: requestContext orParams: parameters)
						ifTrue: [
							self requestStateSecurity
								unsealState: rawState
								expectedMethod: 'resources/read'
								expectedTarget: resourceUri
								arguments: EsOrderedDictionary new
								expectedPrincipal: requestContext principal]
						ifFalse: [rawState].
				requestContext requestState: unsealed].
		parameters
			at: '_meta'
			ifPresent: [:meta |
				(meta isKindOf: KeyedCollection)
					ifTrue: [
						meta
							at: 'progressToken'
							ifPresent: [:token | requestContext progressToken: token]]].
		parameters
			at: 'progressToken'
			ifPresent: [:token |
				requestContext progressToken ifNil: [requestContext progressToken: token]]].
	resource := self resourceRegistry resourceAt: resourceUri ifAbsent: [nil].
	resource
		ifNotNil: [result := resource readWithContext: requestContext]
		ifNil: [| template |
			template := self resourceTemplateRegistry
				templateMatchingUri: resourceUri
				ifAbsent: [nil].
			template ifNil: [| errorData notFoundCode |
				errorData := EsOrderedDictionary with: 'uri' -> resourceUri.
				notFoundCode :=
					(self isModernContext: requestContext orParams: parameters)
						ifTrue: [McpJsonRpcInvalidParamsCode]
						ifFalse: [McpResourceNotFoundErrorCode].
				McpJsonRpcError
					signalCode: notFoundCode
					message: 'Resource not found'
					data: errorData].
			result := template readUri: resourceUri context: requestContext].
	(self isModernContext: requestContext orParams: parameters)
		ifTrue: [| type |
			type :=
				(result isKindOf: KeyedCollection)
					ifTrue: [result at: 'resultType' ifAbsent: [nil]]
					ifFalse: [nil].
			(type = 'input_required' or: [type = 'inputRequired'])
				ifTrue: [| rawState |
					result at: 'resultType' put: 'input_required'.
					rawState := result at: 'requestState' ifAbsent: [nil].
					rawState ifNotNil: [
						result
							at: 'requestState'
							put: (
								self requestStateSecurity
									sealState: rawState
									method: 'resources/read'
									target: resourceUri
									arguments: EsOrderedDictionary new
									principal: (requestContext ifNotNil: [:ctx | ctx principal]))]]
				ifFalse: [
					(result isKindOf: KeyedCollection)
						ifTrue: [| ttl scope |
							ttl :=
								resource
									ifNotNil: [:r |
										r meta ifNotNil: [:m | m at: 'ttlMs' ifAbsent: [nil]]]
									ifNil: [nil].
							scope :=
								resource
									ifNotNil: [:r |
										r meta ifNotNil: [:m | m at: 'cacheScope' ifAbsent: [nil]]]
									ifNil: [nil].
							result
								at: 'resultType' put: 'complete';
								at: 'cacheScope' put: (scope ifNil: ['private']);
								at: 'ttlMs' put: (ttl ifNil: [0])]]].
	self validateResourceReadResult: result.
	^self detachedProtocolValue: result
]

{ #category : 'Protocol Operations' }
McpServer >> serverDiscover: parameters [
	"Answer server discovery result without transport request context.

	 Arguments:
		parameters - <KeyedCollection> discovery parameters, or nil.
	 Answers:
		<KeyedCollection> MCP DiscoverResult."

	^self serverDiscover: parameters context: nil
]

{ #category : 'Protocol Operations' }
McpServer >> serverDiscover: parameters context: requestContext [
	"Validate discovery request and answer server discovery result.

	 Arguments:
		parameters - <KeyedCollection> discovery parameters, or nil.
		requestContext - <McpServerRequestContext> or nil.
	 Answers:
		<KeyedCollection> MCP DiscoverResult."

	| serverMetadata meta result |

	serverMetadata :=
		EsOrderedDictionary new
			at: 'name' put: self name;
			at: 'version' put: self version;
			yourself.
	meta :=
		EsOrderedDictionary new
			at: 'io.modelcontextprotocol/serverInfo' put: serverMetadata;
			yourself.
	result :=
		EsOrderedDictionary new
			at: 'capabilities' put: self capabilities;
			at: 'supportedVersions' put: self supportedProtocolVersions;
			at: 'resultType' put: 'complete';
			at: 'cacheScope' put: 'public';
			at: 'ttlMs' put: 0;
			at: '_meta' put: meta;
			yourself.
	^self detachedProtocolValue: result
]

{ #category : 'Accessing' }
McpServer >> subscriptionBus [
	"Answer the subscription bus for change notifications.

	 Answers:
		<McpSubscriptionBus>."

	subscriptionBus ifNil: [subscriptionBus := McpSubscriptionBus new].
	^subscriptionBus
]

{ #category : 'Accessing' }
McpServer >> subscriptionBus: aBus [
	"Set the subscription bus.

	 Arguments:
		aBus - <McpSubscriptionBus>.
	 Answers:
		<McpServer> the receiver."

	(aBus isKindOf: McpSubscriptionBus)
		ifFalse: [self error: 'Subscription bus must be an McpSubscriptionBus'].
	subscriptionBus := aBus.
	^self
]

{ #category : 'Protocol Operations' }
McpServer >> subscriptionsListen: parameters [
	"Establish or acknowledge a subscriptions/listen request without request context.

	 Arguments:
		parameters - <KeyedCollection> subscription filters.
	 Answers:
		<KeyedCollection> subscription acknowledgment metadata."

	^self subscriptionsListen: parameters context: nil
]

{ #category : 'Protocol Operations' }
McpServer >> subscriptionsListen: parameters context: requestContext [
	"Establish or acknowledge a subscriptions/listen request.

	 Arguments:
		parameters - <KeyedCollection> subscription filters.
		requestContext - <McpServerRequestContext> or nil.
	 Answers:
		<KeyedCollection> subscription acknowledgment metadata."

	| requestedNotifications acknowledged result hasTools hasPrompts hasResources |

	requestedNotifications :=
		(parameters isKindOf: KeyedCollection)
			ifTrue: [parameters at: 'notifications' ifAbsent: [EsOrderedDictionary new]]
			ifFalse: [EsOrderedDictionary new].
	acknowledged := EsOrderedDictionary new.

	hasTools :=
		(requestedNotifications at: 'toolsListChanged' ifAbsent: [false]) == true
			or: [(requestedNotifications at: 'tools' ifAbsent: [false]) == true].
	hasTools
		ifTrue: [
			acknowledged
				at: 'toolsListChanged' put: true;
				at: 'tools' put: true].

	hasPrompts :=
		(requestedNotifications at: 'promptsListChanged' ifAbsent: [false]) == true
			or: [(requestedNotifications at: 'prompts' ifAbsent: [false]) == true].
	hasPrompts
		ifTrue: [
			acknowledged
				at: 'promptsListChanged' put: true;
				at: 'prompts' put: true].

	hasResources :=
		(requestedNotifications at: 'resourcesListChanged' ifAbsent: [false]) == true
			or: [(requestedNotifications at: 'resources' ifAbsent: [false]) == true].
	hasResources
		ifTrue: [
			acknowledged
				at: 'resourcesListChanged' put: true;
				at: 'resources' put: true].

	(requestedNotifications includesKey: 'resourceSubscriptions')
		ifTrue: [
			acknowledged
				at: 'resourceSubscriptions'
				put: (requestedNotifications at: 'resourceSubscriptions') copy].
	result :=
		EsOrderedDictionary new
			at: 'notifications' put: acknowledged;
			at: 'resultType' put: 'complete';
			yourself.
	^self detachedProtocolValue: result
]

{ #category : 'Accessing' }
McpServer >> supportedHandshakeProtocolVersions [
	"Answer protocol versions reachable via the initialize handshake in preference order.

	 Answers:
		<Array> of <String>."

	^McpProtocolVersion handshakeProtocolVersions
]

{ #category : 'Accessing' }
McpServer >> supportedProtocolVersions [
	"Answer protocol versions supported by this server in preference order.

	 Answers:
		<Array> of <String>."

	^McpProtocolVersion supportedProtocolVersions
]

{ #category : 'Accessing' }
McpServer >> toolRegistry [
	"Answer the tool registry owned by the server.

	 Answers:
		<McpToolRegistry>."

	^toolRegistry
]

{ #category : 'Accessing' }
McpServer >> toolRegistry: aRegistry [
	"Set the tool registry used by tool operations.

	 Arguments:
		aRegistry - <McpToolRegistry> registry.
	 Answers:
		<McpServer> the receiver."

	(aRegistry isKindOf: McpToolRegistry)
		ifFalse: [self error: 'MCP server tool registry has an invalid type'].
	toolRegistry := aRegistry.
	^self
]

{ #category : 'Protocol Operations' }
McpServer >> toolsCall: parameters [
	"Execute a tool call without transport request context.

	 Arguments:
		parameters - <KeyedCollection> tool-call parameters.
	 Answers:
		<KeyedCollection> MCP CallToolResult."

	^self toolsCall: parameters context: nil
]

{ #category : 'Protocol Operations' }
McpServer >> toolsCall: parameters context: requestContext [
	"Validate, execute, normalize, and verify one tool call.

	 Malformed calls and unknown tools signal protocol errors. Argument-schema
	 mismatches and execution failures become actionable tool-error results.

	 Arguments:
		parameters - <KeyedCollection> tool-call parameters.
		requestContext - <McpServerRequestContext> or nil.
	 Answers:
		<KeyedCollection> validated MCP CallToolResult or InputRequiredResult."

	| toolName arguments tool normalized validationErrorContent validationErrorResult |

	toolName :=
		parameters
			at: 'name'
			ifAbsent: [
				McpJsonRpcError
					signalCode: McpJsonRpcInvalidParamsCode
					message: 'Invalid params: missing tool name'
					data: nil].
	(toolName isString and: [toolName isEmpty not])
		ifFalse: [
			McpJsonRpcError
				signalCode: McpJsonRpcInvalidParamsCode
				message: 'Invalid params: tool name must be nonempty'
				data: nil].
	arguments := parameters at: 'arguments' ifAbsent: [EsOrderedDictionary new].
	(arguments isKindOf: KeyedCollection)
		ifFalse: [
			McpJsonRpcError
				signalCode: McpJsonRpcInvalidParamsCode
				message: 'Invalid params: arguments must be keyed'
				data: nil].
	requestContext ifNotNil: [
		parameters
			at: 'inputResponses'
			ifPresent: [:responses | requestContext inputResponses: responses].
		parameters
			at: 'requestState'
			ifPresent: [:rawState | | unsealed |
				unsealed :=
					(self isModernContext: requestContext orParams: parameters)
						ifTrue: [
							self requestStateSecurity
								unsealState: rawState
								expectedMethod: 'tools/call'
								expectedTarget: toolName
								arguments: arguments
								expectedPrincipal: requestContext principal]
						ifFalse: [rawState].
				requestContext requestState: unsealed].
		parameters
			at: '_meta'
			ifPresent: [:meta |
				(meta isKindOf: KeyedCollection)
					ifTrue: [
						meta
							at: 'progressToken'
							ifPresent: [:token | requestContext progressToken: token].
						meta
							at: 'io.modelcontextprotocol/logLevel'
							ifPresent: [:lvl | requestContext logLevel: lvl]]].
		parameters
			at: 'progressToken'
			ifPresent: [:token |
				requestContext progressToken ifNil: [requestContext progressToken: token]]].
	tool :=
		self toolRegistry
			toolNamed: toolName
			ifAbsent: [
				McpJsonRpcError
					signalCode: McpJsonRpcInvalidParamsCode
					message: 'Unknown tool: ' , toolName
					data: nil].
	[self validateArguments: arguments againstSchema: tool inputSchema]
		on: McpJsonRpcError
		do: [:validationError |
			validationErrorContent :=
				EsOrderedDictionary new
					at: 'type' put: 'text';
					at: 'text' put: validationError messageText;
					yourself.
			validationErrorResult :=
				EsOrderedDictionary new
					at: 'content' put: (Array with: validationErrorContent);
					at: 'isError' put: true;
					yourself.
			(self isModernContext: requestContext orParams: parameters)
				ifTrue: [validationErrorResult at: 'resultType' put: 'complete'].
			^self detachedProtocolValue: validationErrorResult].
	normalized :=
		[
			self
				normalizeToolResult: (
					tool
						executeWithArguments: (self detachedProtocolValue: arguments)
						context: requestContext)
				for: tool]
					on: Error
					do: [:executionError | | errorContent errorResult |
						errorContent :=
							EsOrderedDictionary new
								at: 'type' put: 'text';
								at: 'text' put: executionError messageText;
								yourself.
						errorResult :=
							EsOrderedDictionary new
								at: 'content' put: (Array with: errorContent);
								at: 'isError' put: true;
								yourself.
						(self isModernContext: requestContext orParams: parameters)
							ifTrue: [errorResult at: 'resultType' put: 'complete'].
						executionError return: errorResult].
	(self isModernContext: requestContext orParams: parameters)
		ifTrue: [| type |
			type := normalized at: 'resultType' ifAbsent: [nil].
			(type = 'input_required' or: [type = 'inputRequired'])
				ifTrue: [| rawState |
					normalized at: 'resultType' put: 'input_required'.
					rawState := normalized at: 'requestState' ifAbsent: [nil].
					rawState ifNotNil: [
						normalized
							at: 'requestState'
							put: (
								self requestStateSecurity
									sealState: rawState
									method: 'tools/call'
									target: toolName
									arguments: arguments
									principal: (requestContext ifNotNil: [:ctx | ctx principal]))]]
				ifFalse: [normalized at: 'resultType' put: 'complete']].
	self validateToolResult: normalized for: tool.
	^self detachedProtocolValue: normalized
]

{ #category : 'Protocol Operations' }
McpServer >> toolsList: parameters [
	"Answer one stable, cursor-selected page of tool definitions.

	 Arguments:
		parameters - <KeyedCollection> optional cursor parameters.
	 Answers:
		<KeyedCollection> MCP ListToolsResult."

	^self toolsList: parameters context: nil
]

{ #category : 'Protocol Operations' }
McpServer >> toolsList: parameters context: requestContext [
	"Answer one stable, cursor-selected page of tool definitions with optional modern metadata.

	 Arguments:
		parameters - <KeyedCollection> optional cursor parameters.
		requestContext - <McpServerRequestContext> or nil.
	 Answers:
		<KeyedCollection> MCP ListToolsResult."

	| cursor tools definitions offset limit endIndex page result |

	cursor := parameters at: 'cursor' ifAbsent: [nil].
	tools :=
		self toolRegistry tools values asSortedCollection: [:left :right | left name <= right name].
	definitions := (tools collect: [:tool | tool asMcpDefinition]) asArray.
	offset := self cursorOffsetFrom: cursor totalSize: definitions size.
	limit := self listPageSize.
	endIndex := (offset + limit) min: definitions size.
	page := offset = endIndex ifTrue: [#()] ifFalse: [definitions copyFrom: offset + 1 to: endIndex].
	result := EsOrderedDictionary with: 'tools' -> page.
	endIndex < definitions size ifTrue: [result at: 'nextCursor' put: endIndex printString].
	(self isModernContext: requestContext orParams: parameters)
		ifTrue: [
			result
				at: 'resultType' put: 'complete';
				at: 'cacheScope' put: 'public';
				at: 'ttlMs' put: 0].
	^result
]

{ #category : 'Validation',
  #vaVisibility : 'private' }
McpServer >> validateArguments: value againstSchema: schema [
	"Validate arguments with the native document-local schema validator.
	Arguments:
		value - <Object> JSON value.
		schema - <KeyedCollection | nil> schema document.
	Answers:
		<McpServer> the receiver."
	McpSchemaValidator new validate: value against: schema

]

{ #category : 'Validation',
  #vaVisibility : 'private' }
McpServer >> validatePromptArguments: argumentValues for: aPrompt [
	"Validate supplied strings against a prompt argument declaration.

	 Arguments:
		argumentValues - <KeyedCollection> supplied arguments.
		aPrompt - <McpPrompt> selected prompt.
	 Answers:
		<McpServer> the receiver."

	| definitions declaredNames |

	definitions := aPrompt arguments ifNil: [#()].
	declaredNames := Set new.
	definitions do: [:definition | | argumentName required |
		argumentName := definition at: 'name'.
		declaredNames add: argumentName.
		required := definition at: 'required' ifAbsent: [false].
		(required and: [(argumentValues includesKey: argumentName) not])
			ifTrue: [
				McpJsonRpcError
					signalCode: McpJsonRpcInvalidParamsCode
					message: 'Missing required prompt argument: ' , argumentName
					data: nil]].
	argumentValues keysAndValuesDo: [:key :value |
		(key isString and: [value isString])
			ifFalse: [
				McpJsonRpcError
					signalCode: McpJsonRpcInvalidParamsCode
					message: 'Prompt arguments must map strings to strings'
					data: nil].
		(declaredNames includes: key)
			ifFalse: [
				McpJsonRpcError
					signalCode: McpJsonRpcInvalidParamsCode
					message: 'Unknown prompt argument: ' , key
					data: nil]].
	^self
]

{ #category : 'Validation',
  #vaVisibility : 'private' }
McpServer >> validatePromptContent: content [
	"Validate one MCP prompt content block.

	 Arguments:
		content - <Object> content candidate.
	 Answers:
		<McpServer> the receiver."

	| type resource hasText hasBlob value |

	(content isKindOf: KeyedCollection)
		ifFalse: [self error: 'MCP prompt message content must be keyed'].
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
				value isString
					ifFalse: [self error: 'MCP media content requires string data and MIME type']].
			^self].
	type = 'resource'
		ifTrue: [
			resource := content at: 'resource' ifAbsent: [nil].
			(resource isKindOf: KeyedCollection)
				ifFalse: [self error: 'MCP embedded resource must be keyed'].
			value := resource at: 'uri' ifAbsent: [nil].
			(value isString and: [value isEmpty not])
				ifFalse: [self error: 'MCP embedded resource requires a URI'].
			hasText := resource includesKey: 'text'.
			hasBlob := resource includesKey: 'blob'.
			hasText = hasBlob
				ifTrue: [self error: 'MCP embedded resource requires either text or blob'].
			value := resource at: (hasText ifTrue: ['text'] ifFalse: ['blob']).
			value isString ifFalse: [self error: 'MCP embedded resource content must be a string'].
			^self].
	type = 'resource_link'
		ifTrue: [
			#('uri' 'name') do: [:field |
				value := content at: field ifAbsent: [nil].
				(value isString and: [value isEmpty not])
					ifFalse: [self error: 'MCP resource link requires URI and name']].
			^self].
	self error: 'MCP prompt message has an unsupported content type'
]

{ #category : 'Validation',
  #vaVisibility : 'private' }
McpServer >> validatePromptMessage: message [
	"Validate one MCP prompt message.

	 Arguments:
		message - <Object> message candidate.
	 Answers:
		<McpServer> the receiver."

	| role content |

	(message isKindOf: KeyedCollection) ifFalse: [self error: 'MCP prompt messages must be keyed'].
	role := message at: 'role' ifAbsent: [nil].
	(#('user' 'assistant') includes: role)
		ifFalse: [self error: 'MCP prompt message role is invalid'].
	content := message at: 'content' ifAbsent: [nil].
	self validatePromptContent: content.
	^self
]

{ #category : 'Validation',
  #vaVisibility : 'private' }
McpServer >> validatePromptResult: result [
	"Validate an MCP GetPromptResult or InputRequiredResult returned by a renderer.

	 Arguments:
		result - <Object> renderer result.
	 Answers:
		<McpServer> the receiver."

	| description messages resultType requests state |

	(result isKindOf: KeyedCollection)
		ifFalse: [self error: 'MCP prompt renderer must answer a keyed result'].
	resultType := result at: 'resultType' ifAbsent: [nil].
	(resultType = 'input_required' or: [resultType = 'inputRequired'])
		ifTrue: [
			requests := result at: 'inputRequests' ifAbsent: [nil].
			state := result at: 'requestState' ifAbsent: [nil].
			(requests isNil and: [state isNil])
				ifTrue: [
					self error: 'MCP InputRequiredResult must have inputRequests or requestState'].
			(requests notNil and: [(requests isKindOf: KeyedCollection) not])
				ifTrue: [self error: 'MCP inputRequests must be a keyed collection'].
			(state notNil and: [state isString not])
				ifTrue: [self error: 'MCP requestState must be a string'].
			^self].
	description := result at: 'description' ifAbsent: [nil].
	(description isNil or: [description isString])
		ifFalse: [self error: 'MCP prompt result description must be a string'].
	messages := result at: 'messages' ifAbsent: [nil].
	((messages isKindOf: SequenceableCollection)
		and: [messages isString not and: [(messages isKindOf: KeyedCollection) not]])
			ifFalse: [self error: 'MCP prompt result messages must be an array'].
	messages do: [:message | self validatePromptMessage: message].
	^self
]

{ #category : 'Validation',
  #vaVisibility : 'private' }
McpServer >> validateResourceContents: content [
	"Validate one text or blob resource-contents object.

	 Arguments:
		content - <Object> resource contents candidate.
	 Answers:
		<McpServer> the receiver."

	| uri mimeType hasText hasBlob value |

	(content isKindOf: KeyedCollection) ifFalse: [self error: 'MCP resource contents must be keyed'].
	uri := content at: 'uri' ifAbsent: [nil].
	(self isValidAbsoluteResourceUri: uri)
		ifFalse: [self error: 'MCP resource contents requires a valid URI'].
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
McpServer >> validateResourceReadResult: result [
	"Validate an MCP ReadResourceResult or InputRequiredResult returned by a reader.

	 Arguments:
		result - <Object> reader result.
	 Answers:
		<McpServer> the receiver."

	| contents resultType requests state |

	(result isKindOf: KeyedCollection)
		ifFalse: [self error: 'MCP resource reader must answer a keyed result'].
	resultType := result at: 'resultType' ifAbsent: [nil].
	(resultType = 'input_required' or: [resultType = 'inputRequired'])
		ifTrue: [
			requests := result at: 'inputRequests' ifAbsent: [nil].
			state := result at: 'requestState' ifAbsent: [nil].
			(requests isNil and: [state isNil])
				ifTrue: [
					self error: 'MCP InputRequiredResult must have inputRequests or requestState'].
			(requests notNil and: [(requests isKindOf: KeyedCollection) not])
				ifTrue: [self error: 'MCP inputRequests must be a keyed collection'].
			(state notNil and: [state isString not])
				ifTrue: [self error: 'MCP requestState must be a string'].
			^self].
	contents := result at: 'contents' ifAbsent: [nil].
	((contents isKindOf: SequenceableCollection)
		and: [contents isString not and: [(contents isKindOf: KeyedCollection) not]])
			ifFalse: [self error: 'MCP resource result contents must be an array'].
	contents do: [:content | self validateResourceContents: content].
	^self
]

{ #category : 'Validation',
  #vaVisibility : 'private' }
McpServer >> validateToolResult: result for: aTool [
	"Validate CallToolResult or InputRequiredResult shape and optional structured output.

	 Arguments:
		result - <Object> normalized result candidate.
		aTool - <McpTool> executed tool.
	 Answers:
		<McpServer> the receiver."

	| content isError structured schema requests state resultType |

	(result isKindOf: KeyedCollection) ifFalse: [self error: 'MCP tool result must be keyed'].
	resultType := result at: 'resultType' ifAbsent: [nil].
	(resultType = 'input_required' or: [resultType = 'inputRequired'])
		ifTrue: [
			requests := result at: 'inputRequests' ifAbsent: [nil].
			state := result at: 'requestState' ifAbsent: [nil].
			(requests isNil and: [state isNil])
				ifTrue: [
					self error: 'MCP InputRequiredResult must have inputRequests or requestState'].
			(requests notNil and: [(requests isKindOf: KeyedCollection) not])
				ifTrue: [self error: 'MCP inputRequests must be a keyed collection'].
			(state notNil and: [state isString not])
				ifTrue: [self error: 'MCP requestState must be a string'].
			^self].
	content := result at: 'content' ifAbsent: [nil].
	((content isKindOf: SequenceableCollection)
		and: [content isString not and: [(content isKindOf: KeyedCollection) not]])
			ifFalse: [self error: 'MCP tool result content must be an array'].
	content do: [:item | self validatePromptContent: item].
	isError := result at: 'isError' ifAbsent: [false].
	isError isBoolean ifFalse: [self error: 'MCP tool result isError must be boolean'].
	structured := result at: 'structuredContent' ifAbsent: [nil].
	schema := aTool outputSchema.
	(schema notNil and: [isError not])
		ifTrue: [
			structured ifNil: [self error: 'MCP tool with outputSchema requires structuredContent'].
			[self validateArguments: structured againstSchema: schema]
				on: McpJsonRpcError
				do: [:schemaError | self error: 'MCP structuredContent violates the outputSchema']].
	^self
]

{ #category : 'Accessing' }
McpServer >> version [
	"Answer a copy of the server implementation version.

	 Answers:
		<String>."

	^version copy
]

{ #category : 'Accessing' }
McpServer >> version: aString [
	"Set the server implementation version.

	 Arguments:
		aString - <String> nonempty version.
	 Answers:
		<McpServer> the receiver."

	(aString isString and: [aString isEmpty not])
		ifFalse: [self error: 'MCP server version must be a nonempty string'].
	version := aString copy.
	^self
]
