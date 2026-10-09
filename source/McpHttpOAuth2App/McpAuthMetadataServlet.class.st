Class {
	#name : 'McpAuthMetadataServlet',
	#superclass : 'SstHttpServlet',
	#category : 'McpHttpOAuth2App'
}

{ #category : 'Request Handling' }
McpAuthMetadataServlet >> doGet: aRequest [
	"Handle metadata requests for oauth endpoints."

	| path authSettings meta json |

	path := aRequest getRequestUri.
	path ifNil: [path := ''].
	authSettings := self transport authSettings.
	authSettings ifNil: [
		aRequest header responseHeader
			status: '404 Not Found';
			contentLength: 0.
		^''].
	(path indexOfSubCollection: '/oauth-authorization-server' startingAt: 1) > 0
		ifTrue: [meta := authSettings authorizationServerMetadata]
		ifFalse: [
			(path indexOfSubCollection: '/oauth-protected-resource' startingAt: 1) > 0
				ifTrue: [meta := authSettings protectedResourceMetadata]
				ifFalse: [
					aRequest header responseHeader
						status: '404 Not Found';
						contentLength: 0.
					^'']].
	json := String streamContents: [:stream | (McpJSONWriter on: stream) nextPut: meta].
	aRequest header responseHeader
		status: '200 OK';
		contentType: 'application/json';
		contentLength: json asUtf8Bytes size.
	^json
]

{ #category : 'Accessing',
  #vaVisibility : 'private' }
McpAuthMetadataServlet >> transport [
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
