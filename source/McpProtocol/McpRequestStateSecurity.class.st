"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# McpRequestStateSecurity

`McpRequestStateSecurity` protects the integrity and confidentiality of the
multi-round-trip `requestState` token (SEP-2577).

## Responsibilities

- Seal outgoing `requestState` tokens with cryptographic HMAC-SHA256 signatures,
  binding them to the originating method, target name/URI, canonical arguments
  digest, authenticated principal, and expiration timestamp.
- Unseal and verify inbound client-echoed `requestState` tokens, rejecting
  tampered, expired, or replayed tokens with code -32602.
- Generate and manage process-local secret keys by default or use configured
  keys for multi-instance deployments.

## Lifecycle and boundaries

Owned by an `McpServer`. Tokens minted by this instance expire after the
configured TTL.
"
Class {
	#name : 'McpRequestStateSecurity',
	#superclass : 'Object',
	#instVars : [
		'secretKey',
		'ttlSeconds'
	],
	#pools : [
		'McpJsonRpcConstants'
	],
	#category : 'McpProtocol'
}

{ #category : 'Instance Creation' }
McpRequestStateSecurity class >> new [
	"Answer a new initialized request-state security manager.

	 Answers:
		<McpRequestStateSecurity>."

	^super new initialize
]

{ #category : 'Instance Creation' }
McpRequestStateSecurity class >> secretKey: aKey [
	"Answer a new security boundary using the specified secret key.

	 Arguments:
		aKey - <String> HMAC secret key.
	 Answers:
		<McpRequestStateSecurity>."

	^self new secretKey: aKey
]

{ #category : 'Instance Creation' }
McpRequestStateSecurity class >> secretKey: aKey ttlSeconds: anInteger [
	"Answer a new security boundary using the specified secret key and TTL in seconds.

	 Arguments:
		aKey - <String> HMAC secret key.
		anInteger - <Integer> time-to-live in seconds.
	 Answers:
		<McpRequestStateSecurity>."

	^self new
		secretKey: aKey;
		ttlSeconds: anInteger;
		yourself
]

{ #category : 'Validation' }
McpRequestStateSecurity >> digestForArguments: anArgumentsObject [
	"Answer a deterministic SHA-256 hex digest of the tool or prompt arguments.

	 Arguments:
		anArgumentsObject - <Object> arguments map or collection.
	 Answers:
		<String> hex digest."

	| canonicalJson |

	canonicalJson :=
		(anArgumentsObject isNil
			or: [(anArgumentsObject respondsTo: 'isEmpty') and: [anArgumentsObject isEmpty]])
				ifTrue: ['{}']
				ifFalse: [JcsCanonicalizer canonicalStringFor: anArgumentsObject].
	^(OSSslDigest sha256) printableDigest: canonicalJson asUtf8Bytes
]

{ #category : 'Initialization',
  #vaVisibility : 'private' }
McpRequestStateSecurity >> initialize [
	"Initialize random process-local secret key and default 15-minute TTL.

	 Answers:
		<McpRequestStateSecurity> the receiver."

	super initialize.
	secretKey := (Base64Coder current encode: (OSSslRandom randomBytes: 32)) asString.
	ttlSeconds := 900.
	^self
]

{ #category : 'Protocol Operations' }
McpRequestStateSecurity >> sealState: aStateString
	method: aMethodName
	target: aTargetName
	arguments: anArguments
	principal: aPrincipal [
	"Seal an internal state string into a tamper-proof signed token.

	 Arguments:
		aStateString - <String> plaintext state to protect.
		aMethodName - <String> originating MCP method name (e.g., tools/call).
		aTargetName - <String> tool name, prompt name, or resource URI.
		anArguments - <Object> or nil, arguments for the call.
		aPrincipal - <Object> or nil, authenticated principal.
	 Answers:
		<String> sealed base64 token."

	| now claims payloadJson signature b64Payload |

	now := Time totalSeconds.
	claims :=
		EsOrderedDictionary new
			at: 'v' put: 1;
			at: 'iat' put: now;
			at: 'exp' put: now + self ttlSeconds;
			at: 'm' put: aMethodName;
			at: 't' put: aTargetName;
			at: 'a' put: (self digestForArguments: anArguments);
			at: 's' put: (aStateString ifNil: ['']);
			yourself.
	aPrincipal ifNotNil: [claims at: 'p' put: aPrincipal asString].
	payloadJson := JcsCanonicalizer canonicalStringFor: claims.
	signature :=
		(OSSslDigest sha256)
			hmacPrintableDigest: payloadJson asUtf8Bytes
			key: self secretKey asUtf8Bytes.
	b64Payload := (Base64Coder current encode: payloadJson asUtf8Bytes) asString.
	^b64Payload , '.' , signature
]

{ #category : 'Accessing' }
McpRequestStateSecurity >> secretKey [
	"Answer the HMAC secret key.

	 Answers:
		<String>."

	^secretKey
]

{ #category : 'Accessing' }
McpRequestStateSecurity >> secretKey: aKey [
	"Set the HMAC secret key.

	 Arguments:
		aKey - <String>.
	 Answers:
		<McpRequestStateSecurity> the receiver."

	(aKey isString and: [aKey isEmpty not])
		ifFalse: [self error: 'Secret key must be a nonempty string'].
	secretKey := aKey.
	^self
]

{ #category : 'Accessing' }
McpRequestStateSecurity >> ttlSeconds [
	"Answer the token time-to-live in seconds.

	 Answers:
		<Integer>."

	^ttlSeconds
]

{ #category : 'Accessing' }
McpRequestStateSecurity >> ttlSeconds: anInteger [
	"Set the token time-to-live in seconds.

	 Arguments:
		anInteger - <Integer> positive duration.
	 Answers:
		<McpRequestStateSecurity> the receiver."

	(anInteger isInteger and: [anInteger > 0])
		ifFalse: [self error: 'TTL must be a positive integer'].
	ttlSeconds := anInteger.
	^self
]

{ #category : 'Protocol Operations' }
McpRequestStateSecurity >> unsealState: aTokenString
	expectedMethod: aMethodName
	expectedTarget: aTargetName
	arguments: anArguments
	expectedPrincipal: aPrincipal [
	"Verify and unseal a client-echoed requestState token.

	 Arguments:
		aTokenString - <String> sealed token.
		aMethodName - <String> expected method name.
		aTargetName - <String> expected tool/prompt name or resource URI.
		anArguments - <Object> or nil, arguments on the retry call.
		aPrincipal - <Object> or nil, authenticated principal on the retry.
	 Answers:
		<String> original plaintext state string."

	| dotIndex b64Payload signature payloadBytes payloadJson expectedSignature claims now |

	(aTokenString isString and: [aTokenString isEmpty not])
		ifFalse: [
			McpJsonRpcError
				signalCode: McpJsonRpcInvalidParamsCode
				message: 'Invalid or expired requestState'
				data: nil].
	dotIndex := aTokenString indexOf: $..
	dotIndex <= 1
		ifTrue: [
			McpJsonRpcError
				signalCode: McpJsonRpcInvalidParamsCode
				message: 'Invalid or expired requestState'
				data: nil].
	b64Payload := aTokenString copyFrom: 1 to: dotIndex - 1.
	signature := aTokenString copyFrom: dotIndex + 1 to: aTokenString size.
	payloadBytes :=
		[Base64Coder current decodeAsByteArray: b64Payload]
			on: Error
			do: [:e |
				McpJsonRpcError
					signalCode: McpJsonRpcInvalidParamsCode
					message: 'Invalid or expired requestState'
					data: nil].
	payloadJson := (UnicodeString utf8: payloadBytes) asString.
	expectedSignature :=
		(OSSslDigest sha256)
			hmacPrintableDigest: payloadJson asUtf8Bytes
			key: self secretKey asUtf8Bytes.
	signature = expectedSignature
		ifFalse: [
			McpJsonRpcError
				signalCode: McpJsonRpcInvalidParamsCode
				message: 'Invalid or expired requestState'
				data: nil].
	claims :=
		[McpJSONReader fromString: payloadJson]
			on: Error
			do: [:e |
				McpJsonRpcError
					signalCode: McpJsonRpcInvalidParamsCode
					message: 'Invalid or expired requestState'
					data: nil].
	now := Time totalSeconds.
	(claims at: 'exp' ifAbsent: [0]) <= now
		ifTrue: [
			McpJsonRpcError
				signalCode: McpJsonRpcInvalidParamsCode
				message: 'Invalid or expired requestState'
				data: nil].
	(claims at: 'm' ifAbsent: ['']) = aMethodName
		ifFalse: [
			McpJsonRpcError
				signalCode: McpJsonRpcInvalidParamsCode
				message: 'Invalid or expired requestState'
				data: nil].
	(claims at: 't' ifAbsent: ['']) = aTargetName
		ifFalse: [
			McpJsonRpcError
				signalCode: McpJsonRpcInvalidParamsCode
				message: 'Invalid or expired requestState'
				data: nil].
	(claims at: 'a' ifAbsent: ['']) = (self digestForArguments: anArguments)
		ifFalse: [
			McpJsonRpcError
				signalCode: McpJsonRpcInvalidParamsCode
				message: 'Invalid or expired requestState'
				data: nil].
	aPrincipal ifNotNil: [
		(claims at: 'p' ifAbsent: [nil]) = aPrincipal asString
			ifFalse: [
				McpJsonRpcError
					signalCode: McpJsonRpcInvalidParamsCode
					message: 'Invalid or expired requestState'
					data: nil]].
	^claims at: 's' ifAbsent: ['']
]
