"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# McpToolRegistry

`McpToolRegistry` owns the thread-safe registry of named MCP tools.

## Responsibilities

- Validate and register unique protocol-safe tool names.
- Return stable snapshots while guarding mutation with a mutex.

## Lifecycle and boundaries

The server owns the registry for its configured lifetime.
"
Class {
	#name : 'McpToolRegistry',
	#superclass : 'Object',
	#instVars : [
		'tools',
		'registryMutex'
	],
	#category : 'McpTools'
}

{ #category : 'Instance Creation' }
McpToolRegistry class >> new [
	"Answer a new initialized synchronized tool registry.

	 Answers:
		<McpToolRegistry>."

	^super new initialize
]

{ #category : 'Registration' }
McpToolRegistry >> includesToolNamed: aString [
	"Answer whether a tool is registered under a name.

	 Arguments:
		aString - <String> tool name.
	 Answers:
		<Boolean>."

	^self registryMutex critical: [tools includesKey: aString]
]

{ #category : 'Initialization',
  #vaVisibility : 'private' }
McpToolRegistry >> initialize [
	"Initialize empty synchronized registry state.

	 Answers:
		<McpToolRegistry> the receiver."

	super initialize.
	tools := EsOrderedDictionary new.
	registryMutex := Semaphore forMutualExclusion.
	^self
]

{ #category : 'Validation',
  #vaVisibility : 'private' }
McpToolRegistry >> isValidToolNameCharacter: aCharacter [
	"Answer whether a character belongs to the MCP tool-name alphabet.

	 Arguments:
		aCharacter - <Character> name character.
	 Answers:
		<Boolean>."

	| codePoint |

	codePoint := aCharacter codePoint.
	^(codePoint between: $A codePoint and: $Z codePoint) or: [
		(codePoint between: $a codePoint and: $z codePoint) or: [
			(codePoint between: $0 codePoint and: $9 codePoint)
				or: [aCharacter = $. or: [aCharacter = $- or: [aCharacter = $_]]]]]
]

{ #category : 'Registration' }
McpToolRegistry >> registerTool: aTool [
	"Validate and register one uniquely named MCP tool.

	 Arguments:
		aTool - <McpTool> tool implementation.
	 Answers:
		<McpTool> the registered tool."

	| toolName definition |

	(aTool isKindOf: McpTool) ifFalse: [self error: 'Only McpTool instances can be registered'].
	toolName := aTool name.
	((toolName isString) and: [toolName size between: 1 and: 128])
		ifFalse: [self error: 'Tool name must be a string of 1-128 characters'].
	(toolName allSatisfy: [:character | self isValidToolNameCharacter: character])
		ifFalse: [
			self error:
				'Tool name may contain only ASCII letters, digits, dot, ' , 'hyphen, and underscore'].
	definition := aTool asMcpDefinition.
	self validateToolDefinition: definition.
	self registryMutex critical: [
		(tools includesKey: toolName) ifTrue: [self error: 'Tool already registered: ' , toolName].
		tools at: toolName put: aTool].
	^aTool
]

{ #category : 'Accessing',
  #vaVisibility : 'private' }
McpToolRegistry >> registryMutex [
	"Answer the mutex protecting registry structure.

	 Answers:
		<Semaphore>."

	^registryMutex
]

{ #category : 'Accessing' }
McpToolRegistry >> size [
	"Answer the number of registered tools.

	 Answers:
		<Integer>."

	^self registryMutex critical: [tools size]
]

{ #category : 'Registration' }
McpToolRegistry >> toolNamed: aName ifAbsent: absentBlock [
	"Answer a named tool or evaluate an absence block after unlocking.

	 Arguments:
		aName - <String> tool name.
		absentBlock - <Block> evaluated when no tool is registered.
	 Answers:
		<McpTool> or the absence-block result."

	| tool found |

	found := true.
	self registryMutex critical: [tool := tools at: aName ifAbsent: [found := false]].
	^found ifTrue: [tool] ifFalse: [absentBlock value]
]

{ #category : 'Protocol Operations' }
McpToolRegistry >> tools [
	"Answer a structural snapshot of registered tools by name.

	 Answers:
		<KeyedCollection> copied registry structure."

	^self registryMutex critical: [tools copy]
]

{ #category : 'Registration' }
McpToolRegistry >> unregisterToolNamed: aString [
	"Remove and answer a named tool when present.

	 Arguments:
		aString - <String> nonempty tool name.
	 Answers:
		<McpTool> or nil."

	(aString isString and: [aString isEmpty not])
		ifFalse: [self error: 'Tool name must be a nonempty string'].
	^self registryMutex critical: [tools removeKey: aString ifAbsent: [nil]]
]

{ #category : 'Validation',
  #vaVisibility : 'private' }
McpToolRegistry >> validateToolDefinition: definition [
	"Validate an advertised definition and unsupported task claims.

	 Arguments:
		definition - <KeyedCollection> MCP tool definition.
	 Answers:
		<McpToolRegistry> the receiver."

	| value execution |

	#('title' 'description') do: [:field |
		value := definition at: field ifAbsent: [nil].
		(value isNil or: [value isString])
			ifFalse: [self error: 'Tool ' , field , ' must be a string']].
	value := definition at: 'inputSchema' ifAbsent: [nil].
	((value isKindOf: KeyedCollection) and: [(value at: 'type' ifAbsent: [nil])
		= 'object'])
		ifFalse: [self error: 'Tool inputSchema must declare object type'].
	value := definition at: 'outputSchema' ifAbsent: [nil].
	(value isNil
		or: [value isKindOf: KeyedCollection])
			ifFalse: [self error: 'Tool outputSchema must be keyed'].
	execution := definition at: 'execution' ifAbsent: [nil].
	execution ifNotNil: [| taskSupport |
		(execution isKindOf: KeyedCollection)
			ifFalse: [self error: 'Tool execution metadata must be keyed'].
		taskSupport := execution at: 'taskSupport' ifAbsent: ['forbidden'].
		taskSupport = 'forbidden'
			ifFalse: [self error:
				'MCP task-augmented tool execution is not implemented']].
	^self

]
