"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# McpSessionGroup

`McpSessionGroup` concurrently manages and aggregates multiple MCP client connections
into a single unified client facade.

## Responsibilities

- Aggregate tools, resources, and prompts across multiple connected MCP servers.
- Route `callTool:arguments:`, `getPrompt:arguments:`, and `readResource:` to the
  owning client session.
- Detect naming collisions across servers or apply disambiguation hooks (`nameCollisionHook:`).
- Offer automatic server-name prefixing via `prefixToolNamesWithServerName`.
- Gracefully close all aggregated client sessions upon shutdown.

## Lifecycle and boundaries

Thread-safe. Concurrency operations are guarded by `groupMutex`.
"
Class {
	#name : 'McpSessionGroup',
	#superclass : 'Object',
	#instVars : [
		'clients',
		'toolToClientMap',
		'promptToClientMap',
		'resourceToClientMap',
		'nameCollisionHook',
		'groupMutex'
	],
	#pools : [
		'McpJsonRpcConstants'
	],
	#category : 'McpProtocol'
}

{ #category : 'Instance Creation' }
McpSessionGroup class >> new [
	"Answer a new initialized session group.

	 Answers:
		<McpSessionGroup>."

	^super new initialize
]

{ #category : 'Registration' }
McpSessionGroup >> addClient: anMcpClient [
	"Aggregate an MCP client into this group, registering its tools, prompts, and resources.

	 Arguments:
		anMcpClient - <McpClient>.
	 Answers:
		<McpSessionGroup> the receiver."

	| sInfo toolsList promptsList resourcesList |

	anMcpClient isConnected ifFalse: [anMcpClient connect].
	sInfo := anMcpClient serverInfo.

	groupMutex critical: [
		self clients add: anMcpClient.

		[toolsList := anMcpClient listTools] on: Error do: [:e | toolsList := #()].
		toolsList do: [:toolDef | | origName compName |
			origName := toolDef at: 'name'.
			compName := self componentNameFor: origName serverInfo: sInfo.
			(toolToClientMap includesKey: compName)
				ifTrue: [
					self nameCollisionHook
						ifNil: [self error: 'Tool name collision in session group: ' , compName]].
			toolToClientMap at: compName put: (Array with: anMcpClient with: origName)].

		[promptsList := anMcpClient listPrompts] on: Error do: [:e | promptsList := #()].
		promptsList do: [:promptDef | | origName compName |
			origName := promptDef at: 'name'.
			compName := self componentNameFor: origName serverInfo: sInfo.
			promptToClientMap at: compName put: (Array with: anMcpClient with: origName)].

		[resourcesList := anMcpClient listResources] on: Error do: [:e | resourcesList := #()].
		resourcesList do: [:resourceDef | | uri |
			uri := resourceDef at: 'uri'.
			resourceToClientMap at: uri put: (Array with: anMcpClient with: uri)]].
	^self
]

{ #category : 'Protocol Operations' }
McpSessionGroup >> callTool: aToolName arguments: arguments [
	"Route a tool call to the owning client session.

	 Arguments:
		aToolName - <String> aggregated tool name.
		arguments - <KeyedCollection> tool arguments.
	 Answers:
		<KeyedCollection> CallToolResult."

	| binding targetClient origName |

	binding :=
		groupMutex critical: [
			toolToClientMap
				at: aToolName
				ifAbsent: [self error: 'Unknown tool in session group: ' , aToolName]].
	targetClient := binding first.
	origName := binding second.
	^targetClient callTool: origName arguments: arguments
]

{ #category : 'Accessing' }
McpSessionGroup >> clients [
	"Answer the collection of aggregated MCP clients.

	 Answers:
		<OrderedCollection> of <McpClient>."

	clients ifNil: [clients := OrderedCollection new].
	^clients
]

{ #category : 'Connection Lifecycle' }
McpSessionGroup >> close [
	"Close all registered client sessions and reset aggregated state.

	 Answers:
		<McpSessionGroup> the receiver."

	groupMutex critical: [
		self clients do: [:c | [c close] on: Error do: [:e | nil]].
		clients := OrderedCollection new.
		toolToClientMap := Dictionary new.
		promptToClientMap := Dictionary new.
		resourceToClientMap := Dictionary new].
	^self
]

{ #category : 'Private',
  #vaVisibility : 'private' }
McpSessionGroup >> componentNameFor: rawName serverInfo: sInfo [
	"Answer the resolved component name applying the collision hook if configured.

	 Arguments:
		rawName - <String>.
		sInfo - <KeyedCollection>.
	 Answers:
		<String>."

	self nameCollisionHook ifNotNil: [:hook | ^hook cull: rawName cull: sInfo].
	^rawName
]

{ #category : 'Protocol Operations' }
McpSessionGroup >> getPrompt: aPromptName arguments: arguments [
	"Route a getPrompt call to the owning client session.

	 Arguments:
		aPromptName - <String> prompt name.
		arguments - <KeyedCollection> arguments.
	 Answers:
		<KeyedCollection>."

	| binding targetClient origName |

	binding :=
		groupMutex critical: [
			promptToClientMap
				at: aPromptName
				ifAbsent: [self error: 'Unknown prompt in session group: ' , aPromptName]].
	targetClient := binding first.
	origName := binding second.
	^targetClient getPrompt: origName arguments: arguments
]

{ #category : 'Initialization',
  #vaVisibility : 'private' }
McpSessionGroup >> initialize [
	"Initialize session group collections and synchronization mutex.

	 Answers:
		<McpSessionGroup> the receiver."

	super initialize.
	clients := OrderedCollection new.
	toolToClientMap := Dictionary new.
	promptToClientMap := Dictionary new.
	resourceToClientMap := Dictionary new.
	groupMutex := Semaphore forMutualExclusion.
	^self
]

{ #category : 'Protocol Operations' }
McpSessionGroup >> listPrompts [
	"Answer the aggregated prompt definitions across all clients.

	 Answers:
		<Array>."

	| aggregated |

	aggregated := OrderedCollection new.
	groupMutex critical: [
		promptToClientMap keysAndValuesDo: [:compName :binding |
			aggregated add: (EsOrderedDictionary with: 'name' -> compName)]].
	^aggregated asArray
]

{ #category : 'Protocol Operations' }
McpSessionGroup >> listResources [
	"Answer the aggregated resource definitions across all clients.

	 Answers:
		<Array>."

	| aggregated |

	aggregated := OrderedCollection new.
	groupMutex critical: [
		resourceToClientMap keysAndValuesDo: [:uri :binding |
			aggregated add: (EsOrderedDictionary with: 'uri' -> uri)]].
	^aggregated asArray
]

{ #category : 'Protocol Operations' }
McpSessionGroup >> listTools [
	"Answer the aggregated collection of tool definitions from all registered clients.

	 Answers:
		<Array> of <KeyedCollection>."

	| aggregated |

	aggregated := OrderedCollection new.
	groupMutex critical: [
		toolToClientMap keysAndValuesDo: [:compName :binding | | targetClient origName def |
			targetClient := binding first.
			origName := binding second.
			def :=
				EsOrderedDictionary new
					at: 'name' put: compName;
					yourself.
			targetClient knownToolSchemas
				at: origName
				ifPresent: [:schema | def at: 'inputSchema' put: schema].
			aggregated add: def]].
	^aggregated asArray
]

{ #category : 'Accessing' }
McpSessionGroup >> nameCollisionHook [
	"Answer the optional hook block [:componentName :serverInfo | ...] for disambiguating names.

	 Answers:
		<Block> or nil."

	^nameCollisionHook
]

{ #category : 'Accessing' }
McpSessionGroup >> nameCollisionHook: aBlock [
	"Set the hook block [:componentName :serverInfo | ...] for disambiguating names.

	 Arguments:
		aBlock - <Block>.
	 Answers:
		<McpSessionGroup> the receiver."

	nameCollisionHook := aBlock.
	^self
]

{ #category : 'Configuration' }
McpSessionGroup >> prefixToolNamesWithServerName [
	"Configure a default collision hook that prefixes tool names with the server name.

	 Answers:
		<McpSessionGroup> the receiver."

	nameCollisionHook := [:rawName :sInfo | | sName |
		sName := sInfo at: 'name' ifAbsent: ['server'].
		sName , '_' , rawName].
	^self
]

{ #category : 'Protocol Operations' }
McpSessionGroup >> readResource: aUri [
	"Route a readResource call to the owning client session.

	 Arguments:
		aUri - <String> resource URI.
	 Answers:
		<KeyedCollection>."

	| binding targetClient origUri |

	binding :=
		groupMutex critical: [
			resourceToClientMap
				at: aUri
				ifAbsent: [self error: 'Unknown resource in session group: ' , aUri]].
	targetClient := binding first.
	origUri := binding second.
	^targetClient readResource: origUri
]

{ #category : 'Registration' }
McpSessionGroup >> removeClient: anMcpClient [
	"Deregister an MCP client and evict all its mapped components from this group.

	 Arguments:
		anMcpClient - <McpClient>.
	 Answers:
		<McpSessionGroup> the receiver."

	groupMutex critical: [
		self clients remove: anMcpClient ifAbsent: [].
		toolToClientMap keys copy do: [:k |
			((toolToClientMap at: k) first == anMcpClient) ifTrue: [toolToClientMap removeKey: k]].
		promptToClientMap keys copy do: [:k |
			((promptToClientMap at: k) first == anMcpClient) ifTrue: [promptToClientMap removeKey: k]].
		resourceToClientMap keys copy do: [:k |
			((resourceToClientMap at: k) first == anMcpClient)
				ifTrue: [resourceToClientMap removeKey: k]]].
	^self
]
