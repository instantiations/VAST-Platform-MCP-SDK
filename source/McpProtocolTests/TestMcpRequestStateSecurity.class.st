Class {
	#name : 'TestMcpRequestStateSecurity',
	#superclass : 'TestCase',
	#instVars : [
		'security'
	],
	#pools : [
		'McpJsonRpcConstants'
	],
	#category : 'McpProtocolTests'
}

{ #category : 'Initialization' }
TestMcpRequestStateSecurity >> setUp [
	"Prepare request state security fixture.

	 Answers:
		<TestMcpRequestStateSecurity> the receiver."

	super setUp.
	security := McpRequestStateSecurity secretKey: 'test-secret-key-12345' ttlSeconds: 60.
	^self
]

{ #category : 'Testing' }
TestMcpRequestStateSecurity >> testArgumentsMismatchIsRejected [
	"A token replayed against modified arguments is rejected."

	| args differentArgs token |

	args := EsOrderedDictionary with: 'count' -> 42.
	differentArgs := EsOrderedDictionary with: 'count' -> 99.
	token :=
		security
			sealState: 'internal-state'
			method: 'tools/call'
			target: 'tool1'
			arguments: args
			principal: nil.
	self
		should: [
			security
				unsealState: token
				expectedMethod: 'tools/call'
				expectedTarget: 'tool1'
				arguments: differentArgs
				expectedPrincipal: nil]
		raise: McpJsonRpcError
]

{ #category : 'Testing' }
TestMcpRequestStateSecurity >> testExpiredTokenIsRejected [
	"A token past its TTL is rejected as expired."

	| expiredSecurity args token |

	expiredSecurity := McpRequestStateSecurity secretKey: 'exp-key' ttlSeconds: 1.
	args := EsOrderedDictionary new.
	token :=
		expiredSecurity
			sealState: 'expired-state'
			method: 'tools/call'
			target: 'tool1'
			arguments: args
			principal: nil.
	(Delay forMilliseconds: 1500) wait.
	self
		should: [
			expiredSecurity
				unsealState: token
				expectedMethod: 'tools/call'
				expectedTarget: 'tool1'
				arguments: args
				expectedPrincipal: nil]
		raise: McpJsonRpcError
]

{ #category : 'Testing' }
TestMcpRequestStateSecurity >> testMethodMismatchIsRejected [
	"A token replayed against a different method is rejected."

	| args token |

	args := EsOrderedDictionary with: 'count' -> 42.
	token :=
		security
			sealState: 'internal-state'
			method: 'tools/call'
			target: 'tool1'
			arguments: args
			principal: nil.
	self
		should: [
			security
				unsealState: token
				expectedMethod: 'prompts/get'
				expectedTarget: 'tool1'
				arguments: args
				expectedPrincipal: nil]
		raise: McpJsonRpcError
]

{ #category : 'Testing' }
TestMcpRequestStateSecurity >> testSealAndUnsealRoundTrip [
	"A sealed token unseals to its exact plaintext state."

	| args token unsealed |

	args := EsOrderedDictionary with: 'count' -> 42.
	token :=
		security
			sealState: 'internal-cursor-state'
			method: 'tools/call'
			target: 'calculator'
			arguments: args
			principal: 'user-bob'.
	self assert: (token includes: $.).
	unsealed :=
		security
			unsealState: token
			expectedMethod: 'tools/call'
			expectedTarget: 'calculator'
			arguments: args
			expectedPrincipal: 'user-bob'.
	self assert: unsealed equals: 'internal-cursor-state'
]

{ #category : 'Testing' }
TestMcpRequestStateSecurity >> testTamperedTokenIsRejected [
	"A token with modified signature or payload is rejected."

	| args token tampered |

	args := EsOrderedDictionary with: 'count' -> 42.
	token :=
		security
			sealState: 'internal-state'
			method: 'tools/call'
			target: 'tool1'
			arguments: args
			principal: nil.
	tampered := token copy.
	tampered at: tampered size put: $X.
	self
		should: [
			security
				unsealState: tampered
				expectedMethod: 'tools/call'
				expectedTarget: 'tool1'
				arguments: args
				expectedPrincipal: nil]
		raise: McpJsonRpcError
]

{ #category : 'Testing' }
TestMcpRequestStateSecurity >> testTargetMismatchIsRejected [
	"A token replayed against a different tool or prompt is rejected."

	| args token |

	args := EsOrderedDictionary with: 'count' -> 42.
	token :=
		security
			sealState: 'internal-state'
			method: 'tools/call'
			target: 'tool1'
			arguments: args
			principal: nil.
	self
		should: [
			security
				unsealState: token
				expectedMethod: 'tools/call'
				expectedTarget: 'otherTool'
				arguments: args
				expectedPrincipal: nil]
		raise: McpJsonRpcError
]
