"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# McpPromptRegistry

`McpPromptRegistry` owns the thread-safe registry of named MCP prompts.

## Responsibilities

- Validate and register unique prompt names.
- Return stable snapshots while guarding mutation with a mutex.

## Lifecycle and boundaries

The server owns the registry for its configured lifetime.
"
Class {
	#name : 'McpPromptRegistry',
	#superclass : 'Object',
	#instVars : [
		'prompts',
		'registryMutex'
	],
	#category : 'McpPrompts'
}

{ #category : 'Instance Creation' }
McpPromptRegistry class >> new [
	"Answer a new initialized prompt registry.

	 Answers:
		<McpPromptRegistry>."

	^super new initialize
]

{ #category : 'Registration' }
McpPromptRegistry >> includesPromptNamed: aString [
	"Answer whether a prompt is registered under a name.

	 Arguments:
		aString - <String> prompt name.
	 Answers:
		<Boolean>."

	^self registryMutex critical: [prompts includesKey: aString]
]

{ #category : 'Initialization',
  #vaVisibility : 'private' }
McpPromptRegistry >> initialize [
	"Initialize empty synchronized registry state.

	 Answers:
		<McpPromptRegistry> the receiver."

	super initialize.
	prompts := EsOrderedDictionary new.
	registryMutex := Semaphore forMutualExclusion.
	^self
]

{ #category : 'Registration' }
McpPromptRegistry >> promptNamed: aString ifAbsent: absentBlock [
	"Answer a named prompt or evaluate an absence block.

	 Arguments:
		aString - <String> prompt name.
		absentBlock - <Block> evaluated when no prompt is registered.
	 Answers:
		<McpPrompt> or the absence-block result."

	| prompt found |

	found := true.
	self registryMutex critical: [prompt := prompts at: aString ifAbsent: [found := false]].
	^found ifTrue: [prompt] ifFalse: [absentBlock value]
]

{ #category : 'Protocol Operations' }
McpPromptRegistry >> prompts [
	"Answer a structural snapshot of registered prompts.

	 Answers:
		<KeyedCollection> name-to-prompt mapping."

	^self registryMutex critical: [prompts copy]
]

{ #category : 'Registration' }
McpPromptRegistry >> registerPrompt: aPrompt [
	"Validate and register one uniquely named prompt.

	 Arguments:
		aPrompt - <McpPrompt> prompt implementation.
	 Answers:
		<McpPrompt> the registered prompt."

	| promptName |

	self validatePrompt: aPrompt.
	promptName := aPrompt name.
	self registryMutex critical: [
		(prompts includesKey: promptName)
			ifTrue: [self error: 'Prompt already registered: ' , promptName].
		prompts at: promptName put: aPrompt].
	^aPrompt
]

{ #category : 'Accessing',
  #vaVisibility : 'private' }
McpPromptRegistry >> registryMutex [
	"Answer the mutex protecting registry structure.

	 Answers:
		<Semaphore>."

	^registryMutex
]

{ #category : 'Accessing' }
McpPromptRegistry >> size [
	"Answer the number of registered prompts.

	 Answers:
		<Integer>."

	^self registryMutex critical: [prompts size]
]

{ #category : 'Registration' }
McpPromptRegistry >> unregisterPromptNamed: aString [
	"Remove and answer a named prompt when present.

	 Arguments:
		aString - <String> nonempty prompt name.
	 Answers:
		<McpPrompt> or nil."

	(aString isString and: [aString isEmpty not])
		ifFalse: [self error: 'Prompt name must be a nonempty string'].
	^self registryMutex critical: [prompts removeKey: aString ifAbsent: [nil]]
]

{ #category : 'Validation',
  #vaVisibility : 'private' }
McpPromptRegistry >> validatePrompt: aPrompt [
	"Validate a prompt before entering the registry.

	 Arguments:
		aPrompt - <Object> registration candidate.
	 Answers:
		<McpPromptRegistry> the receiver."

	| promptName |

	(aPrompt isKindOf: McpPrompt) ifFalse: [self error: 'Only McpPrompt instances can be registered'].
	promptName := aPrompt name.
	(promptName isString and: [promptName isEmpty not])
		ifFalse: [self error: 'Prompt name must be a nonempty string'].
	aPrompt asMcpDefinition.
	^self
]
