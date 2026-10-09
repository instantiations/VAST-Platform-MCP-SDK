"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# TestMcpProgress

`TestMcpProgress` tests MCP `notifications/progress` notification dispatch,
server-side progress token extraction, context reporting, and client-side
progress callback correlation.
"
Class {
	#name : 'TestMcpResponseCache',
	#superclass : 'TestCase',
	#instVars : [
		'cache',
		'client',
		'transport'
	],
	#category : 'McpProtocolTests'
}

{ #category : 'Running' }
TestMcpResponseCache >> setUp [
	"Prepare cache test fixtures.

	 Answers:
		<TestMcpResponseCache> the receiver."

	super setUp.
	cache := McpClientResponseCache new.
	transport := McpScriptedClientTransport new.
	client := McpClient new.
	client transport: transport.
	^self
]

{ #category : 'Running' }
TestMcpResponseCache >> tearDown [
	"Clean up test fixtures.

	 Answers:
		<TestMcpResponseCache> the receiver."

	client ifNotNil: [[client close] on: Error do: [:closeError | closeError return: nil]].
	super tearDown
]

{ #category : 'Testing' }
TestMcpResponseCache >> testCacheStoreExpiresStaleEntry [
	"Verify that an entry past its TTL is treated as stale and evicted."

	| payload retrieved |

	payload := EsOrderedDictionary with: 'data' -> 'temp'.
	cache set: 'resources/read' key: 'test://uri' value: payload ttlMs: 1 scope: 'private'.

	(Delay forMilliseconds: 20) wait.

	retrieved := cache get: 'resources/read' key: 'test://uri'.
	self assert: retrieved isNil.
	self assert: cache size = 0
]

{ #category : 'Testing' }
TestMcpResponseCache >> testCacheStoreGetAndSetFreshEntry [
	"Verify setting and getting a fresh cache entry within its TTL window."

	| payload retrieved |

	payload := EsOrderedDictionary with: 'tools' -> #('toolA' 'toolB').
	cache set: 'tools/list' key: '' value: payload ttlMs: 5000 scope: 'public'.

	retrieved := cache get: 'tools/list' key: ''.
	self assert: retrieved notNil.
	self assert: (retrieved at: 'tools') asArray = #('toolA' 'toolB')
]

{ #category : 'Testing' }
TestMcpResponseCache >> testCacheStoreMaxEntriesEviction [
	"Verify that exceeding maxEntries drops the oldest entry."

	cache maxEntries: 2.
	cache set: 'm1' key: 'k1' value: 'v1' ttlMs: 10000 scope: 'public'.
	cache set: 'm2' key: 'k2' value: 'v2' ttlMs: 10000 scope: 'public'.
	cache set: 'm3' key: 'k3' value: 'v3' ttlMs: 10000 scope: 'public'.

	self assert: cache size = 2.
	self assert: (cache get: 'm1' key: 'k1') isNil.
	self assert: (cache get: 'm2' key: 'k2') = 'v2'.
	self assert: (cache get: 'm3' key: 'k3') = 'v3'
]

{ #category : 'Testing' }
TestMcpResponseCache >> testCacheStoreModeBypass [
	"Verify that mode #bypass neither reads nor writes to the cache."

	cache mode: #bypass.
	cache set: 'tools/list' key: '' value: 'tools' ttlMs: 10000 scope: 'public'.

	self assert: cache size = 0.
	self assert: (cache get: 'tools/list' key: '') isNil
]

{ #category : 'Testing' }
TestMcpResponseCache >> testCacheStoreModeRefresh [
	"Verify that mode #refresh stores without serving stale values."

	cache set: 'tools/list' key: '' value: 'version1' ttlMs: 10000 scope: 'public'.
	cache mode: #refresh.

	self assert: (cache get: 'tools/list' key: '') isNil.

	cache set: 'tools/list' key: '' value: 'version2' ttlMs: 10000 scope: 'public'.

	cache mode: #use.
	self assert: (cache get: 'tools/list' key: '') = 'version2'
]

{ #category : 'Testing' }
TestMcpResponseCache >> testClientCachesResultWithTtl [
	"Verify that McpClient caches responses when ttlMs is returned by the server."

	| response tools1 tools2 |

	client instVarNamed: 'isConnected' put: true.
	client instVarNamed: 'serverCapabilities' put: (Dictionary with: 'tools' -> Dictionary new).

	response :=
		EsOrderedDictionary new
			at: 'tools'
				put: (
					Array with: (
						EsOrderedDictionary new
							at: 'name' put: 'echo';
							at: 'description' put: 'echoes';
							at: 'inputSchema' put: (EsOrderedDictionary with: 'type' -> 'object');
							yourself));
			at: 'ttlMs' put: 10000;
			at: 'cacheScope' put: 'public';
			yourself.
	transport enqueueResponse: response.

	tools1 := client listTools.
	self assert: tools1 size = 1.
	self assert: transport requests size = 1.

	tools2 := client listTools.
	self assert: tools2 size = 1.
	self assert: transport requests size = 1
]

{ #category : 'Testing' }
TestMcpResponseCache >> testClientInvalidatesCacheOnToolsListChangedNotification [
	"Verify that notifications/tools/list_changed invalidates the tools/list cache."

	| response1 response2 notification tools1 tools2 |

	client instVarNamed: 'isConnected' put: true.
	client instVarNamed: 'serverCapabilities' put: (Dictionary with: 'tools' -> Dictionary new).

	response1 :=
		EsOrderedDictionary new
			at: 'tools'
				put: (
					Array with: (
						EsOrderedDictionary new
							at: 'name' put: 'tool1';
							at: 'inputSchema' put: (EsOrderedDictionary with: 'type' -> 'object');
							yourself));
			at: 'ttlMs' put: 10000;
			yourself.
	transport enqueueResponse: response1.

	tools1 := client listTools.
	self assert: tools1 size = 1.
	self assert: transport requests size = 1.

	notification :=
		EsOrderedDictionary new
			at: 'jsonrpc' put: '2.0';
			at: 'method' put: 'notifications/tools/list_changed';
			at: 'params' put: EsOrderedDictionary new;
			yourself.
	client handleIncomingMessage: notification.

	response2 :=
		EsOrderedDictionary new
			at: 'tools'
				put: (
					Array
						with: (
							EsOrderedDictionary new
								at: 'name' put: 'tool1';
								at: 'inputSchema'
									put: (EsOrderedDictionary with: 'type' -> 'object');
								yourself)
						with: (
							EsOrderedDictionary new
								at: 'name' put: 'tool2';
								at: 'inputSchema'
									put: (EsOrderedDictionary with: 'type' -> 'object');
								yourself));
			at: 'ttlMs' put: 10000;
			yourself.
	transport enqueueResponse: response2.

	tools2 := client listTools.
	self assert: tools2 size = 2.
	self assert: transport requests size = 2
]

{ #category : 'Testing' }
TestMcpResponseCache >> testClientInvalidatesResourceCacheOnResourceUpdated [
	"Verify that notifications/resources/updated invalidates the specific resources/read cache entry."

	| response1 response2 notification read1 read2 |

	client instVarNamed: 'isConnected' put: true.
	client instVarNamed: 'serverCapabilities' put: (Dictionary with: 'resources' -> Dictionary new).

	response1 :=
		EsOrderedDictionary new
			at: 'contents'
				put: (
					Array with:
						(EsOrderedDictionary with: 'uri' -> 'test://res1' with: 'text' -> 'version1'));
			at: 'ttlMs' put: 10000;
			yourself.
	transport enqueueResponse: response1.

	read1 := client readResource: 'test://res1'.
	self assert: ((read1 at: 'contents') first at: 'text') = 'version1'.
	self assert: transport requests size = 1.

	read1 := client readResource: 'test://res1'.
	self assert: transport requests size = 1.

	notification :=
		EsOrderedDictionary new
			at: 'jsonrpc' put: '2.0';
			at: 'method' put: 'notifications/resources/updated';
			at: 'params' put: (EsOrderedDictionary with: 'uri' -> 'test://res1');
			yourself.
	client handleIncomingMessage: notification.

	response2 :=
		EsOrderedDictionary new
			at: 'contents'
				put: (
					Array with:
						(EsOrderedDictionary with: 'uri' -> 'test://res1' with: 'text' -> 'version2'));
			at: 'ttlMs' put: 10000;
			yourself.
	transport enqueueResponse: response2.

	read2 := client readResource: 'test://res1'.
	self assert: ((read2 at: 'contents') first at: 'text') = 'version2'.
	self assert: transport requests size = 2
]

{ #category : 'Testing' }
TestMcpResponseCache >> testEvictMethodAndKey [
	"Verify selective method eviction and key eviction."

	cache set: 'tools/list' key: '' value: 'all-tools' ttlMs: 10000 scope: 'public'.
	cache set: 'resources/read' key: 'res://1' value: 'r1' ttlMs: 10000 scope: 'public'.
	cache set: 'resources/read' key: 'res://2' value: 'r2' ttlMs: 10000 scope: 'public'.

	cache evictMethod: 'resources/read' key: 'res://1'.
	self assert: (cache get: 'resources/read' key: 'res://1') isNil.
	self assert: (cache get: 'resources/read' key: 'res://2') = 'r2'.

	cache evictMethod: 'resources/read'.
	self assert: (cache get: 'resources/read' key: 'res://2') isNil.
	self assert: (cache get: 'tools/list' key: '') = 'all-tools'
]
