"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# McpClientResponseCache

`McpClientResponseCache` implements client-side response caching for idempotent MCP
methods (SEP-2549).

## Responsibilities

- Cache results from `tools/list`, `prompts/list`, `resources/list`, and `resources/read`
  honoring server-advertised `ttlMs` and `cacheScope` (`public`, `private`).
- Provide cache modes: `#use`, `#bypass`, and `#refresh`.
- Automatically evict cached entries upon receiving change notifications:
  `notifications/tools/list_changed`, `notifications/prompts/list_changed`,
  `notifications/resources/list_changed`, and `notifications/resources/updated`.
- Enforce LRU or capacity limits (`maxEntries`).

## Lifecycle and boundaries

Owned by an `McpClient`. Concurrency is protected by `entriesMutex`.
"
Class {
	#name : 'McpClientResponseCache',
	#superclass : 'Object',
	#instVars : [
		'entries',
		'entriesMutex',
		'maxEntries',
		'mode',
		'defaultTtlMs'
	],
	#category : 'McpProtocol'
}

{ #category : 'Instance Creation' }
McpClientResponseCache class >> new [
	"Answer a new initialized cache store.

	 Answers:
		<McpClientResponseCache>."

	^super new initialize
]

{ #category : 'Caching',
  #vaVisibility : 'private' }
McpClientResponseCache >> cacheKeyForMethod: aMethod key: aParamsKey [
	"Answer the composite lookup key.

	 Arguments:
		aMethod - <String> MCP request method.
		aParamsKey - <String> parameters discriminator.
	 Answers:
		<String>."

	^aMethod , '::' , (aParamsKey ifNil: [''])
]

{ #category : 'Caching' }
McpClientResponseCache >> clear [
	"Remove all cached entries.

	 Answers:
		<McpClientResponseCache> the receiver."

	entriesMutex critical: [entries := Dictionary new].
	^self
]

{ #category : 'Timing',
  #vaVisibility : 'private' }
McpClientResponseCache >> currentMillisecondClock [
	"Answer a monotonic millisecond clock value.

	 Answers:
		<Integer> milliseconds."

	^Time millisecondClockValue
]

{ #category : 'Accessing' }
McpClientResponseCache >> defaultTtlMs [
	"Answer the fallback TTL in milliseconds when a server does not provide ttlMs.

	 Answers:
		<Integer> milliseconds."

	^defaultTtlMs
]

{ #category : 'Accessing' }
McpClientResponseCache >> defaultTtlMs: anInteger [
	"Set the fallback TTL in milliseconds when a server does not provide ttlMs.

	 Arguments:
		anInteger - <Integer> nonnegative milliseconds.
	 Answers:
		<McpClientResponseCache> the receiver."

	(anInteger isInteger and: [anInteger >= 0])
		ifFalse: [self error: 'defaultTtlMs must be a non-negative integer'].
	defaultTtlMs := anInteger.
	^self
]

{ #category : 'Serialization',
  #vaVisibility : 'private' }
McpClientResponseCache >> detachedProtocolValue: anObject [
	"Answer a detached copy of anObject.

	 Arguments:
		anObject - <Object> protocol value.
	 Answers:
		<Object> detached copy."

	^self detachedProtocolValue: anObject visited: IdentitySet new
]

{ #category : 'Serialization',
  #vaVisibility : 'private' }
McpClientResponseCache >> detachedProtocolValue: anObject visited: visitedObjects [
	"Copy protocol data while rejecting cycles.

	 Arguments:
		anObject - <Object> value being copied.
		visitedObjects - <IdentitySet> active containers.
	 Answers:
		<Object> detached value."

	| detached |

	anObject ifNil: [^nil].
	anObject isBoolean ifTrue: [^anObject].
	anObject isNumber ifTrue: [^anObject].
	anObject isString ifTrue: [^anObject copy].
	(visitedObjects includes: anObject) ifTrue: [self error: 'Cached value contains a cycle'].
	(anObject isKindOf: KeyedCollection)
		ifTrue: [
			visitedObjects add: anObject.
			[
				detached := EsOrderedDictionary new.
				anObject keysAndValuesDo: [:key :value |
					detached
						at: key copy
						put: (self detachedProtocolValue: value visited: visitedObjects)]]
							ensure: [visitedObjects remove: anObject ifAbsent: []].
			^detached].
	(anObject isKindOf: SequenceableCollection)
		ifTrue: [
			visitedObjects add: anObject.
			[
				detached :=
					anObject
						collect: [:value | self detachedProtocolValue: value visited: visitedObjects]]
							ensure: [visitedObjects remove: anObject ifAbsent: []].
			^detached asArray].
	^anObject copy
]

{ #category : 'Caching' }
McpClientResponseCache >> evictForNotification: methodName params: parameters [
	"Evict cached entries affected by a server notification.

	 Arguments:
		methodName - <String> notification method.
		parameters - <KeyedCollection> notification parameters, or nil.
	 Answers:
		<McpClientResponseCache> the receiver."

	methodName = 'notifications/tools/list_changed' ifTrue: [self evictMethod: 'tools/list'].
	methodName = 'notifications/prompts/list_changed' ifTrue: [self evictMethod: 'prompts/list'].
	methodName = 'notifications/resources/list_changed' ifTrue: [self evictMethod: 'resources/list'].
	methodName = 'notifications/resources/updated'
		ifTrue: [| uri |
			uri :=
				(parameters isKindOf: KeyedCollection)
					ifTrue: [parameters at: 'uri' ifAbsent: ['']]
					ifFalse: [''].
			uri isEmpty
				ifTrue: [self evictMethod: 'resources/read']
				ifFalse: [self evictMethod: 'resources/read' key: uri]].
	^self
]

{ #category : 'Caching' }
McpClientResponseCache >> evictMethod: aMethod [
	"Evict all cached entries for a given method.

	 Arguments:
		aMethod - <String> method name.
	 Answers:
		<McpClientResponseCache> the receiver."

	| prefix matchingKeys |

	prefix := aMethod , '::'.
	entriesMutex critical: [
		matchingKeys := entries keys
			select: [:k | (k indexOfSubCollection: prefix startingAt: 1) = 1].
		matchingKeys do: [:k | entries removeKey: k ifAbsent: [nil]]].
	^self
]

{ #category : 'Caching' }
McpClientResponseCache >> evictMethod: aMethod key: aParamsKey [
	"Evict a specific entry by method and parameters key.

	 Arguments:
		aMethod - <String> method name.
		aParamsKey - <String> parameters key.
	 Answers:
		<McpClientResponseCache> the receiver."

	| key |

	key := self cacheKeyForMethod: aMethod key: aParamsKey.
	entriesMutex critical: [entries removeKey: key ifAbsent: [nil]].
	^self
]

{ #category : 'Caching' }
McpClientResponseCache >> get: aMethod key: aParamsKey [
	"Answer a detached copy of the cached result if present and fresh, or nil.

	 Arguments:
		aMethod - <String> MCP method name.
		aParamsKey - <String> parameters key.
	 Answers:
		<Object> cached result or nil."

	| key entry |

	self mode == #bypass ifTrue: [^nil].
	self mode == #refresh ifTrue: [^nil].
	key := self cacheKeyForMethod: aMethod key: aParamsKey.
	entriesMutex critical: [
		entry := entries at: key ifAbsent: [^nil].
		(self isFresh: entry)
			ifTrue: [^self detachedProtocolValue: (entry at: 'value')]
			ifFalse: [
				entries removeKey: key ifAbsent: [nil].
				^nil]]
]

{ #category : 'Initialization',
  #vaVisibility : 'private' }
McpClientResponseCache >> initialize [
	"Initialize cache state, eviction mutex, and defaults.

	 Answers:
		<McpClientResponseCache> the receiver."

	super initialize.
	entries := Dictionary new.
	entriesMutex := Semaphore forMutualExclusion.
	maxEntries := 1024.
	mode := #use.
	defaultTtlMs := 0.
	^self
]

{ #category : 'Caching',
  #vaVisibility : 'private' }
McpClientResponseCache >> isFresh: anEntry [
	"Answer whether the cache entry is still within its TTL window.

	 Arguments:
		anEntry - <KeyedCollection> cache entry.
	 Answers:
		<Boolean>."

	| expiresAt |

	expiresAt := anEntry at: 'expiresAt' ifAbsent: [^false].
	expiresAt ifNil: [^false].
	^self currentMillisecondClock < expiresAt
]

{ #category : 'Accessing' }
McpClientResponseCache >> maxEntries [
	"Answer the maximum number of entries before oldest entry eviction.

	 Answers:
		<Integer>."

	^maxEntries
]

{ #category : 'Accessing' }
McpClientResponseCache >> maxEntries: anInteger [
	"Set the maximum number of entries before oldest entry eviction.

	 Arguments:
		anInteger - <Integer> positive capacity.
	 Answers:
		<McpClientResponseCache> the receiver."

	(anInteger isInteger and: [anInteger > 0])
		ifFalse: [self error: 'maxEntries must be a positive integer'].
	maxEntries := anInteger.
	^self
]

{ #category : 'Accessing' }
McpClientResponseCache >> mode [
	"Answer the cache mode (#use, #refresh, #bypass).

	 Answers:
		<Symbol>."

	^mode
]

{ #category : 'Accessing' }
McpClientResponseCache >> mode: aSymbol [
	"Set the cache mode (#use, #refresh, #bypass).

	 Arguments:
		aSymbol - <Symbol> #use, #refresh, or #bypass.
	 Answers:
		<McpClientResponseCache> the receiver."

	(#(use refresh bypass) includes: aSymbol)
		ifFalse: [self error: 'Invalid cache mode: must be #use, #refresh, or #bypass'].
	mode := aSymbol.
	^self
]

{ #category : 'Caching' }
McpClientResponseCache >> set: aMethod key: aParamsKey value: aResult ttlMs: aTtlMs scope: aScope [
	"Store a result with TTL and scope. Replaces any existing entry under the key.

	 Arguments:
		aMethod - <String> MCP method name.
		aParamsKey - <String> parameters key.
		aResult - <Object> JSON-RPC result.
		aTtlMs - <Integer> time-to-live in milliseconds, or nil.
		aScope - <String> 'public' or 'private', or nil.
	 Answers:
		<McpClientResponseCache> the receiver."

	| key effectiveTtl expiresAt entry |

	self mode == #bypass ifTrue: [^self].
	effectiveTtl := (aTtlMs ifNil: [defaultTtlMs]) min: (24 * 60 * 60 * 1000).
	effectiveTtl <= 0 ifTrue: [^self].
	key := self cacheKeyForMethod: aMethod key: aParamsKey.
	expiresAt := self currentMillisecondClock + effectiveTtl.
	entry :=
		EsOrderedDictionary new
			at: 'value' put: (self detachedProtocolValue: aResult);
			at: 'expiresAt' put: expiresAt;
			at: 'scope' put: (aScope ifNil: ['private']);
			at: 'insertedAt' put: self currentMillisecondClock;
			yourself.
	entriesMutex critical: [
		(entries size >= maxEntries and: [(entries includesKey: key) not])
			ifTrue: [entries removeKey: entries keys asArray first ifAbsent: [nil]].
		entries at: key put: entry].
	^self
]

{ #category : 'Accessing' }
McpClientResponseCache >> size [
	"Answer the number of entries currently in the cache.

	 Answers:
		<Integer>."

	entriesMutex critical: [^entries size]
]
