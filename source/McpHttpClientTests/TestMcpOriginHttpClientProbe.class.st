"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

Endpoint-free HTTP probe for the actual MCP redirect send loop.
All hops share ordered response and observation collections. The probe owns
its child hops and records shutdown; it never starts an SST endpoint.
"
Class {
	#name : 'TestMcpOriginHttpClientProbe',
	#superclass : 'McpOriginHttpClient',
	#instVars : [
		'responses',
		'sentRequests',
		'closeCount',
		'discardCount'
	],
	#category : 'McpHttpClientTests'
}

{ #category : 'Instance Creation' }
TestMcpOriginHttpClientProbe class >> responses: scriptedResponses observations: observations [
	"Create a probe with a shared script and detached request observations.
	Arguments:
		scriptedResponses - <OrderedCollection> HTTP responses.
		observations - <OrderedCollection> captured URL/request pairs.
	Answers:
		<TestMcpOriginHttpClientProbe> initialized probe."
	^self basicNew initializeResponses: scriptedResponses observations:
		observations

]

{ #category : 'Fixtures',
  #vaVisibility : 'private' }
TestMcpOriginHttpClientProbe >> basicSend: requestMessage to: endpoint assemblerPolicy: policy [
	"Record exactly the request that the production send loop attempts.
	Arguments:
		requestMessage - <SstCommunicationMessage> request.
		endpoint - <SstHttpUrl> destination.
		policy - <Object> unused fixture policy.
	Answers:
		<McpHttpClientTestResponse> next scripted response."
	sentRequests add: (endpoint copy -> requestMessage).
	^responses removeFirst

]

{ #category : 'Fixtures',
  #vaVisibility : 'private' }
TestMcpOriginHttpClientProbe >> clientForRedirectTo: destination [
	"Create a child probe sharing the remaining response script.
	Arguments:
		destination - <SstHttpUrl> approved destination.
	Answers:
		<TestMcpOriginHttpClientProbe> next hop."
	^self class responses: responses observations: sentRequests

]

{ #category : 'Fixtures' }
TestMcpOriginHttpClientProbe >> closedHopCount [
	"Answer the number of closed hops including the receiver.
	Answers:
		<Integer> closed-hop count."
	^(closeCount > 0 ifTrue: [1] ifFalse: [0]) +
		(redirectClient ifNil: [0] ifNotNil: [redirectClient closedHopCount])

]

{ #category : 'Fixtures',
  #vaVisibility : 'private' }
TestMcpOriginHttpClientProbe >> discardRedirectResponse: response [
	"Record disposal without consuming a nonexistent socket stream.
	Arguments:
		response - <McpHttpClientTestResponse> redirect response.
	Answers:
		<TestMcpOriginHttpClientProbe> the receiver."
	discardCount := discardCount + 1

]

{ #category : 'Initialization',
  #vaVisibility : 'private' }
TestMcpOriginHttpClientProbe >> initializeResponses: scriptedResponses observations: observations [
	"Initialize synchronizers without opening any SST endpoints.
	Arguments:
		scriptedResponses - <OrderedCollection> HTTP responses.
		observations - <OrderedCollection> captured requests.
	Answers:
		<TestMcpOriginHttpClientProbe> the receiver."
	synchronizer := Semaphore forMutualExclusion.
	proxyEnabled := false.
	responses := scriptedResponses.
	sentRequests := observations.
	closeCount := 0.
	discardCount := 0

]

{ #category : 'Resource Management' }
TestMcpOriginHttpClientProbe >> shutDown [
	"Record shutdown and close owned child probes.
	Answers:
		<TestMcpOriginHttpClientProbe> the receiver."
	closeCount := closeCount + 1.
	redirectClient ifNotNil: [redirectClient shutDown]

]
