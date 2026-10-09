"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# McpJsonRpcDispatcher

`McpJsonRpcDispatcher` dispatches validated JSON-RPC 2.0 messages to registered
MCP handlers across both handshake and modern protocol eras.

## Responsibilities

- Dispatch standard MCP methods: `server/discover`, `initialize`,
  `notifications/initialized`, `ping`, `tools/*`, `prompts/*`, `resources/*`,
  and `subscriptions/listen`.
- Detect the operating protocol era via `isModernContext:orParams:`.
- Automatically stamp modern response envelopes with
  `_meta['io.modelcontextprotocol/serverInfo']`.
- Correlate request identifiers, validate parameter objects, and format
  canonical error envelopes.

## Lifecycle and boundaries

The server owns handler registration; dispatch may be concurrent across
multiple threads and requests.
"
Class {
	#name : 'McpJsonRpcDispatcher',
	#superclass : 'Object',
	#instVars : [
		'server',
		'methodMap'
	],
	#pools : [
		'McpJsonRpcConstants'
	],
	#category : 'McpProtocol'
}

{ #category : 'Instance Creation' }
McpJsonRpcDispatcher class >> new [
	"Answer a new initialized JSON-RPC dispatcher.

	 Answers:
		<McpJsonRpcDispatcher>."

	^super new initialize
]

{ #category : 'Serialization',
  #vaVisibility : 'private' }
McpJsonRpcDispatcher >> detachedJsonValue: anObject [
	"Answer a detached JSON-compatible value.

	 Arguments:
		anObject - <Object> protocol value.
	 Answers:
		<Object> detached value."

	^self detachedJsonValue: anObject visited: IdentitySet new
]

{ #category : 'Serialization',
  #vaVisibility : 'private' }
McpJsonRpcDispatcher >> detachedJsonValue: anObject visited: visitedObjects [
	"Copy JSON data while rejecting cycles and unsupported objects.

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
	(visitedObjects includes: anObject) ifTrue: [self error: 'JSON-RPC value contains a cycle'].
	(anObject isKindOf: KeyedCollection)
		ifTrue: [
			visitedObjects add: anObject.
			[
				detached := EsOrderedDictionary new.
				anObject keysAndValuesDo: [:key :value |
					key isString ifFalse: [self error: 'JSON-RPC object keys must be strings'].
					detached
						at: key copy
						put: (self detachedJsonValue: value visited: visitedObjects)]]
							ensure: [visitedObjects remove: anObject ifAbsent: []].
			^detached].
	(anObject isKindOf: SequenceableCollection)
		ifTrue: [
			visitedObjects add: anObject.
			[
				detached :=
					anObject
						collect: [:value | self detachedJsonValue: value visited: visitedObjects]]
							ensure: [visitedObjects remove: anObject ifAbsent: []].
			^detached asArray].
	self error: 'JSON-RPC value is not JSON-compatible'
]

{ #category : 'Dispatching' }
McpJsonRpcDispatcher >> dispatch: aDictionary [
	"Dispatch one JSON-RPC message without a server request context.

	 Arguments:
		aDictionary - <KeyedCollection> decoded JSON-RPC message.
	 Answers:
		<KeyedCollection> response, or nil."

	^self dispatch: aDictionary context: nil
]

{ #category : 'Dispatching' }
McpJsonRpcDispatcher >> dispatch: aDictionary context: requestContext [
	"Validate and dispatch one JSON-RPC message with request context.

	 Readable request identifiers remain correlated in validation errors.

	 Arguments:
		aDictionary - <KeyedCollection> decoded JSON-RPC message.
		requestContext - <McpServerRequestContext> or nil.
	 Answers:
		<KeyedCollection> response, or nil."

	| hasId identifier responseIdentifier method parameters result response |

	(aDictionary isKindOf: KeyedCollection)
		ifFalse: [
			^self
				formatError: McpJsonRpcInvalidRequestCode
				message: 'Invalid Request: expected an object'
				id: nil
				data: nil].
	hasId := aDictionary includesKey: 'id'.
	identifier := hasId ifTrue: [aDictionary at: 'id'] ifFalse: [nil].
	responseIdentifier :=
		(hasId and: [self isValidRequestIdentifier: identifier]) ifTrue: [identifier] ifFalse: [nil].
	(aDictionary at: 'jsonrpc' ifAbsent: [nil]) = '2.0'
		ifFalse: [
			^self
				formatError: McpJsonRpcInvalidRequestCode
				message: 'Invalid Request: invalid jsonrpc version'
				id: responseIdentifier
				data: nil].
	method := aDictionary at: 'method' ifAbsent: [nil].
	method ifNil: [
		(self isValidResponseObject: aDictionary) ifTrue: [^nil].
		^self
			formatError: McpJsonRpcInvalidRequestCode
			message: 'Invalid Request: missing method'
			id: responseIdentifier
			data: nil].
	hasId
		ifTrue: [
			(self isValidRequestIdentifier: identifier)
				ifFalse: [
					^self
						formatError: McpJsonRpcInvalidRequestCode
						message: 'Invalid Request: invalid identifier'
						id: nil
						data: nil]].
	method isString
		ifFalse: [
			hasId ifFalse: [^nil].
			^self
				formatError: McpJsonRpcInvalidRequestCode
				message: 'Invalid Request: method must be a string'
				id: identifier
				data: nil].
	parameters := aDictionary at: 'params' ifAbsent: [EsOrderedDictionary new].
	(parameters isKindOf: KeyedCollection)
		ifFalse: [
			hasId ifFalse: [^nil].
			^self
				formatError: McpJsonRpcInvalidRequestCode
				message: 'Invalid Request: params must be an object'
				id: identifier
				data: nil].
	(parameters isKindOf: KeyedCollection)
		ifTrue: [| meta reqVersion |
			meta := parameters at: '_meta' ifAbsent: [nil].
			(meta isKindOf: KeyedCollection)
				ifTrue: [
					reqVersion := meta at: 'io.modelcontextprotocol/protocolVersion' ifAbsent: [nil].
					(reqVersion notNil and: [(self server supportedProtocolVersions includes: reqVersion) not])
						ifTrue: [| errData |
							hasId ifFalse: [^nil].
							errData :=
								EsOrderedDictionary new
									at: 'supported' put: self server supportedProtocolVersions;
									at: 'requested' put: reqVersion;
									yourself.
							^self
								formatError: -32022
								message: 'Unsupported protocol version'
								id: responseIdentifier
								data: errData]]].
	[
		[
			result :=
				self
					dispatchMethod: method
					params: (self detachedJsonValue: parameters)
					id: identifier
					context: requestContext.
			result := self detachedJsonValue: result]
				on: McpJsonRpcError
				do: [:rpcError |
					hasId ifFalse: [^nil].
					^self
						formatError: rpcError code
						message: rpcError messageText
						id: identifier
						data: rpcError data]]
							on: Error
							do: [:unexpectedError |
								hasId ifFalse: [^nil].
								^self
									formatError: McpJsonRpcInternalErrorCode
									message: 'Internal error'
									id: identifier
									data: nil].
	hasId ifFalse: [^nil].
	(self server isModernContext: requestContext orParams: parameters)
		ifTrue: [
			(result isKindOf: KeyedCollection)
				ifTrue: [| meta serverInfo |
					serverInfo :=
						EsOrderedDictionary new
							at: 'name' put: self server name;
							at: 'version' put: self server version;
							yourself.
					meta := result at: '_meta' ifAbsentPut: [EsOrderedDictionary new].
					(meta isKindOf: KeyedCollection)
						ifTrue: [
							(meta includesKey: 'io.modelcontextprotocol/serverInfo')
								ifFalse: [
									meta at: 'io.modelcontextprotocol/serverInfo' put: serverInfo]]]].
	response :=
		EsOrderedDictionary new
			at: 'jsonrpc' put: '2.0';
			at: 'id' put: identifier;
			at: 'result' put: result;
			yourself.
	^response
]

{ #category : 'Dispatching' }
McpJsonRpcDispatcher >> dispatchMethod: methodName params: parameters id: identifier [
	"Dispatch one method without a server request context.

	 Arguments:
		methodName - <String> JSON-RPC method name.
		parameters - <KeyedCollection> method parameters.
		identifier - <Object> request identifier, or nil.
	 Answers:
		<Object> handler result."

	^self dispatchMethod: methodName params: parameters id: identifier context: nil
]

{ #category : 'Dispatching' }
McpJsonRpcDispatcher >> dispatchMethod: methodName params: parameters id: identifier context: requestContext [
	"Dispatch one method with its server request context.

	 Arguments:
		methodName - <String> JSON-RPC method name.
		parameters - <KeyedCollection> method parameters.
		identifier - <Object> request identifier, or nil.
		requestContext - <McpServerRequestContext> or nil.
	 Answers:
		<Object> handler result."

	| handler |

	handler :=
		methodMap
			at: methodName
			ifAbsent: [
				McpJsonRpcError
					signalCode: McpJsonRpcMethodNotFoundCode
					message: 'Method not found: ' , methodName
					data: nil].
	^handler value: parameters value: requestContext
]

{ #category : 'Formatting' }
McpJsonRpcDispatcher >> formatError: code message: message id: identifier data: data [
	"Build a validated JSON-RPC error response.

	 Arguments:
		code - <Integer> JSON-RPC error code.
		message - <String> nonempty human-readable message.
		identifier - <String>, <Number>, or nil.
		data - <Object> optional JSON-compatible error data.
	 Answers:
		<KeyedCollection> error response."

	| response errorDictionary dataSnapshot |

	code isInteger ifFalse: [self error: 'JSON-RPC error code must be an integer'].
	(message isString and: [message isEmpty not])
		ifFalse: [self error: 'JSON-RPC error message must be nonempty'].
	(self isValidResponseIdentifier: identifier)
		ifFalse: [self error: 'JSON-RPC error identifier is invalid'].
	dataSnapshot := nil.
	data ifNotNil: [
		[dataSnapshot := self detachedJsonValue: data]
			on: Error
			do: [:serializationError | dataSnapshot := nil]].
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
	^response
]

{ #category : 'Initialization',
  #vaVisibility : 'private' }
McpJsonRpcDispatcher >> initialize [
	"Initialize built-in JSON-RPC method dispatch.

	 Answers:
		<McpJsonRpcDispatcher> the receiver."

	super initialize.
	methodMap := Dictionary new.
	methodMap
		at: 'server/discover'
			put: [:parameters :context | self server serverDiscover: parameters context: context];
		at: 'initialize' put: [:parameters :context | self server initializeProtocol: parameters];
		at: 'notifications/initialized'
			put: [:parameters :context | self server initializedNotification: parameters];
		at: 'notifications/cancelled'
			put: [:parameters :context |
				self server cancelledNotification: parameters context: context];
		at: 'ping' put: [:parameters :context | self server ping: parameters context: context];
		at: 'prompts/list'
			put: [:parameters :context | self server promptsList: parameters context: context];
		at: 'prompts/get'
			put: [:parameters :context | self server promptsGet: parameters context: context];
		at: 'resources/list'
			put: [:parameters :context | self server resourcesList: parameters context: context];
		at: 'resources/read'
			put: [:parameters :context | self server resourcesRead: parameters context: context];
		at: 'resources/templates/list'
			put: [:parameters :context |
				self server resourceTemplatesList: parameters context: context];
		at: 'tools/list'
			put: [:parameters :context | self server toolsList: parameters context: context];
		at: 'tools/call'
			put: [:parameters :context | self server toolsCall: parameters context: context];
		at: 'subscriptions/listen'
			put: [:parameters :context |
				self server subscriptionsListen: parameters context: context];
		at: 'completion/complete'
			put: [:parameters :context | self server completionComplete: parameters context: context].
	^self
]

{ #category : 'Validation',
  #vaVisibility : 'private' }
McpJsonRpcDispatcher >> isValidRequestIdentifier: identifier [
	"Answer whether a value is a valid MCP request identifier.

	 MCP restricts request identifiers to strings and integers.

	 Arguments:
		identifier - <Object> identifier candidate.
	 Answers:
		<Boolean>."

	^identifier isString or: [identifier isInteger]
]

{ #category : 'Validation',
  #vaVisibility : 'private' }
McpJsonRpcDispatcher >> isValidResponseIdentifier: identifier [
	"Answer whether a value is valid in a JSON-RPC response.

	 Arguments:
		identifier - <Object> identifier candidate.
	 Answers:
		<Boolean>."

	^identifier isNil or: [self isValidRequestIdentifier: identifier]
]

{ #category : 'Validation',
  #vaVisibility : 'private' }
McpJsonRpcDispatcher >> isValidResponseObject: aDictionary [
	"Answer whether a dictionary is a valid JSON-RPC response object.

	 Arguments:
		aDictionary - <KeyedCollection> response candidate.
	 Answers:
		<Boolean>."

	| hasResult hasError identifier errorDictionary data valid |

	(aDictionary includesKey: 'id') ifFalse: [^false].
	identifier := aDictionary at: 'id'.
	(self isValidResponseIdentifier: identifier) ifFalse: [^false].
	hasResult := aDictionary includesKey: 'result'.
	hasError := aDictionary includesKey: 'error'.
	hasResult = hasError ifTrue: [^false].
	hasResult
		ifTrue: [
			valid := true.
			[self detachedJsonValue: (aDictionary at: 'result')]
				on: Error
				do: [:serializationError | valid := false].
			^valid].
	errorDictionary := aDictionary at: 'error'.
	(errorDictionary isKindOf: KeyedCollection) ifFalse: [^false].
	(errorDictionary at: 'code' ifAbsent: [nil]) isInteger ifFalse: [^false].
	(errorDictionary at: 'message' ifAbsent: [nil]) isString ifFalse: [^false].
	data := errorDictionary at: 'data' ifAbsent: [nil].
	valid := true.
	[self detachedJsonValue: data] on: Error do: [:serializationError | valid := false].
	^valid
]

{ #category : 'Accessing' }
McpJsonRpcDispatcher >> methodMap [
	"Answer a structural snapshot of registered method handlers.

	 Answers:
		<KeyedCollection> method-to-block mapping."

	^methodMap copy
]

{ #category : 'Registration' }
McpJsonRpcDispatcher >> registerMethod: methodName handler: handlerBlock [
	"Register one custom two-argument JSON-RPC method handler.

	 Arguments:
		methodName - <String> nonempty JSON-RPC method name.
		handlerBlock - <Block> accepting parameters and request context.
	 Answers:
		<McpJsonRpcDispatcher> the receiver."

	(methodName isString and: [methodName isEmpty not])
		ifFalse: [self error: 'JSON-RPC method name must be nonempty'].
	(handlerBlock isBlock and: [handlerBlock numArgs = 2])
		ifFalse: [self error: 'JSON-RPC method handler must accept two arguments'].
	(methodMap includesKey: methodName)
		ifTrue: [self error: 'JSON-RPC method is already registered: ' , methodName].
	methodMap at: methodName copy put: handlerBlock.
	^self
]

{ #category : 'Accessing' }
McpJsonRpcDispatcher >> server [
	"Answer the transport-neutral MCP server.

	 Answers:
		<McpServer> or nil."

	^server
]

{ #category : 'Accessing' }
McpJsonRpcDispatcher >> server: anMcpServer [
	"Set the transport-neutral MCP server.

	 Arguments:
		anMcpServer - <McpServer> server implementation.
	 Answers:
		<McpJsonRpcDispatcher> the receiver."

	(anMcpServer isKindOf: McpServer) ifFalse: [self error: 'Dispatcher server must be a McpServer'].
	server := anMcpServer.
	^self
]

{ #category : 'Registration' }
McpJsonRpcDispatcher >> unregisterMethod: methodName [
	"Remove and answer one registered JSON-RPC method handler.

	 Arguments:
		methodName - <String> nonempty JSON-RPC method name.
	 Answers:
		<Block> removed handler, or nil."

	(methodName isString and: [methodName isEmpty not])
		ifFalse: [self error: 'JSON-RPC method name must be nonempty'].
	^methodMap removeKey: methodName ifAbsent: [nil]
]
