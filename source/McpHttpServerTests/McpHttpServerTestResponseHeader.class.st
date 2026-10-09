"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# McpHttpServerTestResponseHeader

`McpHttpServerTestResponseHeader` records an offline HTTP response header.

## Responsibilities

- Retain status, media type, content length, and arbitrary response fields.
- Provide case-insensitive field lookup for protocol assertions.

Each test request owns one mutable instance. The fixture performs no I/O and
is not shared across tests or concurrent processes.
"
Class {
	#name : 'McpHttpServerTestResponseHeader',
	#superclass : 'Object',
	#instVars : [
		'status',
		'contentLength',
		'contentType',
		'fields'
	],
	#category : 'McpHttpServerTests'
}

{ #category : 'Instance Creation' }
McpHttpServerTestResponseHeader class >> new [
	"Answer an initialized empty response header."

	^super new initialize
]

{ #category : 'Accessing' }
McpHttpServerTestResponseHeader >> at: fieldName [
	"Answer a response field by case-insensitive name, or nil if absent.

	 Arguments:
		fieldName - <String>.
	 Answers:
		<String> or nil."

	^self at: fieldName ifAbsent: [nil]
]

{ #category : 'Accessing' }
McpHttpServerTestResponseHeader >> at: fieldName ifAbsent: absentBlock [
	"Answer a response field by case-insensitive name."

	| existingName |

	existingName := fields keys detect: [:name | name sameAs: fieldName] ifNone: [nil].
	^existingName ifNil: [absentBlock value] ifNotNil: [fields at: existingName]
]

{ #category : 'Accessing' }
McpHttpServerTestResponseHeader >> at: fieldName put: fieldValue [
	"Set a response field after removing a case-insensitive duplicate."

	| existingName |

	existingName := fields keys detect: [:name | name sameAs: fieldName] ifNone: [nil].
	existingName ifNotNil: [fields removeKey: existingName].
	fields at: fieldName put: fieldValue.
	^fieldValue
]

{ #category : 'Accessing' }
McpHttpServerTestResponseHeader >> contentLength [
	"Answer the configured response entity length."

	^contentLength
]

{ #category : 'Accessing' }
McpHttpServerTestResponseHeader >> contentLength: byteCount [
	"Set the response entity length."

	contentLength := byteCount.
	^self
]

{ #category : 'Accessing' }
McpHttpServerTestResponseHeader >> contentType [
	"Answer the configured response media type."

	^contentType
]

{ #category : 'Accessing' }
McpHttpServerTestResponseHeader >> contentType: mediaType [
	"Set the response media type."

	contentType := mediaType.
	^self
]

{ #category : 'Initialization',
  #vaVisibility : 'private' }
McpHttpServerTestResponseHeader >> initialize [
	"Initialize empty response fields."

	super initialize.
	fields := EsOrderedDictionary new.
	^self
]

{ #category : 'Accessing' }
McpHttpServerTestResponseHeader >> status [
	"Answer the configured HTTP status string."

	^status
]

{ #category : 'Accessing' }
McpHttpServerTestResponseHeader >> status: statusString [
	"Set the HTTP status string."

	status := statusString.
	^self
]
