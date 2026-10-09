"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# TestMcpServerRequestContext

`TestMcpServerRequestContext` verifies request-scoped server state.

## Responsibilities

- Verify delegation to the established transport session.
- Verify session protocol validation.
- Verify request metadata ownership and reset behavior.
- Verify principal and transport-request retention.
- Verify required state before a context crosses the server boundary.

Each test creates a fresh context and transport-neutral session fixture.
Instances are mutable and confined to one test process.
"
Class {
	#name : 'TestMcpServerRequestContext',
	#superclass : 'TestCase',
	#instVars : [
		'context',
		'session'
	],
	#category : 'McpStructuralTests'
}

{ #category : 'Initialization' }
TestMcpServerRequestContext >> setUp [
	"Create an isolated request context and session fixture."

	super setUp.
	session :=
		McpRequestContextTestSession new
			id: 'session-42';
			protocolVersion: '2025-11-25';
			clientInfo:
				(EsOrderedDictionary with: 'name' -> 'StructuralClient' with: 'version' -> '1.0.0');
			clientCapabilities: (EsOrderedDictionary with: 'sampling' -> EsOrderedDictionary new);
			yourself.
	context := McpServerRequestContext new
]

{ #category : 'Accessing' }
TestMcpServerRequestContext >> testAccessorsRetainPrincipalAndTransportRequest [
	"Security and transport layers may attach request-scoped collaborators."

	| principal transportRequest |

	principal := Object new.
	transportRequest := Object new.
	context
		principal: principal;
		transportRequest: transportRequest.
	self assert: context principal == principal.
	self assert: context transportRequest == transportRequest
]

{ #category : 'Accessing' }
TestMcpServerRequestContext >> testLogLevelAndCanEmitLog [
	"Verify logLevel accessor and canEmitLog predicate per SEP-2575."

	| testContext |

	testContext := McpServerRequestContext new.
	self assert: testContext logLevel isNil.
	self deny: testContext canEmitLog.

	testContext logLevel: 'info'.
	self assert: testContext logLevel equals: 'info'.
	self assert: testContext canEmitLog
]

{ #category : 'Copying' }
TestMcpServerRequestContext >> testMetadataIsIndependentAndCopiesAssignedStructure [
	"Each context owns its metadata dictionary and copies assigned structure."

	| other source |

	other := McpServerRequestContext new.
	context metadata at: 'request' put: 'first'.
	self assert: other metadata isEmpty.
	source := EsOrderedDictionary with: 'trace' -> 'trace-1'.
	context metadata: source.
	source at: 'trace' put: 'changed'.
	self assert: (context metadata at: 'trace') equals: 'trace-1'
]

{ #category : 'Initialization' }
TestMcpServerRequestContext >> testMetadataNilResetsToEmptyDictionary [
	"Assigning nil clears request metadata to a usable empty dictionary."

	context metadata at: 'request' put: 'value'.
	context metadata: nil.
	self assert: context metadata isEmpty.
	context metadata at: 'replacement' put: true.
	self assert: (context metadata at: 'replacement') equals: true
]

{ #category : 'Session Management' }
TestMcpServerRequestContext >> testSessionAccessorsDelegateToConfiguredSession [
	"Context session accessors expose negotiated transport state."

	context session: session.
	self assert: context session == session.
	self assert: context sessionId equals: 'session-42'.
	self assert: context protocolVersion equals: '2025-11-25'.
	self assert: (context clientInfo at: 'name') equals: 'StructuralClient'.
	self assert: (context clientCapabilities includesKey: 'sampling')
]

{ #category : 'Validation' }
TestMcpServerRequestContext >> testSessionRejectsMissingProtocol [
	"A session must implement every request-context collaboration."

	self should: [context session: Object new] raise: Error.
	self assert: context session equals: nil
]

{ #category : 'Validation' }
TestMcpServerRequestContext >> testValidateRequiresSessionAndTransportRequest [
	"Validation requires both established session and transport request."

	| request |

	request := Object new.
	self should: [context validate] raise: Error.
	context session: session.
	self should: [context validate] raise: Error.
	context transportRequest: request.
	self assert: context validate == context
]
