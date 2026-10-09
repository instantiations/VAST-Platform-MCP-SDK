"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# McpHttpServerTestRequest

`McpHttpServerTestRequest` models the request protocol consumed by the server
transport without constructing an SST listener.

## Responsibilities

- Retain request fields, media type, and raw entity bytes.
- Provide case-insensitive request-field lookup.
- Provide a writable response header through the servlet request protocol.

Each test owns and configures one mutable request fixture. It performs no I/O,
scheduling, authentication, or implicit normalization.
"
Class {
	#name : 'McpHttpServerTestRequest',
	#superclass : 'Object',
	#instVars : [
		'headers',
		'contentType',
		'contents',
		'requestHeader',
		'requestUri'
	],
	#category : 'McpHttpServerTests'
}

{ #category : 'Instance Creation' }
McpHttpServerTestRequest class >> new [
	"Answer an initialized empty request."

	^super new initialize
]

{ #category : 'Accessing' }
McpHttpServerTestRequest >> contentType: mediaType [
	"Set the request Content-Type value."

	contentType := mediaType.
	^self
]

{ #category : 'Accessing' }
McpHttpServerTestRequest >> contents [
	"Answer the raw request entity bytes."

	^contents
]

{ #category : 'Accessing' }
McpHttpServerTestRequest >> contents: bytes [
	"Set the raw request entity bytes."

	contents := bytes.
	^self
]

{ #category : 'Accessing' }
McpHttpServerTestRequest >> getContentType [
	"Answer the request Content-Type value."

	^contentType
]

{ #category : 'Accessing' }
McpHttpServerTestRequest >> getHeader: fieldName [
	"Answer a request field by case-insensitive name, or nil."

	| existingName |

	existingName := headers keys detect: [:name | name sameAs: fieldName] ifNone: [nil].
	^existingName ifNil: [nil] ifNotNil: [headers at: existingName]
]

{ #category : 'Accessing' }
McpHttpServerTestRequest >> getRequestUri [
	"Answer the requested URI path and query string.

	 Answers:
		<String>."

	^requestUri
]

{ #category : 'Accessing' }
McpHttpServerTestRequest >> header [
	"Answer the request-header collaboration."

	^requestHeader
]

{ #category : 'Test Support' }
McpHttpServerTestRequest >> headerAt: fieldName put: fieldValue [
	"Set a request field after removing a case-insensitive duplicate."

	| existingName |

	existingName := headers keys detect: [:name | name sameAs: fieldName] ifNone: [nil].
	existingName ifNotNil: [headers removeKey: existingName].
	headers at: fieldName put: fieldValue.
	^self
]

{ #category : 'Initialization',
  #vaVisibility : 'private' }
McpHttpServerTestRequest >> initialize [
	"Initialize empty request state and a response header."

	super initialize.
	headers := EsOrderedDictionary new.
	contentType := nil.
	contents := #().
	requestHeader := McpHttpServerTestRequestHeader new.
	^self
]

{ #category : 'Accessing' }
McpHttpServerTestRequest >> requestUri: aString [
	"Set the requested URI path and query string.

	 Arguments:
		aString - <String>.
	 Answers:
		<McpHttpServerTestRequest> the receiver."

	requestUri := aString.
	^self
]
