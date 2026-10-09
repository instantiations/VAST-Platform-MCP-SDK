"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# McpHttpServerTestRequestHeader

`McpHttpServerTestRequestHeader` supplies the response-header collaboration
expected by the production HTTP transport.

Each request owns one response header for its complete lifecycle. The fixture
contains no network or servlet-engine behavior.
"
Class {
	#name : 'McpHttpServerTestRequestHeader',
	#superclass : 'Object',
	#instVars : [
		'responseHeader'
	],
	#category : 'McpHttpServerTests'
}

{ #category : 'Instance Creation' }
McpHttpServerTestRequestHeader class >> new [
	"Answer a request header with a writable response header."

	^super new initialize
]

{ #category : 'Initialization',
  #vaVisibility : 'private' }
McpHttpServerTestRequestHeader >> initialize [
	"Initialize a fresh response header."

	super initialize.
	responseHeader := McpHttpServerTestResponseHeader new.
	^self
]

{ #category : 'Accessing' }
McpHttpServerTestRequestHeader >> responseHeader [
	"Answer the response header paired with this request."

	^responseHeader
]
