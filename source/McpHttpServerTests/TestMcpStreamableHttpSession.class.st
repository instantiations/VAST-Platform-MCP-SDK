"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# TestMcpStreamableHttpSession

`TestMcpStreamableHttpSession` verifies server-side MCP session state.

## Responsibilities

- Verify immutable identity and negotiated protocol version.
- Verify the initializing-to-ready lifecycle invariant.
- Verify deep snapshot isolation for negotiated client metadata.
- Verify rejection of invalid or cyclic metadata.

Sessions are exercised directly without HTTP, shared state, scheduling, or
network I/O.
"
Class {
	#name : 'TestMcpStreamableHttpSession',
	#superclass : 'TestCase',
	#category : 'McpHttpServerTests'
}

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpStreamableHttpSession >> newSession [
	"Answer one session with valid empty negotiated metadata."

	^McpStreamableHttpSession
		id: 'session-1'
		protocolVersion: '2025-11-25'
		clientInfo: EsOrderedDictionary new
		capabilities: EsOrderedDictionary new
]

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpStreamableHttpSession >> sessionWithInfo: information [
	"Answer one session using information as negotiated client metadata."

	^McpStreamableHttpSession
		id: 'session-1'
		protocolVersion: '2025-11-25'
		clientInfo: information
		capabilities: EsOrderedDictionary new
]

{ #category : 'Instance Creation' }
TestMcpStreamableHttpSession >> testCompatibilityFactoryUsesEmptyMetadata [
	"The compatibility factory supplies empty client metadata."

	| session |

	session := McpStreamableHttpSession id: 'session-1' protocolVersion: '2025-11-25'.
	self assert: session clientInfo isEmpty.
	self assert: session clientCapabilities isEmpty
]

{ #category : 'Copying' }
TestMcpStreamableHttpSession >> testIdentityAndProtocolVersionAreDetached [
	"Session identity and protocol version are retained by value."

	| identifier version session returnedIdentifier returnedVersion |

	identifier := 'session-1' copy.
	version := '2025-11-25' copy.
	session := McpStreamableHttpSession id: identifier protocolVersion: version.
	identifier at: 1 put: $X.
	version at: 1 put: $X.
	self assert: session id equals: 'session-1'.
	self assert: session protocolVersion equals: '2025-11-25'.
	returnedIdentifier := session id.
	returnedVersion := session protocolVersion.
	returnedIdentifier at: 1 put: $Y.
	returnedVersion at: 1 put: $Y.
	self assert: session id equals: 'session-1'.
	self assert: session protocolVersion equals: '2025-11-25'
]

{ #category : 'Session Management' }
TestMcpStreamableHttpSession >> testInitialStateAndReadyTransition [
	"A session transitions from initializing to ready exactly once."

	| session |

	session := self newSession.
	self assert: session state equals: #initializing.
	self assert: session isInitializing.
	self deny: session isReady.
	self assert: session markReady == session.
	self assert: session state equals: #ready.
	self deny: session isInitializing.
	self assert: session isReady.
	self should: [session markReady] raise: Error
]

{ #category : 'Validation' }
TestMcpStreamableHttpSession >> testInvalidIdentityAndMetadataAreRejected [
	"Factories validate identity, version, and keyed metadata."

	self should: [McpStreamableHttpSession id: '' protocolVersion: '2025-11-25'] raise: Error.
	self should: [McpStreamableHttpSession id: 1 protocolVersion: '2025-11-25'] raise: Error.
	self should: [McpStreamableHttpSession id: 'session-1' protocolVersion: ''] raise: Error.
	self
		should: [
			McpStreamableHttpSession
				id: 'session-1'
				protocolVersion: '2025-11-25'
				clientInfo: #()
				capabilities: EsOrderedDictionary new]
		raise: Error.
	self
		should: [
			McpStreamableHttpSession
				id: 'session-1'
				protocolVersion: '2025-11-25'
				clientInfo: EsOrderedDictionary new
				capabilities: #()]
		raise: Error
]

{ #category : 'Copying' }
TestMcpStreamableHttpSession >> testMetadataIsDeeplyDetached [
	"Negotiated client metadata is isolated on assignment and access."

	| name tags information capabilities session snapshot returnedTags |

	name := 'client-one' copy.
	tags := OrderedCollection with: 'first'.
	information :=
		EsOrderedDictionary new
			at: 'name' put: name;
			at: 'tags' put: tags;
			yourself.
	capabilities := EsOrderedDictionary with: 'sampling' -> EsOrderedDictionary new.
	session :=
		McpStreamableHttpSession
			id: 'session-1'
			protocolVersion: '2025-11-25'
			clientInfo: information
			capabilities: capabilities.
	name at: 1 put: $X.
	tags add: 'later'.
	information at: 'extra' put: true.
	capabilities at: 'roots' put: EsOrderedDictionary new.
	snapshot := session clientInfo.
	self assert: (snapshot at: 'name') equals: 'client-one'.
	self assert: (snapshot at: 'tags') equals: #('first').
	self deny: (snapshot includesKey: 'extra').
	self deny: (session clientCapabilities includesKey: 'roots').
	returnedTags := snapshot at: 'tags'.
	returnedTags at: 1 put: 'changed'.
	snapshot at: 'name' put: 'changed'.
	self assert: (session clientInfo at: 'name') equals: 'client-one'.
	self assert: (session clientInfo at: 'tags') equals: #('first')
]

{ #category : 'Validation' }
TestMcpStreamableHttpSession >> testMetadataRejectsCyclesAndUnsupportedValues [
	"Session metadata must be finite JSON-compatible data."

	| cyclic invalidKey unsupported |

	cyclic := EsOrderedDictionary new.
	cyclic at: 'self' put: cyclic.
	invalidKey := EsOrderedDictionary with: 1 -> 'value'.
	unsupported := EsOrderedDictionary with: 'object' -> Object new.
	self should: [self sessionWithInfo: cyclic] raise: Error.
	self should: [self sessionWithInfo: invalidKey] raise: Error.
	self should: [self sessionWithInfo: unsupported] raise: Error
]

{ #category : 'Serialization' }
TestMcpStreamableHttpSession >> testUnicodeMetadataStringsAreAccepted [
	"Unicode strings are valid JSON metadata strings."

	| unicode session |

	unicode := UnicodeString with: (Grapheme value: 16r03BB).
	session := self sessionWithInfo: (EsOrderedDictionary with: 'name' -> unicode).
	self assert: (session clientInfo at: 'name') equals: unicode
]
