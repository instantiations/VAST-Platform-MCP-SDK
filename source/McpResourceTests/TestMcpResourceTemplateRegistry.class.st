"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# TestMcpResourceTemplateRegistry

`TestMcpResourceTemplateRegistry` verifies resource-template registration.

## Responsibilities

- Verify unique URI-template registration and public lookup.
- Verify template metadata and structural URI-template validation.
- Verify zero, one, and ambiguous concrete-URI matches.
- Verify matcher and reader block contracts.

Each test creates a fresh registry and shares no mutable template metadata.
"
Class {
	#name : 'TestMcpResourceTemplateRegistry',
	#superclass : 'TestCase',
	#instVars : [
		'registry'
	],
	#category : 'McpResourceTests'
}

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpResourceTemplateRegistry >> emptyReadResult [
	"Answer a valid empty ReadResourceResult."

	^EsOrderedDictionary with: 'contents' -> #()
]

{ #category : 'Initialization' }
TestMcpResourceTemplateRegistry >> setUp [
	"Create a fresh resource-template registry."

	super setUp.
	registry := McpResourceTemplateRegistry new
]

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpResourceTemplateRegistry >> template: templateString name: templateName match: matcher read: reader [
	"Answer a configured block resource template."

	^McpBlockResourceTemplate new
		uriTemplate: templateString;
		name: templateName;
		matchBlock: matcher;
		readBlock: reader;
		yourself
]

{ #category : 'Validation' }
TestMcpResourceTemplateRegistry >> testAmbiguousTemplateMatchIsRejected [
	"A concrete URI cannot resolve through multiple templates."

	| first second |

	first :=
		self
			template: 'test://first/{id}'
			name: 'first'
			match: [:uri | true]
			read: [:uri | self emptyReadResult].
	second :=
		self
			template: 'test://second/{id}'
			name: 'second'
			match: [:uri | true]
			read: [:uri | self emptyReadResult].
	registry
		registerTemplate: first;
		registerTemplate: second.
	self should: [registry templateMatchingUri: 'test://items/42' ifAbsent: [nil]] raise: Error
]

{ #category : 'Dispatching' }
TestMcpResourceTemplateRegistry >> testAutomaticTemplateMatchingWithoutMatchBlock [
	"McpBlockResourceTemplate matches URIs automatically when matchBlock is omitted."

	| template matched context |

	template :=
		McpBlockResourceTemplate new
			uriTemplate: 'test://items/{id}';
			name: 'items_template';
			readBlock: [:uri :ctx | self emptyReadResult];
			yourself.
	registry registerTemplate: template.

	matched := registry templateMatchingUri: 'test://items/item-123' ifAbsent: [nil].
	self assert: matched == template.

	context := McpServerRequestContext new.
	template readUri: 'test://items/item-123' context: context.
	self assert: ((context metadata at: 'variables') at: 'id') equals: 'item-123'
]

{ #category : 'Registration' }
TestMcpResourceTemplateRegistry >> testDuplicateRegistrationPreservesOriginalTemplate [
	"Duplicate template strings do not replace the registered template."

	| original duplicate signaledError |

	original :=
		self
			template: 'test://items/{id}'
			name: 'original'
			match: [:uri | true]
			read: [:uri | self emptyReadResult].
	duplicate :=
		self
			template: 'test://items/{id}'
			name: 'replacement'
			match: [:uri | true]
			read: [:uri | self emptyReadResult].
	registry registerTemplate: original.
	signaledError := nil.
	[registry registerTemplate: duplicate]
		on: Error
		do: [:error |
			signaledError := error.
			error return].
	self assert: signaledError notNil.
	self
		assert: signaledError messageText
		equals: 'Resource template already registered: test://items/{id}'.
	self assert: (registry templates at: 'test://items/{id}') equals: original.
	self assert: registry size equals: 1
]

{ #category : 'Validation' }
TestMcpResourceTemplateRegistry >> testMatcherAndReaderRejectInvalidArity [
	"Template matcher and reader blocks enforce their public contracts."

	| template |

	template :=
		McpBlockResourceTemplate new
			uriTemplate: 'test://items/{id}';
			name: 'items';
			yourself.
	self should: [template matchBlock: [true]] raise: Error.
	self should: [template readBlock: [self emptyReadResult]] raise: Error
]

{ #category : 'Registration' }
TestMcpResourceTemplateRegistry >> testRegistrationSupportsPublicLookup [
	"Registration exposes the template through public registry snapshots."

	| template |

	template :=
		self
			template: 'test://items/{id}'
			name: 'items'
			match: [:uri | uri = 'test://items/42']
			read: [:uri | self emptyReadResult].
	self assert: (registry registerTemplate: template) equals: template.
	self assert: (registry includesTemplate: 'test://items/{id}').
	self assert: (registry templates at: 'test://items/{id}') == template.
	self assert: registry size equals: 1
]

{ #category : 'Serialization' }
TestMcpResourceTemplateRegistry >> testTemplateDefinitionIncludesConfiguredMetadata [
	"A template definition includes configured descriptive metadata."

	| template definition |

	template :=
		self
			template: 'test://items/{id}'
			name: 'items'
			match: [:uri | true]
			read: [:uri | self emptyReadResult].
	template
		title: 'Items';
		description: 'Parameterized item resource';
		mimeType: 'application/json'.
	definition := template asMcpDefinition.
	self assert: (definition at: 'uriTemplate') equals: 'test://items/{id}'.
	self assert: (definition at: 'name') equals: 'items'.
	self assert: (definition at: 'title') equals: 'Items'.
	self assert: (definition at: 'description') equals: 'Parameterized item resource'.
	self assert: (definition at: 'mimeType') equals: 'application/json'
]

{ #category : 'Dispatching' }
TestMcpResourceTemplateRegistry >> testTemplateMatchingReturnsMatchOrAbsentValue [
	"Template matching returns one match or evaluates the absence block."

	| template match absent |

	template :=
		self
			template: 'test://items/{id}'
			name: 'items'
			match: [:uri | uri = 'test://items/42']
			read: [:uri | self emptyReadResult].
	registry registerTemplate: template.
	match := registry templateMatchingUri: 'test://items/42' ifAbsent: [nil].
	absent := registry templateMatchingUri: 'test://items/99' ifAbsent: [#absent].
	self assert: match == template.
	self assert: absent equals: #absent
]

{ #category : 'Validation' }
TestMcpResourceTemplateRegistry >> testTemplateRejectsMalformedUriTemplate [
	"A template requires balanced nonempty URI-template expressions."

	self should: [McpBlockResourceTemplate new uriTemplate: 'test://items/{id'] raise: Error
]

{ #category : 'Dispatching' }
TestMcpResourceTemplateRegistry >> testUriTemplateMatchingAndVariableExtraction [
	"McpUriTemplate extracts variables from matching URIs and supports expansion."

	| template vars expanded |

	template := McpUriTemplate template: 'test://users/{userId}/posts/{postId}'.
	self assert: (template matchesUri: 'test://users/42/posts/99').
	self deny: (template matchesUri: 'test://users/42').
	self deny: (template matchesUri: 'test://users/42/posts/99/comments').

	vars := template matchUri: 'test://users/42/posts/99'.
	self assert: (vars at: 'userId') equals: '42'.
	self assert: (vars at: 'postId') equals: '99'.

	expanded := template expand: (Dictionary with: 'userId' -> 'bob' with: 'postId' -> 'first').
	self assert: expanded equals: 'test://users/bob/posts/first'
]
