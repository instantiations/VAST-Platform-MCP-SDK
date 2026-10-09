"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# McpResourceRegistry

`McpResourceRegistry` owns the thread-safe registry of concrete MCP
resources.

## Responsibilities

- Validate and register unique resource URIs.
- Return stable snapshots while guarding mutation with a mutex.

## Lifecycle and boundaries

The server owns the registry for its configured lifetime.
"
Class {
	#name : 'McpResourceRegistry',
	#superclass : 'Object',
	#instVars : [
		'resources',
		'registryMutex'
	],
	#category : 'McpResources'
}

{ #category : 'Instance Creation' }
McpResourceRegistry class >> new [
	"Answer a new initialized resource registry.

	 Answers:
		<McpResourceRegistry>."

	^super new initialize
]

{ #category : 'Registration' }
McpResourceRegistry >> includesResourceAt: aUri [
	"Answer whether a resource is registered at a URI.

	 Arguments:
		aUri - <String> resource URI.
	 Answers:
		<Boolean>."

	^self registryMutex critical: [resources includesKey: aUri]
]

{ #category : 'Initialization',
  #vaVisibility : 'private' }
McpResourceRegistry >> initialize [
	"Initialize empty synchronized registry state.

	 Answers:
		<McpResourceRegistry> the receiver."

	super initialize.
	resources := EsOrderedDictionary new.
	registryMutex := Semaphore forMutualExclusion.
	^self
]

{ #category : 'Registration' }
McpResourceRegistry >> registerResource: aResource [
	"Validate and register one uniquely identified resource.

	 Arguments:
		aResource - <McpResource> resource implementation.
	 Answers:
		<McpResource> the registered resource."

	| resourceUri |

	self validateResource: aResource.
	resourceUri := aResource uri.
	self registryMutex critical: [
		(resources includesKey: resourceUri)
			ifTrue: [self error: 'Resource already registered: ' , resourceUri].
		resources at: resourceUri put: aResource].
	^aResource
]

{ #category : 'Accessing',
  #vaVisibility : 'private' }
McpResourceRegistry >> registryMutex [
	"Answer the mutex protecting registry structure.

	 Answers:
		<Semaphore>."

	^registryMutex
]

{ #category : 'Registration' }
McpResourceRegistry >> resourceAt: aUri ifAbsent: absentBlock [
	"Answer a resource at a URI or evaluate an absence block.

	 Arguments:
		aUri - <String> resource URI.
		absentBlock - <Block> evaluated when no resource is registered.
	 Answers:
		<McpResource> or the absence-block result."

	| resource found |

	found := true.
	self registryMutex critical: [resource := resources at: aUri ifAbsent: [found := false]].
	^found ifTrue: [resource] ifFalse: [absentBlock value]
]

{ #category : 'Protocol Operations' }
McpResourceRegistry >> resources [
	"Answer a structural snapshot of registered resources.

	 Answers:
		<KeyedCollection> URI-to-resource mapping."

	^self registryMutex critical: [resources copy]
]

{ #category : 'Accessing' }
McpResourceRegistry >> size [
	"Answer the number of registered resources.

	 Answers:
		<Integer>."

	^self registryMutex critical: [resources size]
]

{ #category : 'Registration' }
McpResourceRegistry >> unregisterResourceAt: aUri [
	"Remove and answer a resource registered at a URI.

	 Arguments:
		aUri - <String> nonempty resource URI.
	 Answers:
		<McpResource> or nil."

	(aUri isString and: [aUri isEmpty not])
		ifFalse: [self error: 'Resource URI must be a nonempty string'].
	^self registryMutex critical: [resources removeKey: aUri ifAbsent: [nil]]
]

{ #category : 'Validation',
  #vaVisibility : 'private' }
McpResourceRegistry >> validateResource: aResource [
	"Validate a resource before entering the registry.

	 Arguments:
		aResource - <Object> registration candidate.
	 Answers:
		<McpResourceRegistry> the receiver."

	| resourceUri resourceName |

	(aResource isKindOf: McpResource)
		ifFalse: [self error: 'Only McpResource instances can be registered'].
	resourceUri := aResource uri.
	(resourceUri isString and: [resourceUri isEmpty not])
		ifFalse: [self error: 'Resource URI must be a nonempty string'].
	resourceName := aResource name.
	(resourceName isString and: [resourceName isEmpty not])
		ifFalse: [self error: 'Resource name must be a nonempty string'].
	aResource asMcpDefinition.
	^self
]
