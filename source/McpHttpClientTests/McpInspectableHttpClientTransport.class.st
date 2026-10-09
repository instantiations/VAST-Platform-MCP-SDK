"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# McpInspectableHttpClientTransport

`McpInspectableHttpClientTransport` injects a scripted HTTP collaborator into
the production Streamable HTTP transport.

## Responsibilities

- Preserve all production transport behavior under test.
- Replace only SST client construction with a deterministic fixture.
- Expose that fixture for assertions.

The owning test configures one endpoint and one scripted client. The subclass
adds no protocol behavior and is not used outside the offline test suite.
"
Class {
	#name : 'McpInspectableHttpClientTransport',
	#superclass : 'McpHttpClientTransport',
	#instVars : [
		'scriptedHttpClient'
	],
	#category : 'McpHttpClientTests'
}

{ #category : 'Test Support',
  #vaVisibility : 'private' }
McpInspectableHttpClientTransport >> configuredHttpClientFor: endpointUrl [
	"Answer the injected client without creating an SST connection."

	^scriptedHttpClient
]

{ #category : 'Initialization',
  #vaVisibility : 'private' }
McpInspectableHttpClientTransport >> initialize [
	"Initialize production state and a default scripted collaborator."

	super initialize.
	scriptedHttpClient := McpScriptedHttpClient new.
	^self
]

{ #category : 'Test Support' }
McpInspectableHttpClientTransport >> scriptedHttpClient [
	"Answer the injected scripted HTTP client."

	^scriptedHttpClient
]

{ #category : 'Test Support' }
McpInspectableHttpClientTransport >> scriptedHttpClient: aClient [
	"Set the scripted HTTP client returned during endpoint configuration."

	scriptedHttpClient := aClient.
	^self
]
