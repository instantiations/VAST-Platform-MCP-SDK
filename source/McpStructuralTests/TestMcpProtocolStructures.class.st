"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# TestMcpProtocolStructures

`TestMcpProtocolStructures` verifies stable MCP protocol metadata and
versioning invariants.

## Responsibilities

- Verify canonical JSON-RPC and MCP extension error codes.
- Verify client and server support selected protocol revisions in preference
  order (`2026-07-28`, `2025-11-25`, etc.).
- Verify server capabilities describe only implemented operations.
- Verify returned capability metadata is detached from server state.

## Test isolation

These tests inspect immutable constants and fresh server instances. They
perform no network I/O and make no timing assumptions.
"
Class {
	#name : 'TestMcpProtocolStructures',
	#superclass : 'TestCase',
	#category : 'McpStructuralTests'
}

{ #category : 'Protocol Constants' }
TestMcpProtocolStructures >> testCanonicalJsonRpcErrorCodes [
	"The standard JSON-RPC error constants use their canonical values."

	| constants |

	constants := Smalltalk at: #McpJsonRpcConstants.
	self assert: (constants at: 'McpJsonRpcParseErrorCode') equals: -32700.
	self assert: (constants at: 'McpJsonRpcInvalidRequestCode') equals: -32600.
	self assert: (constants at: 'McpJsonRpcMethodNotFoundCode') equals: -32601.
	self assert: (constants at: 'McpJsonRpcInvalidParamsCode') equals: -32602.
	self assert: (constants at: 'McpJsonRpcInternalErrorCode') equals: -32603
]

{ #category : 'Protocol Constants' }
TestMcpProtocolStructures >> testMcpExtensionErrorCodes [
	"MCP extension errors use the protocol-defined server range value."

	| constants |

	constants := Smalltalk at: #McpJsonRpcConstants.
	self assert: (constants at: 'McpHeaderMismatchErrorCode') equals: -32020.
	self assert: (constants at: 'McpMissingRequiredClientCapabilityErrorCode') equals: -32021.
	self assert: (constants at: 'McpUnsupportedProtocolVersionErrorCode') equals: -32022.
	self assert: (constants at: 'McpResourceNotFoundErrorCode') equals: -32602.
	self assert: (constants at: 'McpServerNotInitializedErrorCode') equals: -32002
]

{ #category : 'Protocol Constants' }
TestMcpProtocolStructures >> testSelectedProtocolRevisionIsSupportedByClientAndServer [
	"Client and server support the selected MCP revisions in preference order."

	self
		assert: McpClient supportedProtocolVersions
		equals: McpProtocolVersion supportedProtocolVersions.
	self
		assert: McpServer new supportedProtocolVersions
		equals: McpProtocolVersion supportedProtocolVersions
]

{ #category : 'Configuration' }
TestMcpProtocolStructures >> testServerCapabilitiesAreAccurateAndDetached [
	"Server capabilities advertise supported operations without mutation leaks."

	| server capabilities |

	server := McpServer new.
	capabilities := server capabilities.
	self assert: capabilities size equals: 4.
	self assert: (capabilities includesKey: 'tools').
	self assert: (capabilities includesKey: 'prompts').
	self assert: (capabilities includesKey: 'resources').
	self assert: (capabilities includesKey: 'completions').
	self assert: ((capabilities at: 'tools') at: 'listChanged') equals: false.
	self assert: ((capabilities at: 'prompts') at: 'listChanged') equals: false.
	self deny: ((capabilities at: 'resources') includesKey: 'subscribe').
	self deny: ((capabilities at: 'resources') includesKey: 'listChanged').
	capabilities removeKey: 'tools'.
	self assert: (server capabilities includesKey: 'tools')
]
