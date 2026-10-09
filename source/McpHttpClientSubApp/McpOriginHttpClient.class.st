"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

SST client for MCP exchanges with bounded origin-preserving redirects.
Owns any downstream client until shutdown, including streamed responses.
Uses private SST configurations and preserves the request method and body.
One instance is used for one exchange; callers must always shut it down.
"
Class {
	#name : 'McpOriginHttpClient',
	#superclass : 'SstHttpClient',
	#instVars : [
		'redirectClient'
	],
	#category : 'McpHttpClientSubApp'
}

{ #category : 'Instance Creation' }
McpOriginHttpClient class >> forConfiguration: aConfiguration [
	"Copy SST configuration before attaching an endpoint.
	Arguments:
		aConfiguration - <SstTransportConfiguration> source configuration.
	Answers:
		<McpOriginHttpClient | SstError> initialized client."
	^super forConfiguration: aConfiguration copy

]

{ #category : 'Instance Creation',
  #vaVisibility : 'private' }
McpOriginHttpClient >> clientForRedirectTo: destination [
	"Create the next hop with the appropriate transport and timeout.
	Arguments:
		destination - <SstHttpUrl> approved target.
	Answers:
		<McpOriginHttpClient>."
	| nextClient |
	nextClient := self class forTransportScheme:
		destination localEndpointUrl transport.
	nextClient isSstError ifTrue: [nextClient raise].
	nextClient configuration
		negotiationTimeout: self configuration negotiationTimeout;
		sendTimeout: self configuration sendTimeout;
		receiveTimeout: self configuration receiveTimeout.
	^nextClient

]

{ #category : 'Resource Management',
  #vaVisibility : 'private' }
McpOriginHttpClient >> discardRedirectResponse: response [
	"Cancel an unused streamed redirect body before closing its connection.
	Arguments:
		response - <SstCommunicationMessage> redirect response.
	Answers:
		<McpOriginHttpClient> the receiver."
	| subscription |
	response isStreamed ifTrue: [
		response inputStream ifNotNil: [:stream |
			subscription := stream listen: [:chunk | ]
				onError: [:failure | ] onDone: [] cancelOnError: true.
			subscription cancel]].
	super shutDown

]

{ #category : 'Configuration',
  #vaVisibility : 'private' }
McpOriginHttpClient >> redirectCount [
	"Answer the MCP redirect budget, independent of SST automatic redirects.
	Answers:
		<Integer> maximum followed redirects."
	^20

]

{ #category : 'Execution' }
McpOriginHttpClient >> send: requestMessage to: endpoint redirect: remaining assemblerPolicy: policy [
	"Send once and follow only a method-preserving authorized redirect.
	Arguments:
		requestMessage - <SstCommunicationMessage> request.
		endpoint - <SstHttpUrl> current endpoint.
		remaining - <Integer> remaining redirect budget.
		policy - <SstHttpAssemblerPolicy> response assembly policy.
	Answers:
		<SstCommunicationMessage | SstError> response.
	Raises:
		<Error> refused redirect; the MCP session remains intact."
	| response statusCode location destination copiedRequest |
	response := synchronizer critical: [
		self basicSend: requestMessage to: endpoint assemblerPolicy: policy].
	response isSstError ifTrue: [^response].
	statusCode := response header statusCode.
	(statusCode between: 300 and: 399) ifFalse: [^response].
	location := response header location.
	(remaining <= 0 or: [location isEmptyOrNil])
		ifTrue: [self error: 'MCP HTTP redirect was not followed'].
	(#(301 302 303 307 308) includes: statusCode)
		ifFalse: [self error: 'MCP HTTP redirect was not followed'].
	((#(301 302 303) includes: statusCode) and: [
		requestMessage header command ~= 'GET'])
		ifTrue: [self error: 'MCP HTTP redirect would change the method'].
	destination := McpHttpUrlPolicy resolve: location against: endpoint.
	(McpHttpUrlPolicy allows: destination from: endpoint)
		ifFalse: [self error: 'MCP HTTP redirect leaves the endpoint origin'].
	self discardRedirectResponse: response.
	redirectClient := self clientForRedirectTo: destination.
	copiedRequest := requestMessage copy.
	copiedRequest header: requestMessage header copy.
	copiedRequest header fields: requestMessage header fields copy.
	copiedRequest header
		url: (redirectClient requestUriForUrl: destination);
		host: (redirectClient requestHostAddressForUrl: destination).
	^redirectClient send: copiedRequest to: destination
		redirect: remaining - 1 assemblerPolicy: policy

]

{ #category : 'Resource Management' }
McpOriginHttpClient >> shutDown [
	"Close every owned redirect client, including a final live SSE stream.
	Answers:
		<McpOriginHttpClient> the receiver."
	| downstream |
	downstream := redirectClient.
	redirectClient := nil.
	[downstream ifNotNil: [downstream shutDown]] ensure: [super shutDown]

]
