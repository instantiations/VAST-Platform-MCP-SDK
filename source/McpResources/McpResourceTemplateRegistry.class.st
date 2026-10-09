"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# McpResourceTemplateRegistry

`McpResourceTemplateRegistry` owns the thread-safe registry of MCP resource
templates.

## Responsibilities

- Validate unique templates and resolve the first matching URI.
- Return stable snapshots while guarding mutation with a mutex.

## Lifecycle and boundaries

The server owns the registry for its configured lifetime.
"
Class {
	#name : 'McpResourceTemplateRegistry',
	#superclass : 'Object',
	#instVars : [
		'templates',
		'registryMutex'
	],
	#category : 'McpResources'
}

{ #category : 'Instance Creation' }
McpResourceTemplateRegistry class >> new [
	"Answer a new initialized resource-template registry.

	 Answers:
		<McpResourceTemplateRegistry>."

	^super new initialize
]

{ #category : 'Registration' }
McpResourceTemplateRegistry >> includesTemplate: aUriTemplate [
	"Answer whether an exact URI-template string is registered.

	 Arguments:
		aUriTemplate - <String> advertised template.
	 Answers:
		<Boolean>."

	^self registryMutex critical: [templates includesKey: aUriTemplate]
]

{ #category : 'Initialization',
  #vaVisibility : 'private' }
McpResourceTemplateRegistry >> initialize [
	"Initialize empty synchronized registry state.

	 Answers:
		<McpResourceTemplateRegistry> the receiver."

	super initialize.
	templates := EsOrderedDictionary new.
	registryMutex := Semaphore forMutualExclusion.
	^self
]

{ #category : 'Registration' }
McpResourceTemplateRegistry >> registerTemplate: aTemplate [
	"Validate and register one uniquely advertised resource template.

	 Arguments:
		aTemplate - <McpResourceTemplate> template implementation.
	 Answers:
		<McpResourceTemplate> the registered template."

	| templateString |

	self validateTemplate: aTemplate.
	templateString := aTemplate uriTemplate.
	self registryMutex critical: [
		(templates includesKey: templateString)
			ifTrue: [self error: 'Resource template already registered: ' , templateString].
		templates at: templateString put: aTemplate].
	^aTemplate
]

{ #category : 'Accessing',
  #vaVisibility : 'private' }
McpResourceTemplateRegistry >> registryMutex [
	"Answer the mutex protecting registry structure.

	 Answers:
		<Semaphore>."

	^registryMutex
]

{ #category : 'Accessing' }
McpResourceTemplateRegistry >> size [
	"Answer the number of registered resource templates.

	 Answers:
		<Integer>."

	^self registryMutex critical: [templates size]
]

{ #category : 'Registration' }
McpResourceTemplateRegistry >> templateMatchingUri: aUri ifAbsent: absentBlock [
	"Answer the sole matching template or evaluate an absence block.

	 Arguments:
		aUri - <String> concrete resource URI.
		absentBlock - <Block> evaluated when no template matches.
	 Answers:
		<McpResourceTemplate> or the absence-block result."

	| snapshot matches |

	snapshot :=
		self templates values
			asSortedCollection: [:left :right | left uriTemplate <= right uriTemplate].
	matches := snapshot select: [:template | template matchesUri: aUri].
	matches isEmpty ifTrue: [^absentBlock value].
	matches size > 1 ifTrue: [self error: 'Multiple MCP resource templates match the URI'].
	^matches first
]

{ #category : 'Accessing' }
McpResourceTemplateRegistry >> templates [
	"Answer a structural snapshot of registered resource templates.

	 Answers:
		<KeyedCollection> template-string mapping."

	^self registryMutex critical: [templates copy]
]

{ #category : 'Registration' }
McpResourceTemplateRegistry >> unregisterTemplate: aUriTemplate [
	"Remove and answer an exact advertised resource template.

	 Arguments:
		aUriTemplate - <String> nonempty URI-template string.
	 Answers:
		<McpResourceTemplate> or nil."

	(aUriTemplate isString and: [aUriTemplate isEmpty not])
		ifFalse: [self error: 'Resource template must be a nonempty string'].
	^self registryMutex critical: [templates removeKey: aUriTemplate ifAbsent: [nil]]
]

{ #category : 'Validation',
  #vaVisibility : 'private' }
McpResourceTemplateRegistry >> validateTemplate: aTemplate [
	"Validate a resource template before entering the registry.

	 Arguments:
		aTemplate - <Object> registration candidate.
	 Answers:
		<McpResourceTemplateRegistry> the receiver."

	| templateString templateName |

	(aTemplate isKindOf: McpResourceTemplate)
		ifFalse: [self error: 'Only McpResourceTemplate instances can be registered'].
	templateString := aTemplate uriTemplate.
	(templateString isString and: [templateString isEmpty not])
		ifFalse: [self error: 'Resource template must be a nonempty string'].
	templateName := aTemplate name.
	(templateName isString and: [templateName isEmpty not])
		ifFalse: [self error: 'Resource-template name must be nonempty'].
	aTemplate asMcpDefinition.
	^self
]
