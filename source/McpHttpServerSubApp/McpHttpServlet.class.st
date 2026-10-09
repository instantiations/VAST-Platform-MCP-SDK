"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# McpHttpServlet

`McpHttpServlet` adapts SST HTTP servlet container requests to the MCP
streamable HTTP transport.

## Responsibilities

- Route incoming HTTP verbs (`POST`, `GET`, `DELETE`) to the configured
  `McpStreamableHttpTransport`.
- Locate and bind the active transport from servlet context configuration via
  `#initParameters` (with fallback to `#contextParameters`).

## Lifecycle and boundaries

The servlet engine owns instance lifecycle and concurrency.
"
Class {
	#name : 'McpHttpServlet',
	#superclass : 'SstHttpServlet',
	#category : 'McpHttpServerSubApp'
}

{ #category : 'Request Handling' }
McpHttpServlet >> doDelete: aRequest [
	"Return a flushed UTF-8 entity or the transport's streaming writer."

	^self responseEntity: (self transport handleDeleteRequest: aRequest)
		for: aRequest
]

{ #category : 'Request Handling' }
McpHttpServlet >> doGet: aRequest [
	"Return a flushed UTF-8 entity or the transport's streaming writer."

	^self responseEntity: (self transport handleGetRequest: aRequest)
		for: aRequest
]

{ #category : 'Request Handling' }
McpHttpServlet >> doPost: aRequest [
	"Return a flushed UTF-8 entity or the transport's streaming writer."

	^self responseEntity: (self transport handlePostRequest: aRequest)
		for: aRequest
]

{ #category : 'Execution' }
McpHttpServlet >> responseEntity: anEntity for: aRequest [
	"Encode finite entities and discard an opening whose response cannot send.
	Arguments:
		anEntity - <String | ByteArray | Block> response entity.
		aRequest - <SstHttpServletRequest> current HTTP request.
	Answers:
		<Block> response writer; stream failures propagate to the caller."
	| bytes openingSession responseSession responseTransport |
	anEntity isBlock ifTrue: [^anEntity].
	bytes := anEntity isString ifTrue: [anEntity asUtf8Bytes]
		ifFalse: [anEntity asByteArray].
	aRequest header responseHeader contentLength: bytes size.
	openingSession := aRequest header responseHeader
		at: 'MCP-Session-Id' ifAbsent: [nil].
	responseSession := openingSession ifNil: [
		aRequest getHeader: 'MCP-Session-Id'].
	responseTransport := self transport.
	^[:connection | | delivered
		pinnedSession |
		delivered := false.
		pinnedSession := responseTransport
			beginResponseForSessionNamed: responseSession.
		[
			connection stream nextPutAll: bytes; flush.
			delivered := true
		] ensure: [
			[
				(delivered not and: [openingSession notNil]) ifTrue: [
					responseTransport removeSessionNamed: openingSession]
			] ensure: [responseTransport endResponseForSession: pinnedSession]]]

]

{ #category : 'Accessing',
  #vaVisibility : 'private' }
McpHttpServlet >> transport [
	"Answer the transport installed in this servlet context.

	 Answers:
		<McpStreamableHttpTransport> configured request transport."

	| servletContext parameters configuredTransport |

	servletContext := self getServletContext.
	servletContext ifNil: [self error: 'MCP servlet context is not configured'].
	parameters :=
		(servletContext respondsTo: #initParameters)
			ifTrue: [servletContext initParameters]
			ifFalse: [
				(servletContext respondsTo: #contextParameters)
					ifTrue: [servletContext contextParameters]
					ifFalse: [nil]].
	parameters ifNil: [self error: 'MCP servlet context parameters are not configured'].
	configuredTransport :=
		parameters
			at: 'mcpTransport'
			ifAbsent: [self error: 'MCP servlet transport is not configured'].
	(configuredTransport isKindOf: McpStreamableHttpTransport)
		ifFalse: [self error: 'MCP servlet transport has an invalid type'].
	^configuredTransport
]
