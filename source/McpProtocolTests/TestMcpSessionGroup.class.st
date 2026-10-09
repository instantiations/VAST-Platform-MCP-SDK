Class {
	#name : 'TestMcpSessionGroup',
	#superclass : 'TestCase',
	#instVars : [
		'group',
		'server1',
		'server2',
		'client1',
		'client2'
	],
	#pools : [
		'McpJsonRpcConstants'
	],
	#category : 'McpProtocolTests'
}

{ #category : 'Running' }
TestMcpSessionGroup >> setUp [
	"Prepare servers, clients, and session group."

	super setUp.
	server1 :=
		McpServer new
			name: 'serverAlpha';
			version: '1.0';
			yourself.
	server2 :=
		McpServer new
			name: 'serverBeta';
			version: '1.0';
			yourself.
	client1 := McpClient forServer: server1.
	client2 := McpClient forServer: server2.
	group := McpSessionGroup new
]

{ #category : 'Running' }
TestMcpSessionGroup >> tearDown [
	"Clean up."

	group ifNotNil: [group close].
	client1 ifNotNil: [client1 close].
	client2 ifNotNil: [client2 close].
	super tearDown
]

{ #category : 'Testing' }
TestMcpSessionGroup >> testAggregateToolsFromMultipleServers [
	"Verify session group aggregates tools across multiple connected servers."

	| toolA toolB tools names |

	toolA :=
		McpBlockTool new
			name: 'toolAlpha';
			block: ['alpha'];
			yourself.
	toolB :=
		McpBlockTool new
			name: 'toolBeta';
			block: ['beta'];
			yourself.
	server1 toolRegistry registerTool: toolA.
	server2 toolRegistry registerTool: toolB.

	group addClient: client1.
	group addClient: client2.

	tools := group listTools.
	names := tools collect: [:t | t at: 'name'].
	self assert: names size equals: 2.
	self assert: (names includes: 'toolAlpha').
	self assert: (names includes: 'toolBeta')
]

{ #category : 'Testing' }
TestMcpSessionGroup >> testAutoMcpParamHeadersEmittedOnModernConnection [
	"Verify McpClient automatically emits Mcp-Param-* headers for annotated arguments."

	| schema tool headers |

	schema :=
		EsOrderedDictionary new
			at: 'type' put: 'object';
			at: 'properties'
				put: (
					EsOrderedDictionary with:
						'region' -> (
							EsOrderedDictionary new
								at: 'type' put: 'string';
								at: 'x-mcp-header' put: 'Region';
								yourself));
			yourself.
	tool :=
		McpBlockTool new
			name: 'deploy';
			inputSchema: schema;
			block: [:args :ctx | 'ok'];
			yourself.
	server1 toolRegistry registerTool: tool.

	client1 connect.
	client1 listTools.

	headers :=
		client1
			resolveParamHeadersForTool: 'deploy'
			arguments: (EsOrderedDictionary with: 'region' -> 'us-east1').
	self assert: (headers at: 'Mcp-Param-Region') equals: 'us-east1'
]

{ #category : 'Testing' }
TestMcpSessionGroup >> testCallToolRoutesToOwningServer [
	"Verify calling tools routes to the correct target server."

	| toolA toolB resA resB |

	toolA :=
		McpBlockTool new
			name: 'toolAlpha';
			block: ['alpha'];
			yourself.
	toolB :=
		McpBlockTool new
			name: 'toolBeta';
			block: ['beta'];
			yourself.
	server1 toolRegistry registerTool: toolA.
	server2 toolRegistry registerTool: toolB.

	group addClient: client1.
	group addClient: client2.

	resA := group callTool: 'toolAlpha' arguments: EsOrderedDictionary new.
	resB := group callTool: 'toolBeta' arguments: EsOrderedDictionary new.

	self assert: (((resA at: 'content') first) at: 'text') equals: 'alpha'.
	self assert: (((resB at: 'content') first) at: 'text') equals: 'beta'
]

{ #category : 'Testing' }
TestMcpSessionGroup >> testNameCollisionWithPrefixHookDisambiguates [
	"Verify prefixToolNamesWithServerName disambiguates colliding tool names."

	| toolA toolB tools names resA resB |

	toolA :=
		McpBlockTool new
			name: 'duplicateTool';
			block: ['alpha'];
			yourself.
	toolB :=
		McpBlockTool new
			name: 'duplicateTool';
			block: ['beta'];
			yourself.
	server1 toolRegistry registerTool: toolA.
	server2 toolRegistry registerTool: toolB.

	group prefixToolNamesWithServerName.
	group addClient: client1.
	group addClient: client2.

	tools := group listTools.
	names := tools collect: [:t | t at: 'name'].
	self assert: (names includes: 'serverAlpha_duplicateTool').
	self assert: (names includes: 'serverBeta_duplicateTool').

	resA := group callTool: 'serverAlpha_duplicateTool' arguments: EsOrderedDictionary new.
	resB := group callTool: 'serverBeta_duplicateTool' arguments: EsOrderedDictionary new.

	self assert: (((resA at: 'content') first) at: 'text') equals: 'alpha'.
	self assert: (((resB at: 'content') first) at: 'text') equals: 'beta'
]

{ #category : 'Testing' }
TestMcpSessionGroup >> testNameCollisionWithoutHookRaisesError [
	"Verify naming collision without disambiguation hook raises an error."

	| toolA toolB |

	toolA :=
		McpBlockTool new
			name: 'duplicateTool';
			block: ['alpha'];
			yourself.
	toolB :=
		McpBlockTool new
			name: 'duplicateTool';
			block: ['beta'];
			yourself.
	server1 toolRegistry registerTool: toolA.
	server2 toolRegistry registerTool: toolB.

	group addClient: client1.
	self should: [group addClient: client2] raise: Error
]

{ #category : 'Testing' }
TestMcpSessionGroup >> testRemoveClientEvictsMappedComponents [
	"Verify removing a client evicts all its mapped tools and components."

	| toolA |

	toolA :=
		McpBlockTool new
			name: 'toolAlpha';
			block: ['alpha'];
			yourself.
	server1 toolRegistry registerTool: toolA.

	group addClient: client1.
	self assert: group listTools size equals: 1.

	group removeClient: client1.
	self assert: group listTools isEmpty
]
