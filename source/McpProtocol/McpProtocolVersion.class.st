"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# McpProtocolVersion

`McpProtocolVersion` is the central authority and registry for Model Context
Protocol (MCP) versions and era classification.

## Responsibilities

- Maintain the chronological registry of known MCP revisions (`2024-11-05`,
  `2025-03-26`, `2025-06-18`, `2025-11-25`, `2026-07-28`).
- Classify protocol versions into the Handshake Era (<= `2025-11-25`) and the
  Modern Era (>= `2026-07-28`).
- Provide preference-ordered supported version lists for client and server
  negotiation.
- Perform forward-compatible chronological and boundary comparisons
  (`isVersion:atLeast:`, `isModern:`, `isHandshake:`).

## Lifecycle and boundaries

`McpProtocolVersion` is a stateless class-side utility. Transports,
dispatchers, clients, and servers query it rather than hardcoding protocol date
strings, ensuring future protocol revisions can be integrated without
architectural changes.
"
Class {
	#name : 'McpProtocolVersion',
	#superclass : 'Object',
	#category : 'McpProtocol'
}

{ #category : 'Accessing' }
McpProtocolVersion class >> handshakeProtocolVersions [
	"Answer all protocol versions negotiated via the legacy initialize handshake in preference order (newest first).

	 Answers:
		<Array> of <String>."

	^#('2025-11-25' '2025-06-18' '2025-03-26' '2024-11-05')
]

{ #category : 'Testing' }
McpProtocolVersion class >> isHandshake: aVersionString [
	"Answer whether aVersionString belongs to the handshake era (<= 2025-11-25).
	 Handshake-era connections open with an initialize request and maintain session state.

	 Arguments:
		aVersionString - <String> or nil.
	 Answers:
		<Boolean>."

	(aVersionString isString and: [aVersionString isEmpty not]) ifFalse: [^false].
	^self isVersion: aVersionString atMost: '2025-11-25'
]

{ #category : 'Testing' }
McpProtocolVersion class >> isModern: aVersionString [
	"Answer whether aVersionString belongs to the modern (2026-07-28+) protocol era.
	 Modern protocol versions use sessionless/stateless HTTP, mandatory per-request
	 _meta envelopes, and server/discover.

	 Arguments:
		aVersionString - <String> or nil.
	 Answers:
		<Boolean>."

	(aVersionString isString and: [aVersionString isEmpty not]) ifFalse: [^false].
	(self modernProtocolVersions includes: aVersionString) ifTrue: [^true].
	^self isVersion: aVersionString atLeast: '2026-07-28'
]

{ #category : 'Testing' }
McpProtocolVersion class >> isVersion: aVersionString atLeast: aMinimumVersionString [
	"Answer whether aVersionString is at least as new as aMinimumVersionString.
	 Uses index comparison for known versions, or lexicographical comparison for ISO date-based strings.

	 Arguments:
		aVersionString - <String>.
		aMinimumVersionString - <String>.
	 Answers:
		<Boolean>."

	| known |

	(aVersionString isString and: [aMinimumVersionString isString]) ifFalse: [^false].
	known := self knownProtocolVersions.
	((known includes: aVersionString) and: [known includes: aMinimumVersionString])
		ifTrue: [^(known indexOf: aVersionString) >= (known indexOf: aMinimumVersionString)].
	^aVersionString >= aMinimumVersionString
]

{ #category : 'Testing' }
McpProtocolVersion class >> isVersion: aVersionString atMost: aMaximumVersionString [
	"Answer whether aVersionString is at most as new as aMaximumVersionString.

	 Arguments:
		aVersionString - <String>.
		aMaximumVersionString - <String>.
	 Answers:
		<Boolean>."

	| known |

	(aVersionString isString and: [aMaximumVersionString isString]) ifFalse: [^false].
	known := self knownProtocolVersions.
	((known includes: aVersionString) and: [known includes: aMaximumVersionString])
		ifTrue: [^(known indexOf: aVersionString) <= (known indexOf: aMaximumVersionString)].
	^aVersionString <= aMaximumVersionString
]

{ #category : 'Accessing' }
McpProtocolVersion class >> knownProtocolVersions [
	"Answer all released MCP protocol revisions in chronological order.

	 Answers:
		<Array> of <String>."

	^#('2024-11-05' '2025-03-26' '2025-06-18' '2025-11-25' '2026-07-28')
]

{ #category : 'Accessing' }
McpProtocolVersion class >> latestHandshakeVersion [
	"Answer the newest protocol revision reachable via the initialize handshake.

	 Answers:
		<String>."

	^self handshakeProtocolVersions first
]

{ #category : 'Accessing' }
McpProtocolVersion class >> latestModernVersion [
	"Answer the newest modern protocol revision.

	 Answers:
		<String>."

	^self modernProtocolVersions last
]

{ #category : 'Accessing' }
McpProtocolVersion class >> latestProtocolVersion [
	"Answer the newest protocol revision this framework speaks (any era).

	 Answers:
		<String>."

	^self modernProtocolVersions last
]

{ #category : 'Accessing' }
McpProtocolVersion class >> modernProtocolVersions [
	"Answer modern protocol revisions using the sessionless discover and _meta envelope architecture.

	 Answers:
		<Array> of <String>."

	^#('2026-07-28')
]

{ #category : 'Accessing' }
McpProtocolVersion class >> supportedProtocolVersions [
	"Answer all supported protocol versions in preference order (newest first).

	 Answers:
		<Array> of <String>."

	^#('2026-07-28' '2025-11-25' '2025-06-18' '2025-03-26' '2024-11-05')
]
