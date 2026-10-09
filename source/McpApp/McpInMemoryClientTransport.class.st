"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# McpInMemoryClientTransport

`McpInMemoryClientTransport` connects an `McpClient` directly to an in-process
`McpServer` and its dispatcher without socket or serialization overhead.

## Responsibilities

- Deliver requests directly to an in-process `McpJsonRpcDispatcher`.
- Construct request contexts populated with client capabilities, client info,
  and progress reporters.
- Bridge `subscriptions/listen` requests directly to the server's
  `McpSubscriptionBus`.
- Support modern and legacy modes within the same Smalltalk image for fast,
  reliable unit and integration testing.

## Lifecycle and boundaries

The transport references the server directly. It remains open until closed by
its owning client.
"
Class {
	#name : 'McpInMemoryClientTransport',
	#superclass : 'McpClientTransport',
	#instVars : [
		'server',
		'dispatcher'
	],
	#category : 'McpApp'
}

{ #category : 'Instance Creation' }
McpInMemoryClientTransport class >> server: anMcpServer [
	"Answer a new in-memory transport for the given server.

	 Arguments:
		anMcpServer - <McpServer> in-process server.
	 Answers:
		<McpInMemoryClientTransport>."

	^self new server: anMcpServer
]

{ #category : 'Instance Creation' }
McpInMemoryClientTransport class >> server: anMcpServer dispatcher: aDispatcher [
	"Answer a new in-memory transport for the given server and dispatcher.

	 Arguments:
		anMcpServer - <McpServer> in-process server.
		aDispatcher - <McpJsonRpcDispatcher> protocol dispatcher.
	 Answers:
		<McpInMemoryClientTransport>."

	^self new
		server: anMcpServer;
		dispatcher: aDispatcher;
		yourself
]

{ #category : 'Starting and Stopping' }
McpInMemoryClientTransport >> close [
	"Close the in-memory transport.

	 Answers:
		<McpInMemoryClientTransport> the receiver."

	^self
]

{ #category : 'Accessing' }
McpInMemoryClientTransport >> dispatcher [
	"Answer the protocol dispatcher, creating a default one if needed.

	 Answers:
		<McpJsonRpcDispatcher>."

	dispatcher ifNil: [
		self server ifNotNil: [:s |
			dispatcher :=
				McpJsonRpcDispatcher new
					server: s;
					yourself]].
	^dispatcher
]

{ #category : 'Accessing' }
McpInMemoryClientTransport >> dispatcher: aDispatcher [
	"Set the protocol dispatcher.

	 Arguments:
		aDispatcher - <McpJsonRpcDispatcher>.
	 Answers:
		<McpInMemoryClientTransport> the receiver."

	dispatcher := aDispatcher.
	^self
]

{ #category : 'Protocol Operations' }
McpInMemoryClientTransport >> sendNotification: aNotification [
	"Dispatch one notification directly to the in-memory dispatcher.

	 Arguments:
		aNotification - <KeyedCollection> detached JSON-RPC notification.
	 Answers:
		<McpInMemoryClientTransport> the receiver."

	^self sendNotification: aNotification headers: nil
]

{ #category : 'Protocol Operations' }
McpInMemoryClientTransport >> sendNotification: aNotification headers: requestHeaders [
	"Dispatch one notification directly to the in-memory dispatcher.

	 Arguments:
		aNotification - <KeyedCollection> detached JSON-RPC notification.
		requestHeaders - <KeyedCollection> or nil, scoped transport headers.
	 Answers:
		<McpInMemoryClientTransport> the receiver."

	| context |

	context := McpServerRequestContext new.
	context transportRequest: aNotification.
	self client ifNotNil: [:c |
		context protocolVersion: (c protocolVersion ifNil: ['2026-07-28']).
		context clientInfo: c clientInfo.
		context clientCapabilities: c capabilities].
	self dispatcher dispatch: aNotification context: context.
	^self
]

{ #category : 'Protocol Operations' }
McpInMemoryClientTransport >> sendRequest: aRequest id: anIdentifier [
	"Dispatch one request directly to the in-memory server and answer its result.

	 Arguments:
		aRequest - <KeyedCollection> detached JSON-RPC request.
		anIdentifier - <String> or <Integer> correlation identifier.
	 Answers:
		<Object> decoded JSON-compatible result."

	^self sendRequest: aRequest id: anIdentifier headers: nil
]

{ #category : 'Protocol Operations' }
McpInMemoryClientTransport >> sendRequest: aRequest id: anIdentifier headers: requestHeaders [
	"Dispatch one request directly to the in-memory server and answer its result.

	 Arguments:
		aRequest - <KeyedCollection> detached JSON-RPC request.
		anIdentifier - <String> or <Integer> correlation identifier.
		requestHeaders - <KeyedCollection> or nil, scoped transport headers.
	 Answers:
		<Object> decoded JSON-compatible result."

	| context params meta token rawResponse errorObj method |

	context := McpServerRequestContext new.
	context transportRequest: aRequest.
	self client ifNotNil: [:c |
		context protocolVersion: (c protocolVersion ifNil: ['2026-07-28']).
		context clientInfo: c clientInfo.
		context clientCapabilities: c capabilities].
	params := aRequest at: 'params' ifAbsent: [nil].
	(params isKindOf: KeyedCollection)
		ifTrue: [
			meta := params at: '_meta' ifAbsent: [nil].
			(meta isKindOf: KeyedCollection)
				ifTrue: [token := meta at: 'progressToken' ifAbsent: [nil]].
			token ifNil: [token := params at: 'progressToken' ifAbsent: [nil]].
			token ifNotNil: [
				context progressToken: token.
				self client ifNotNil: [:c |
					context progressReporter: [:progressParams |
						c handleIncomingMessage: (
							EsOrderedDictionary new
								at: 'jsonrpc' put: '2.0';
								at: 'method' put: 'notifications/progress';
								at: 'params' put: progressParams;
								yourself)]]]].
	method := aRequest at: 'method' ifAbsent: [nil].
	method = 'subscriptions/listen'
		ifTrue: [| filter |
			filter :=
				(params isKindOf: KeyedCollection)
					ifTrue: [params at: 'notifications' ifAbsent: [EsOrderedDictionary new]]
					ifFalse: [EsOrderedDictionary new].
			self server ifNotNil: [:s |
				s subscriptionBus
					subscribe: filter
					callback: [:notifMethod :notifParams |
						self client ifNotNil: [:c |
							c handleIncomingMessage: (
								EsOrderedDictionary new
									at: 'jsonrpc' put: '2.0';
									at: 'method' put: notifMethod;
									at: 'params' put: notifParams;
									yourself)]]]].
	rawResponse := self dispatcher dispatch: aRequest context: context.
	rawResponse ifNil: [^nil].
	(rawResponse includesKey: 'error')
		ifTrue: [
			errorObj := rawResponse at: 'error'.
			McpJsonRpcError
				signalCode: (errorObj at: 'code')
				message: (errorObj at: 'message')
				data: (errorObj at: 'data' ifAbsent: [nil])].
	^rawResponse at: 'result' ifAbsent: [nil]
]

{ #category : 'Accessing' }
McpInMemoryClientTransport >> server [
	"Answer the in-memory MCP server.

	 Answers:
		<McpServer> or nil."

	^server
]

{ #category : 'Accessing' }
McpInMemoryClientTransport >> server: anMcpServer [
	"Set the in-memory MCP server.

	 Arguments:
		anMcpServer - <McpServer> in-process server.
	 Answers:
		<McpInMemoryClientTransport> the receiver."

	(anMcpServer isKindOf: McpServer)
		ifFalse: [self error: 'In-memory transport server must be an McpServer'].
	server := anMcpServer.
	dispatcher := nil.
	^self
]

{ #category : 'Testing' }
McpInMemoryClientTransport >> supportsRequestHeaders [
	"Answer whether scoped-header send selectors are supported.

	 Answers:
		<Boolean> true."

	^true
]
