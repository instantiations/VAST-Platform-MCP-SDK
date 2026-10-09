"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# McpResource

`McpResource` describes one concrete MCP resource and its read contract.

## Responsibilities

- Validate absolute resource identity and protocol metadata.
- Expose a detached MCP definition before subclass-defined reads.

## Lifecycle and boundaries

Registries own resource identity; read results are request scoped.
"
Class {
	#name : 'McpResource',
	#superclass : 'Object',
	#instVars : [
		'uri',
		'name',
		'title',
		'description',
		'mimeType',
		'annotations',
		'size',
		'icons',
		'meta'
	],
	#category : 'McpResources'
}

{ #category : 'Accessing' }
McpResource >> annotations [
	"Answer a detached copy of optional resource annotations.

	 Answers:
		<KeyedCollection> or nil."

	annotations ifNil: [^nil].
	^self detachedProtocolValue: annotations
]

{ #category : 'Accessing' }
McpResource >> annotations: aDictionary [
	"Set optional client usage annotations.

	 Arguments:
		aDictionary - <KeyedCollection> JSON-compatible annotations, or nil.
	 Answers:
		<McpResource> the receiver."

	(aDictionary isNil or: [aDictionary isKindOf: KeyedCollection])
		ifFalse: [self error: 'Resource annotations must be keyed or nil'].
	annotations := aDictionary ifNotNil: [self detachedProtocolValue: aDictionary].
	^self
]

{ #category : 'Serialization' }
McpResource >> asMcpDefinition [
	"Answer a detached MCP resource definition.

	 Answers:
		<KeyedCollection> JSON-compatible resource definition."

	| definition |

	definition :=
		EsOrderedDictionary new
			at: 'uri' put: self uri;
			at: 'name' put: self name;
			yourself.
	self title ifNotNil: [:value | definition at: 'title' put: value].
	self description ifNotNil: [:value | definition at: 'description' put: value].
	self mimeType ifNotNil: [:value | definition at: 'mimeType' put: value].
	self annotations ifNotNil: [:value | definition at: 'annotations' put: value].
	self size ifNotNil: [:value | definition at: 'size' put: value].
	self icons ifNotNil: [:value | definition at: 'icons' put: value].
	self meta ifNotNil: [:value | definition at: '_meta' put: value].
	^definition
]

{ #category : 'Accessing' }
McpResource >> description [
	"Answer a copy of the optional human-readable description.

	 Answers:
		<String> or nil."

	description ifNil: [^nil].
	^description copy
]

{ #category : 'Accessing' }
McpResource >> description: aString [
	"Set the optional human-readable description.

	 Arguments:
		aString - <String> description, or nil.
	 Answers:
		<McpResource> the receiver."

	(aString isNil or: [aString isString])
		ifFalse: [self error: 'Resource description must be a string or nil'].
	description := aString ifNotNil: [aString copy].
	^self
]

{ #category : 'Serialization',
  #vaVisibility : 'private' }
McpResource >> detachedProtocolValue: anObject [
	"Answer an isolated copy of a JSON-compatible protocol value.

	 Arguments:
		anObject - <Object> JSON-compatible value.
	 Answers:
		<Object> detached value."

	^self detachedProtocolValue: anObject visited: IdentitySet new
]

{ #category : 'Serialization',
  #vaVisibility : 'private' }
McpResource >> detachedProtocolValue: anObject visited: visitedObjects [
	"Copy a protocol value while rejecting cycles and arbitrary objects.

	 Arguments:
		anObject - <Object> value being copied.
		visitedObjects - <IdentitySet> active containers.
	 Answers:
		<Object> detached JSON-compatible value."

	| detached |

	anObject ifNil: [^nil].
	anObject isBoolean ifTrue: [^anObject].
	anObject isNumber ifTrue: [^anObject].
	anObject isString ifTrue: [^anObject copy].
	(visitedObjects includes: anObject) ifTrue: [self error: 'MCP protocol value contains a cycle'].
	(anObject isKindOf: KeyedCollection)
		ifTrue: [
			visitedObjects add: anObject.
			[
				detached := EsOrderedDictionary new.
				anObject keysAndValuesDo: [:key :value |
					key isString ifFalse: [self error: 'MCP protocol object keys must be strings'].
					detached
						at: key copy
						put: (self detachedProtocolValue: value visited: visitedObjects)]]
							ensure: [visitedObjects remove: anObject ifAbsent: []].
			^detached].
	(anObject isKindOf: SequenceableCollection)
		ifTrue: [
			visitedObjects add: anObject.
			[
				detached :=
					anObject
						collect: [:value | self detachedProtocolValue: value visited: visitedObjects]]
							ensure: [visitedObjects remove: anObject ifAbsent: []].
			^detached asArray].
	self error: 'MCP resource metadata contains a non-JSON-compatible value'
]

{ #category : 'Accessing' }
McpResource >> icons [
	"Answer detached copies of the optional icon definitions.

	 Answers:
		<Array> of <KeyedCollection>, or nil."

	icons ifNil: [^nil].
	^self detachedProtocolValue: icons
]

{ #category : 'Accessing' }
McpResource >> icons: aCollection [
	"Set optional icon definitions.

	 Arguments:
		aCollection - <SequenceableCollection> of keyed icons, or nil.
	 Answers:
		<McpResource> the receiver."

	(aCollection isNil
		or: [(aCollection isKindOf: SequenceableCollection) and: [aCollection isString not]])
			ifFalse: [self error: 'Resource icons must be an array or nil'].
	aCollection ifNotNil: [
		(aCollection allSatisfy: [:icon | icon isKindOf: KeyedCollection])
			ifFalse: [self error: 'Resource icons must contain keyed definitions']].
	icons := aCollection ifNotNil: [self detachedProtocolValue: aCollection].
	^self
]

{ #category : 'Validation',
  #vaVisibility : 'private' }
McpResource >> isValidUriSchemeCharacter: aCharacter first: isFirst [
	"Answer whether a character is valid in an absolute URI scheme.

	 Arguments:
		aCharacter - <Character> scheme character.
		isFirst - <Boolean> whether this begins the scheme.
	 Answers:
		<Boolean>."

	| codePoint isLetter |

	codePoint := aCharacter codePoint.
	isLetter :=
		(codePoint between: $A codePoint and: $Z codePoint)
			or: [codePoint between: $a codePoint and: $z codePoint].
	isFirst ifTrue: [^isLetter].
	^isLetter or: [
		(codePoint between: $0 codePoint and: $9 codePoint)
			or: [aCharacter = $+ or: [aCharacter = $- or: [aCharacter = $.]]]]
]

{ #category : 'Accessing' }
McpResource >> meta [
	"Answer a detached copy of optional protocol extension metadata.

	 Answers:
		<KeyedCollection> or nil."

	meta ifNil: [^nil].
	^self detachedProtocolValue: meta
]

{ #category : 'Accessing' }
McpResource >> meta: aDictionary [
	"Set optional protocol extension metadata serialized as `_meta`.

	 Arguments:
		aDictionary - <KeyedCollection> JSON-compatible metadata, or nil.
	 Answers:
		<McpResource> the receiver."

	(aDictionary isNil or: [aDictionary isKindOf: KeyedCollection])
		ifFalse: [self error: 'Resource metadata must be a keyed collection or nil'].
	meta := aDictionary ifNotNil: [self detachedProtocolValue: aDictionary].
	^self
]

{ #category : 'Accessing' }
McpResource >> mimeType [
	"Answer a copy of the optional MIME type.

	 Answers:
		<String> or nil."

	mimeType ifNil: [^nil].
	^mimeType copy
]

{ #category : 'Accessing' }
McpResource >> mimeType: aString [
	"Set the optional MIME type.

	 Arguments:
		aString - <String> nonempty MIME type, or nil.
	 Answers:
		<McpResource> the receiver."

	(aString isNil or: [aString isString and: [aString isEmpty not]])
		ifFalse: [self error: 'Resource MIME type must be nonempty or nil'].
	mimeType := aString ifNotNil: [aString copy].
	^self
]

{ #category : 'Accessing' }
McpResource >> name [
	"Answer a copy of the logical resource name.

	 Answers:
		<String> or nil."

	name ifNil: [^nil].
	^name copy
]

{ #category : 'Accessing' }
McpResource >> name: aString [
	"Set the logical resource name.

	 Arguments:
		aString - <String> nonempty logical name.
	 Answers:
		<McpResource> the receiver."

	(aString isString and: [aString isEmpty not])
		ifFalse: [self error: 'Resource name must be a nonempty string'].
	name := aString copy.
	^self
]

{ #category : 'Execution' }
McpResource >> readWithContext: requestContext [
	"Read the resource using optional request-scoped state.

	 Arguments:
		requestContext - <McpServerRequestContext> or nil.
	 Answers:
		<KeyedCollection> MCP ReadResourceResult."

	self subclassResponsibility
]

{ #category : 'Accessing' }
McpResource >> size [
	"Answer the optional raw resource size in bytes.

	 Answers:
		<Integer> nonnegative size, or nil."

	^size
]

{ #category : 'Accessing' }
McpResource >> size: anInteger [
	"Set the optional raw resource size in bytes.

	 Arguments:
		anInteger - <Integer> nonnegative size, or nil.
	 Answers:
		<McpResource> the receiver."

	(anInteger isNil or: [anInteger isInteger and: [anInteger >= 0]])
		ifFalse: [self error: 'Resource size must be a nonnegative integer or nil'].
	size := anInteger.
	^self
]

{ #category : 'Accessing' }
McpResource >> title [
	"Answer a copy of the optional human-readable display title.

	 Answers:
		<String> or nil."

	title ifNil: [^nil].
	^title copy
]

{ #category : 'Accessing' }
McpResource >> title: aString [
	"Set the optional human-readable display title.

	 Arguments:
		aString - <String> nonempty title, or nil.
	 Answers:
		<McpResource> the receiver."

	(aString isNil or: [aString isString and: [aString isEmpty not]])
		ifFalse: [self error: 'Resource title must be a nonempty string or nil'].
	title := aString ifNotNil: [aString copy].
	^self
]

{ #category : 'Accessing' }
McpResource >> uri [
	"Answer a copy of the unique resource URI.

	 Answers:
		<String> or nil."

	uri ifNil: [^nil].
	^uri copy
]

{ #category : 'Accessing' }
McpResource >> uri: aString [
	"Set the unique resource URI.

	 Arguments:
		aString - <String> nonempty URI.
	 Answers:
		<McpResource> the receiver."

	(aString isString and: [aString isEmpty not])
		ifFalse: [self error: 'Resource URI must be a nonempty string'].
	self validateUri: aString.
	uri := aString copy.
	^self
]

{ #category : 'Validation',
  #vaVisibility : 'private' }
McpResource >> validateUri: aString [
	"Validate the scheme portion of an absolute resource URI.

	 Arguments:
		aString - <String> resource URI.
	 Answers:
		<McpResource> the receiver."

	| colonIndex scheme index |

	colonIndex := aString indexOf: $:.
	colonIndex > 1 ifFalse: [self error: 'Resource URI must be absolute'].
	scheme := aString copyFrom: 1 to: colonIndex - 1.
	index := 0.
	(scheme allSatisfy: [:character |
		index := index + 1.
		self isValidUriSchemeCharacter: character first: index = 1])
			ifFalse: [self error: 'Resource URI has an invalid scheme'].
	^self
]
