"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# McpSseServlet

`McpSseServlet` is an SST HTTP servlet that bridges incoming HTTP requests to
an `McpSseServerTransport`.

## Responsibilities

- Delegate `GET` requests to `McpSseServerTransport>>handleSseGetRequest:`.
- Delegate `POST` requests to `McpSseServerTransport>>handlePostMessageRequest:`.
- Delegate `DELETE` requests to `McpSseServerTransport>>handleDeleteSessionRequest:`.

## Lifecycle and boundaries

Managed by the SST servlet engine within `McpHttpServer`.
"
Class {
	#name : 'McpSseServlet',
	#superclass : 'SstHttpServlet',
	#pools : [
		'McpJsonRpcConstants'
	],
	#category : 'McpHttpServerSubApp'
}

{ #category : 'Protocol Operations' }
McpSseServlet >> doDelete: aRequest [
	"Delegate one DELETE request to the configured SSE transport.

	 Arguments:
		aRequest - <SstHttpServletRequest> incoming HTTP request.
	 Answers:
		<String> HTTP response entity."

	^self transport handleDeleteSessionRequest: aRequest
]

{ #category : 'Protocol Operations' }
McpSseServlet >> doGet: aRequest [
	"Delegate one GET request to the configured SSE transport.

	 Arguments:
		aRequest - <SstHttpServletRequest> incoming HTTP request.
	 Answers:
		<String> HTTP response entity."

	^self transport handleSseGetRequest: aRequest
]

{ #category : 'Protocol Operations' }
McpSseServlet >> doPost: aRequest [
	"Delegate one POST request to the configured SSE transport.

	 Arguments:
		aRequest - <SstHttpServletRequest> incoming HTTP request.
	 Answers:
		<String> HTTP response entity."

	^self transport handlePostMessageRequest: aRequest
]

{ #category : 'Accessing',
  #vaVisibility : 'private' }
McpSseServlet >> transport [
	"Answer the SSE transport installed in this servlet context.

	 Answers:
		<McpSseServerTransport>."

	| servletContext parameters configuredTransport |

	servletContext := self getServletContext.
	servletContext ifNil: [self error: 'MCP SSE servlet context is not configured'].
	parameters :=
		(servletContext respondsTo: #initParameters)
			ifTrue: [servletContext initParameters]
			ifFalse: [
				(servletContext respondsTo: #contextParameters)
					ifTrue: [servletContext contextParameters]
					ifFalse: [nil]].
	parameters ifNil: [self error: 'MCP SSE servlet context parameters are not configured'].
	configuredTransport :=
		parameters at: 'sseTransport' ifAbsent: [self error: 'MCP SSE transport is not configured'].
	(configuredTransport isKindOf: McpSseServerTransport)
		ifFalse: [self error: 'MCP SSE transport has an invalid type'].
	^configuredTransport
]
