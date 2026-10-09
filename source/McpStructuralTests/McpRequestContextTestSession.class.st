"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# McpRequestContextTestSession

`McpRequestContextTestSession` supplies the session protocol required by an
`McpServerRequestContext` without depending on an HTTP transport session.

## Responsibilities

- Retain an opaque session identifier and negotiated protocol version.
- Expose client information and capabilities to request-context tests.
- Permit each test to configure an isolated session fixture.

Instances are mutable test fixtures, own their assigned values, perform no
I/O, and are not safe for concurrent mutation.
"
Class {
	#name : 'McpRequestContextTestSession',
	#superclass : 'Object',
	#instVars : [
		'identifier',
		'protocolVersion',
		'clientInfo',
		'clientCapabilities'
	],
	#category : 'McpStructuralTests'
}

{ #category : 'Accessing' }
McpRequestContextTestSession >> clientCapabilities [
	"Answer the configured client capabilities."

	^clientCapabilities
]

{ #category : 'Accessing' }
McpRequestContextTestSession >> clientCapabilities: aDictionary [
	"Set the configured client capabilities."

	clientCapabilities := aDictionary.
	^self
]

{ #category : 'Accessing' }
McpRequestContextTestSession >> clientInfo [
	"Answer the configured client implementation information."

	^clientInfo
]

{ #category : 'Accessing' }
McpRequestContextTestSession >> clientInfo: aDictionary [
	"Set the configured client implementation information."

	clientInfo := aDictionary.
	^self
]

{ #category : 'Accessing' }
McpRequestContextTestSession >> id [
	"Answer the opaque session identifier."

	^identifier
]

{ #category : 'Accessing' }
McpRequestContextTestSession >> id: aString [
	"Set the opaque session identifier."

	identifier := aString.
	^self
]

{ #category : 'Accessing' }
McpRequestContextTestSession >> protocolVersion [
	"Answer the negotiated protocol version."

	^protocolVersion
]

{ #category : 'Accessing' }
McpRequestContextTestSession >> protocolVersion: aString [
	"Set the negotiated protocol version."

	protocolVersion := aString.
	^self
]
