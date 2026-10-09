"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# McpScriptedHttpClient

`McpScriptedHttpClient` records HTTP operations and returns queued responses.

## Responsibilities

- Record POST bodies, media types, endpoints, and request headers.
- Record DELETE endpoints and request headers.
- Return exactly one queued response per HTTP operation.
- Record SST shutdown without opening a socket.

Each test owns one mutable instance and explicitly queues every response. The
fixture performs no network I/O, scheduling, or concurrent synchronization.
"
Class {
	#name : 'McpScriptedHttpClient',
	#superclass : 'Object',
	#instVars : [
		'responses',
		'posts',
		'deletes',
		'shutdownCount'
	],
	#category : 'McpHttpClientTests'
}

{ #category : 'Instance Creation' }
McpScriptedHttpClient class >> new [
	"Answer a scripted client initialized with empty queues and logs."

	^super new initialize
]

{ #category : 'Protocol Operations' }
McpScriptedHttpClient >> delete: endpoint typed: mediaType using: context withHeaders: headers [
	"Record one DELETE and answer the next scripted response."

	deletes add: (
		EsOrderedDictionary new
			at: 'endpoint' put: endpoint;
			at: 'mediaType' put: mediaType;
			at: 'context' put: context;
			at: 'headers' put: headers;
			yourself).
	^self nextResponse
]

{ #category : 'Accessing' }
McpScriptedHttpClient >> deletes [
	"Answer the recorded DELETE operations."

	^deletes
]

{ #category : 'Test Support' }
McpScriptedHttpClient >> enqueueResponse: response [
	"Queue one response for the next HTTP operation."

	responses add: response.
	^self
]

{ #category : 'Initialization',
  #vaVisibility : 'private' }
McpScriptedHttpClient >> initialize [
	"Initialize response scripts and operation logs."

	super initialize.
	responses := OrderedCollection new.
	posts := OrderedCollection new.
	deletes := OrderedCollection new.
	shutdownCount := 0.
	^self
]

{ #category : 'Test Support',
  #vaVisibility : 'private' }
McpScriptedHttpClient >> nextResponse [
	"Remove and answer the next explicitly queued response."

	responses isEmpty ifTrue: [self error: 'No scripted HTTP response remains'].
	^responses removeFirst
]

{ #category : 'Protocol Operations' }
McpScriptedHttpClient >> post: body typed: mediaType at: endpoint using: context withHeaders: headers [
	"Record one POST and answer the next scripted response."

	posts add: (
		EsOrderedDictionary new
			at: 'body' put: body;
			at: 'mediaType' put: mediaType;
			at: 'endpoint' put: endpoint;
			at: 'context' put: context;
			at: 'headers' put: headers;
			yourself).
	^self nextResponse
]

{ #category : 'Accessing' }
McpScriptedHttpClient >> posts [
	"Answer the recorded POST operations."

	^posts
]

{ #category : 'Starting and Stopping' }
McpScriptedHttpClient >> shutDown [
	"Record one SST shutdown."

	shutdownCount := shutdownCount + 1.
	^self
]

{ #category : 'Accessing' }
McpScriptedHttpClient >> shutdownCount [
	"Answer the number of recorded SST shutdowns."

	^shutdownCount
]
