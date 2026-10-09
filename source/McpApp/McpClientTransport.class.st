"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# McpClientTransport

`McpClientTransport` defines the transport boundary used by an MCP client.

## Responsibilities

- Send correlated requests and notifications for the owning client.
- Advertise optional request-scoped header support explicitly.

## Lifecycle and boundaries

One client owns a transport from connection through shutdown.
"
Class {
	#name : 'McpClientTransport',
	#superclass : 'Object',
	#instVars : [
		'client'
	],
	#category : 'McpApp'
}

{ #category : 'Instance Creation' }
McpClientTransport class >> new [
	"Answer a new initialized transport instance.

	 Concrete subclasses configure their endpoint before client connection.

	 Answers:
		<McpClientTransport>."

	^super new initialize
]

{ #category : 'Accessing' }
McpClientTransport >> client [
	"Answer the client that owns this transport.

	 Answers:
		<McpClient> or nil."

	^client
]

{ #category : 'Accessing' }
McpClientTransport >> client: anMcpClient [
	"Set or clear the client that owns this transport.

	 The owning `McpClient` enforces exclusive transport ownership.

	 Arguments:
		anMcpClient - <McpClient> or nil.
	 Answers:
		<McpClientTransport> the receiver."

	(anMcpClient isNil or: [anMcpClient isKindOf: McpClient])
		ifFalse: [self error: 'MCP transport owner must be an McpClient or nil'].
	client := anMcpClient.
	^self
]

{ #category : 'Protocol Operations' }
McpClientTransport >> sendNotification: notification [
	"Send one JSON-RPC notification.

	 Arguments:
		notification - <KeyedCollection> detached JSON-RPC notification.
	 Answers:
		<McpClientTransport> the receiver."

	^self subclassResponsibility
]

{ #category : 'Protocol Operations' }
McpClientTransport >> sendRequest: request id: identifier [
	"Send one JSON-RPC request and answer its correlated result.

	 Arguments:
		request - <KeyedCollection> detached JSON-RPC request.
		identifier - <String> or <Integer> correlation identifier.
	 Answers:
		<Object> decoded JSON-compatible result."

	^self subclassResponsibility
]

{ #category : 'Protocol Operations' }
McpClientTransport >> sendRequest: request id: identifier headers: requestHeaders [
	"Send one request with transport-specific scoped headers.

	 Subclasses implementing this selector must also answer true from
	 `supportsRequestHeaders`.

	 Arguments:
		request - <KeyedCollection> detached JSON-RPC request.
		identifier - <String> or <Integer> correlation identifier.
		requestHeaders - <KeyedCollection> scoped transport headers.
	 Answers:
		<Object> decoded JSON-compatible result."

	^self subclassResponsibility
]

{ #category : 'Accessing' }
McpClientTransport >> supportsRequestHeaders [
	"Answer whether scoped-header send selectors are implemented.

	 Answers:
		<Boolean>."

	^false
]
