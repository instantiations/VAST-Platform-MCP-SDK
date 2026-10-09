"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# TestMcpPromptRegistry

`TestMcpPromptRegistry` verifies prompt definition and registration invariants.

## Responsibilities

- Verify unique prompt registration and public lookup.
- Verify descriptive metadata and argument serialization.
- Verify argument-definition validation and defensive copying.
- Verify rendering-block arity validation.

Each test creates a fresh registry and shares no mutable prompt metadata.
"
Class {
	#name : 'TestMcpPromptRegistry',
	#superclass : 'TestCase',
	#instVars : [
		'registry'
	],
	#category : 'McpPromptTests'
}

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpPromptRegistry >> emptyResult [
	"Answer a valid empty GetPromptResult."

	^EsOrderedDictionary with: 'messages' -> #()
]

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpPromptRegistry >> promptNamed: promptName block: renderingBlock [
	"Answer a configured block prompt."

	^McpBlockPrompt new
		name: promptName;
		block: renderingBlock;
		yourself
]

{ #category : 'Initialization' }
TestMcpPromptRegistry >> setUp [
	"Create a fresh prompt registry."

	super setUp.
	registry := McpPromptRegistry new
]

{ #category : 'Copying' }
TestMcpPromptRegistry >> testArgumentDefinitionsAreDefensivelyCopied [
	"Argument definitions cannot be mutated through either metadata boundary."

	| definition argument prompt returnedArguments |

	argument :=
		EsOrderedDictionary new
			at: 'name' put: 'topic';
			at: 'description' put: 'Topic to explain';
			at: 'required' put: true;
			yourself.
	prompt := self promptNamed: 'snapshot.prompt' block: [self emptyResult].
	prompt arguments: (Array with: argument).
	argument at: 'name' put: 'changed'.
	self assert: (prompt arguments first at: 'name') equals: 'topic'.
	returnedArguments := prompt arguments.
	returnedArguments first at: 'name' put: 'changed-again'.
	self assert: (prompt arguments first at: 'name') equals: 'topic'.
	definition := prompt asMcpDefinition.
	self assert: ((definition at: 'arguments') first at: 'name') equals: 'topic'
]

{ #category : 'Validation' }
TestMcpPromptRegistry >> testDuplicateArgumentNamesAreRejected [
	"Prompt argument names must be unique within one definition."

	| prompt first second |

	first := EsOrderedDictionary with: 'name' -> 'topic'.
	second := EsOrderedDictionary with: 'name' -> 'topic'.
	prompt := self promptNamed: 'duplicate.arguments' block: [self emptyResult].
	self should: [prompt arguments: (Array with: first with: second)] raise: Error
]

{ #category : 'Registration' }
TestMcpPromptRegistry >> testDuplicateRegistrationPreservesOriginalPrompt [
	"Duplicate names are rejected without replacing the registered prompt."

	| original duplicate signaledError |

	original := self promptNamed: 'duplicate.prompt' block: [self emptyResult].
	duplicate := self promptNamed: 'duplicate.prompt' block: [self emptyResult].
	registry registerPrompt: original.
	signaledError := nil.
	[registry registerPrompt: duplicate]
		on: Error
		do: [:error |
			signaledError := error.
			error return].
	self assert: signaledError notNil.
	self assert: signaledError messageText equals: 'Prompt already registered: duplicate.prompt'.
	self assert: (registry promptNamed: 'duplicate.prompt' ifAbsent: [nil]) equals: original.
	self assert: registry size equals: 1
]

{ #category : 'Serialization' }
TestMcpPromptRegistry >> testPromptDefinitionIncludesConfiguredMetadata [
	"A prompt definition includes descriptive and argument metadata."

	| prompt argument definition |

	argument :=
		EsOrderedDictionary new
			at: 'name' put: 'code';
			at: 'title' put: 'Source code';
			at: 'description' put: 'Code to review';
			at: 'required' put: true;
			yourself.
	prompt := self promptNamed: 'code.review' block: [self emptyResult].
	prompt
		title: 'Code Review';
		description: 'Review source code';
		arguments: (Array with: argument).
	definition := prompt asMcpDefinition.
	self assert: (definition at: 'name') equals: 'code.review'.
	self assert: (definition at: 'title') equals: 'Code Review'.
	self assert: (definition at: 'description') equals: 'Review source code'.
	self assert: (definition at: 'arguments') size equals: 1.
	self assert: ((definition at: 'arguments') first at: 'required') equals: true
]

{ #category : 'Validation' }
TestMcpPromptRegistry >> testPromptRejectsInvalidArgumentRequiredFlag [
	"An argument required flag must be Boolean when present."

	| prompt argument |

	argument :=
		EsOrderedDictionary new
			at: 'name' put: 'topic';
			at: 'required' put: 'yes';
			yourself.
	prompt := self promptNamed: 'invalid.required' block: [self emptyResult].
	self should: [prompt arguments: (Array with: argument)] raise: Error
]

{ #category : 'Registration' }
TestMcpPromptRegistry >> testRegistrationSupportsPublicLookup [
	"Registration exposes the same prompt through public lookup."

	| prompt lookedUp |

	prompt := self promptNamed: 'lookup.prompt' block: [self emptyResult].
	self assert: (registry registerPrompt: prompt) equals: prompt.
	self assert: (registry includesPromptNamed: 'lookup.prompt').
	lookedUp := registry promptNamed: 'lookup.prompt' ifAbsent: [nil].
	self assert: lookedUp == prompt.
	self assert: registry size equals: 1
]

{ #category : 'Validation' }
TestMcpPromptRegistry >> testRenderingBlockRejectsUnsupportedArity [
	"A rendering block may accept at most arguments and request context."

	| prompt |

	prompt := McpBlockPrompt new name: 'invalid.block'.
	self should: [prompt block: [:arguments :context :extra | extra]] raise: Error
]
