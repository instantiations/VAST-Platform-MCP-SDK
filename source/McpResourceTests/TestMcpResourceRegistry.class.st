"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# TestMcpResourceRegistry

`TestMcpResourceRegistry` verifies concrete resource registration invariants.

## Responsibilities

- Verify unique absolute URI registration and public lookup.
- Verify resource metadata serialization and defensive copying.
- Verify reader-block arity and resource URI validation.

Each test creates a fresh registry and shares no mutable resource metadata.
"
Class {
	#name : 'TestMcpResourceRegistry',
	#superclass : 'TestCase',
	#instVars : [
		'registry'
	],
	#category : 'McpResourceTests'
}

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpResourceRegistry >> emptyReadResult [
	"Answer a valid empty ReadResourceResult."

	^EsOrderedDictionary with: 'contents' -> #()
]

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpResourceRegistry >> resourceAt: uri name: resourceName block: readerBlock [
	"Answer a configured concrete block resource."

	^McpBlockResource new
		uri: uri;
		name: resourceName;
		block: readerBlock;
		yourself
]

{ #category : 'Initialization' }
TestMcpResourceRegistry >> setUp [
	"Create a fresh resource registry."

	super setUp.
	registry := McpResourceRegistry new
]

{ #category : 'Registration' }
TestMcpResourceRegistry >> testDuplicateRegistrationPreservesOriginalResource [
	"Duplicate URIs are rejected without replacing the registered resource."

	| original duplicate signaledError |

	original :=
		self resourceAt: 'test://resources/duplicate' name: 'original' block: [self emptyReadResult].
	duplicate :=
		self
			resourceAt: 'test://resources/duplicate'
			name: 'replacement'
			block: [self emptyReadResult].
	registry registerResource: original.
	signaledError := nil.
	[registry registerResource: duplicate]
		on: Error
		do: [:error |
			signaledError := error.
			error return].
	self assert: signaledError notNil.
	self
		assert: signaledError messageText
		equals: 'Resource already registered: test://resources/duplicate'.
	self assert: (registry resourceAt: 'test://resources/duplicate' ifAbsent: [nil]) equals: original.
	self assert: registry size equals: 1
]

{ #category : 'Validation' }
TestMcpResourceRegistry >> testReaderBlockRejectsUnsupportedArity [
	"A concrete resource reader accepts at most request context."

	| resource |

	resource :=
		McpBlockResource new
			uri: 'test://resources/arity';
			name: 'arity';
			yourself.
	self should: [resource block: [:context :extra | extra]] raise: Error
]

{ #category : 'Registration' }
TestMcpResourceRegistry >> testRegistrationSupportsPublicLookup [
	"Registration exposes the same resource through public lookup."

	| resource lookedUp |

	resource :=
		self resourceAt: 'test://resources/lookup' name: 'lookup' block: [self emptyReadResult].
	self assert: (registry registerResource: resource) equals: resource.
	self assert: (registry includesResourceAt: 'test://resources/lookup').
	lookedUp := registry resourceAt: 'test://resources/lookup' ifAbsent: [nil].
	self assert: lookedUp == resource.
	self assert: registry size equals: 1
]

{ #category : 'Serialization' }
TestMcpResourceRegistry >> testResourceDefinitionIncludesConfiguredMetadata [
	"A resource definition includes configured descriptive metadata."

	| resource definition |

	resource :=
		self resourceAt: 'test://resources/readme' name: 'README' block: [self emptyReadResult].
	resource
		title: 'Project README';
		description: 'Project documentation';
		mimeType: 'text/markdown';
		size: 128.
	definition := resource asMcpDefinition.
	self assert: (definition at: 'uri') equals: 'test://resources/readme'.
	self assert: (definition at: 'name') equals: 'README'.
	self assert: (definition at: 'title') equals: 'Project README'.
	self assert: (definition at: 'description') equals: 'Project documentation'.
	self assert: (definition at: 'mimeType') equals: 'text/markdown'.
	self assert: (definition at: 'size') equals: 128
]

{ #category : 'Copying' }
TestMcpResourceRegistry >> testResourceMetadataIsDefensivelyCopied [
	"Annotations cannot be mutated through either metadata boundary."

	| annotations resource returned |

	annotations := EsOrderedDictionary with: 'priority' -> 0.8.
	resource :=
		self resourceAt: 'test://resources/snapshot' name: 'snapshot' block: [self emptyReadResult].
	resource annotations: annotations.
	annotations at: 'priority' put: 0.1.
	self assert: (resource annotations at: 'priority') equals: 0.8.
	returned := resource annotations.
	returned at: 'priority' put: 0.2.
	self assert: (resource annotations at: 'priority') equals: 0.8
]

{ #category : 'Validation' }
TestMcpResourceRegistry >> testResourceRejectsRelativeUri [
	"A concrete resource requires an absolute URI."

	self should: [McpBlockResource new uri: 'relative/path'] raise: Error
]
