"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# McpHttpClientTestResponseHeader

`McpHttpClientTestResponseHeader` models the response-header protocol consumed
by `McpHttpClientTransport`.

## Responsibilities

- Retain numeric status and optional content type.
- Retain arbitrary fields with case-insensitive lookup.
- Provide a diagnostic status string.

Instances are mutable fixtures owned by one test response. They perform no I/O
and are not safe for concurrent mutation.
"
Class {
	#name : 'McpHttpClientTestResponseHeader',
	#superclass : 'Object',
	#instVars : [
		'statusCode',
		'contentType',
		'fields'
	],
	#category : 'McpHttpClientTests'
}

{ #category : 'Instance Creation' }
McpHttpClientTestResponseHeader class >> new [
	"Answer a response header initialized with empty fields."

	^super new initialize
]

{ #category : 'Accessing' }
McpHttpClientTestResponseHeader >> at: fieldName ifAbsent: absentBlock [
	"Answer a field by case-insensitive name or evaluate absentBlock."

	| existingName |

	existingName := fields keys detect: [:name | name sameAs: fieldName] ifNone: [nil].
	^existingName ifNil: [absentBlock value] ifNotNil: [fields at: existingName]
]

{ #category : 'Accessing' }
McpHttpClientTestResponseHeader >> at: fieldName put: fieldValue [
	"Set a field after removing a case-insensitive duplicate."

	| existingName |

	existingName := fields keys detect: [:name | name sameAs: fieldName] ifNone: [nil].
	existingName ifNotNil: [fields removeKey: existingName].
	fields at: fieldName put: fieldValue.
	^fieldValue
]

{ #category : 'Accessing' }
McpHttpClientTestResponseHeader >> contentType [
	"Answer the configured response content type."

	^contentType
]

{ #category : 'Accessing' }
McpHttpClientTestResponseHeader >> contentType: aString [
	"Set the configured response content type."

	contentType := aString.
	^self
]

{ #category : 'Initialization',
  #vaVisibility : 'private' }
McpHttpClientTestResponseHeader >> initialize [
	"Initialize empty response fields."

	super initialize.
	fields := EsOrderedDictionary new.
	^self
]

{ #category : 'Fixtures' }
McpHttpClientTestResponseHeader >> location [
	"Answer the scripted Location header or nil.
	Answers:
		<String | nil> redirect URI reference."
	^self at: 'Location' ifAbsent: [nil]

]

{ #category : 'Formatting' }
McpHttpClientTestResponseHeader >> status [
	"Answer a diagnostic HTTP status string."

	^'HTTP ' , statusCode printString
]

{ #category : 'Accessing' }
McpHttpClientTestResponseHeader >> statusCode [
	"Answer the numeric HTTP status code."

	^statusCode
]

{ #category : 'Accessing' }
McpHttpClientTestResponseHeader >> statusCode: anInteger [
	"Set the numeric HTTP status code."

	statusCode := anInteger.
	^self
]
