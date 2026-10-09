"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# TestMcpProtocolVersion

`TestMcpProtocolVersion` verifies MCP protocol version categorization, era
classification, and ordering logic.

## Responsibilities

- Verify known protocol version registries and era memberships.
- Verify Handshake Era (<= `2025-11-25`) and Modern Era (>= `2026-07-28`)
  boundaries.
- Verify preference ordering and newest-first supported version resolution.
- Verify chronological comparison helpers (`isVersion:atLeast:`,
  `isVersion:atMost:`).

## Test isolation

These tests inspect pure class-side version logic. They perform no network I/O,
create no processes, and make no timing assumptions.
"
Class {
	#name : 'TestMcpProtocolVersion',
	#superclass : 'TestCase',
	#category : 'McpStructuralTests'
}

{ #category : 'Testing' }
TestMcpProtocolVersion >> testIsModernAndIsHandshakeClassification [
	"Era classification works for past, present, and future revisions."

	self assert: (McpProtocolVersion isHandshake: '2024-11-05').
	self assert: (McpProtocolVersion isHandshake: '2025-03-26').
	self assert: (McpProtocolVersion isHandshake: '2025-11-25').
	self deny: (McpProtocolVersion isModern: '2024-11-05').
	self deny: (McpProtocolVersion isModern: '2025-11-25').

	self assert: (McpProtocolVersion isModern: '2026-07-28').
	self assert: (McpProtocolVersion isModern: '2026-11-15').
	self assert: (McpProtocolVersion isModern: '2027-01-01').
	self deny: (McpProtocolVersion isHandshake: '2026-07-28').
	self deny: (McpProtocolVersion isHandshake: '2027-01-01').

	self deny: (McpProtocolVersion isModern: nil).
	self deny: (McpProtocolVersion isHandshake: nil).
	self deny: (McpProtocolVersion isModern: '').
	self deny: (McpProtocolVersion isHandshake: '')
]

{ #category : 'Testing' }
TestMcpProtocolVersion >> testKnownAndHandshakeAndModernVersions [
	"Version registry categorizes protocol eras correctly."

	self assert: (McpProtocolVersion knownProtocolVersions includes: '2024-11-05').
	self assert: (McpProtocolVersion knownProtocolVersions includes: '2025-11-25').
	self assert: (McpProtocolVersion knownProtocolVersions includes: '2026-07-28').
	self assert: (McpProtocolVersion handshakeProtocolVersions includes: '2024-11-05').
	self assert: (McpProtocolVersion handshakeProtocolVersions includes: '2025-11-25').
	self deny: (McpProtocolVersion handshakeProtocolVersions includes: '2026-07-28').
	self assert: (McpProtocolVersion modernProtocolVersions includes: '2026-07-28').
	self deny: (McpProtocolVersion modernProtocolVersions includes: '2025-11-25').
	self assert: McpProtocolVersion latestHandshakeVersion equals: '2025-11-25'.
	self assert: McpProtocolVersion latestModernVersion equals: '2026-07-28'.
	self assert: McpProtocolVersion latestProtocolVersion equals: '2026-07-28'
]

{ #category : 'Testing' }
TestMcpProtocolVersion >> testVersionComparisonOrdering [
	"Version comparison handles chronological and atLeast/atMost boundaries."

	self assert: (McpProtocolVersion isVersion: '2026-07-28' atLeast: '2025-11-25').
	self assert: (McpProtocolVersion isVersion: '2026-07-28' atLeast: '2026-07-28').
	self deny: (McpProtocolVersion isVersion: '2025-11-25' atLeast: '2026-07-28').
	self assert: (McpProtocolVersion isVersion: '2025-11-25' atMost: '2026-07-28').
	self assert: (McpProtocolVersion isVersion: '2025-03-26' atMost: '2025-11-25').
	self deny: (McpProtocolVersion isVersion: '2026-07-28' atMost: '2025-11-25')
]
