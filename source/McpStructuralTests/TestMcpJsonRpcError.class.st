"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# TestMcpJsonRpcError

`TestMcpJsonRpcError` verifies the structured JSON-RPC exception contract.

## Responsibilities

- Verify protocol code, message, and optional data preservation.
- Verify mutable protocol data is isolated at both access boundaries.
- Verify construction rejects malformed or cyclic protocol values.

Tests handle and resume signaled protocol errors explicitly. Each test owns
all mutable data and performs no external I/O.
"
Class {
	#name : 'TestMcpJsonRpcError',
	#superclass : 'TestCase',
	#category : 'McpStructuralTests'
}

{ #category : 'Protocol Errors' }
TestMcpJsonRpcError >> testDataMayBeNil [
	"Protocol error data is optional."

	| captured |

	captured := nil.
	[McpJsonRpcError signalCode: -32000 message: 'Optional data' data: nil]
		on: McpJsonRpcError
		do: [:error |
			captured := error.
			error return].
	self assert: captured notNil.
	self assert: captured data equals: nil
]

{ #category : 'Validation' }
TestMcpJsonRpcError >> testDataRejectsCyclicValues [
	"Error data must be serializable without object cycles."

	| cyclic |

	cyclic := Array new: 1.
	cyclic at: 1 put: cyclic.
	self should: [McpJsonRpcError new data: cyclic] raise: Error
]

{ #category : 'Protocol Errors' }
TestMcpJsonRpcError >> testSignalPreservesFieldsAndDetachesData [
	"A signaled error preserves fields and isolates mutable protocol data."

	| source nested captured returned |

	nested := EsOrderedDictionary with: 'uri' -> 'test://missing'.
	source := EsOrderedDictionary with: 'details' -> nested.
	captured := nil.
	[McpJsonRpcError signalCode: -32602 message: 'Resource not found' data: source]
		on: McpJsonRpcError
		do: [:error |
			captured := error.
			error return].
	nested at: 'uri' put: 'changed'.
	self assert: captured code equals: -32602.
	self assert: captured messageText equals: 'Resource not found'.
	returned := captured data.
	self assert: ((returned at: 'details') at: 'uri') equals: 'test://missing'.
	(returned at: 'details') at: 'uri' put: 'returned change'.
	self assert: ((captured data at: 'details') at: 'uri') equals: 'test://missing'
]

{ #category : 'Validation' }
TestMcpJsonRpcError >> testSignalRejectsMalformedCodeAndMessage [
	"Signaling requires an integer code and a nonempty message."

	self should: [McpJsonRpcError signalCode: 'invalid' message: 'message' data: nil] raise: Error.
	self should: [McpJsonRpcError signalCode: -32000 message: '' data: nil] raise: Error
]
