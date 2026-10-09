"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# McpHttpClientTestResponse

`McpHttpClientTestResponse` supplies one scripted HTTP response.

## Responsibilities

- Retain a test response header and raw entity bytes.
- Identify itself as a successful SST response object.

Instances are mutable fixtures owned by one scripted client response queue.
They perform no I/O and are not shared across tests.
"
Class {
	#name : 'McpHttpClientTestResponse',
	#superclass : 'Object',
	#instVars : [
		'header',
		'contents'
	],
	#category : 'McpHttpClientTests'
}

{ #category : 'Accessing' }
McpHttpClientTestResponse >> contents [
	"Answer the raw response entity bytes."

	^contents
]

{ #category : 'Accessing' }
McpHttpClientTestResponse >> contents: bytes [
	"Set the raw response entity bytes."

	contents := bytes.
	^self
]

{ #category : 'Accessing' }
McpHttpClientTestResponse >> header [
	"Answer the scripted response header."

	^header
]

{ #category : 'Accessing' }
McpHttpClientTestResponse >> header: aHeader [
	"Set the scripted response header."

	header := aHeader.
	^self
]

{ #category : 'Testing' }
McpHttpClientTestResponse >> isSstError [
	"Answer false because this fixture represents a received response."

	^false
]
