"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# McpResourceTemplate

`McpResourceTemplate` describes a URI-templated MCP resource and read
contract.

## Responsibilities

- Validate URI templates, metadata, and match behavior.
- Expose detached definitions before subclass-defined reads.

## Lifecycle and boundaries

Registries own template identity; read results are request scoped.
"
Class {
	#name : 'McpResourceTemplate',
	#superclass : 'Object',
	#instVars : [
		'uriTemplate',
		'name',
		'title',
		'description',
		'mimeType',
		'annotations',
		'icons',
		'meta'
	],
	#category : 'McpResources'
}

{ #category : 'Accessing' }
McpResourceTemplate >> annotations [
	"Answer a detached copy of optional template annotations.

	 Answers:
		<KeyedCollection> or nil."

	annotations ifNil: [^nil].
	^self detachedProtocolValue: annotations
]

{ #category : 'Accessing' }
McpResourceTemplate >> annotations: aDictionary [
	"Set optional client usage annotations.

	 Arguments:
		aDictionary - <KeyedCollection> JSON-compatible annotations, or nil.
	 Answers:
		<McpResourceTemplate> the receiver."

	(aDictionary isNil or: [aDictionary isKindOf: KeyedCollection])
		ifFalse: [self error: 'Template annotations must be keyed or nil'].
	annotations := aDictionary ifNotNil: [self detachedProtocolValue: aDictionary].
	^self
]

{ #category : 'Serialization' }
McpResourceTemplate >> asMcpDefinition [
	"Answer a detached MCP resource-template definition.

	 Answers:
		<KeyedCollection> JSON-compatible template definition."

	| definition |

	definition :=
		EsOrderedDictionary new
			at: 'uriTemplate' put: self uriTemplate;
			at: 'name' put: self name;
			yourself.
	self title ifNotNil: [:value | definition at: 'title' put: value].
	self description ifNotNil: [:value | definition at: 'description' put: value].
	self mimeType ifNotNil: [:value | definition at: 'mimeType' put: value].
	self annotations ifNotNil: [:value | definition at: 'annotations' put: value].
	self icons ifNotNil: [:value | definition at: 'icons' put: value].
	self meta ifNotNil: [:value | definition at: '_meta' put: value].
	^definition
]

{ #category : 'Accessing' }
McpResourceTemplate >> description [
	"Answer a copy of the optional human-readable description.

	 Answers:
		<String> or nil."

	description ifNil: [^nil].
	^description copy
]

{ #category : 'Accessing' }
McpResourceTemplate >> description: aString [
	"Set the optional human-readable description.

	 Arguments:
		aString - <String> description, or nil.
	 Answers:
		<McpResourceTemplate> the receiver."

	(aString isNil or: [aString isString])
		ifFalse: [self error: 'Template description must be a string or nil'].
	description := aString ifNotNil: [aString copy].
	^self
]

{ #category : 'Serialization',
  #vaVisibility : 'private' }
McpResourceTemplate >> detachedProtocolValue: anObject [
	"Answer an isolated copy of a JSON-compatible protocol value.

	 Arguments:
		anObject - <Object> JSON-compatible value.
	 Answers:
		<Object> detached value."

	^self detachedProtocolValue: anObject visited: IdentitySet new
]

{ #category : 'Serialization',
  #vaVisibility : 'private' }
McpResourceTemplate >> detachedProtocolValue: anObject visited: visitedObjects [
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
	self error: 'MCP template metadata contains a non-JSON-compatible value'
]

{ #category : 'Accessing' }
McpResourceTemplate >> icons [
	"Answer detached copies of the optional icon definitions.

	 Answers:
		<Array> of <KeyedCollection>, or nil."

	icons ifNil: [^nil].
	^self detachedProtocolValue: icons
]

{ #category : 'Accessing' }
McpResourceTemplate >> icons: aCollection [
	"Set optional icon definitions.

	 Arguments:
		aCollection - <SequenceableCollection> of keyed icons, or nil.
	 Answers:
		<McpResourceTemplate> the receiver."

	(aCollection isNil
		or: [(aCollection isKindOf: SequenceableCollection) and: [aCollection isString not]])
			ifFalse: [self error: 'Template icons must be an array or nil'].
	aCollection ifNotNil: [
		(aCollection allSatisfy: [:icon | icon isKindOf: KeyedCollection])
			ifFalse: [self error: 'Template icons must contain keyed definitions']].
	icons := aCollection ifNotNil: [self detachedProtocolValue: aCollection].
	^self
]

{ #category : 'Validation',
  #vaVisibility : 'private' }
McpResourceTemplate >> isValidUriSchemeCharacter: aCharacter first: isFirst [
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

{ #category : 'Validation' }
McpResourceTemplate >> matchesUri: aUri [
	"Answer whether this template accepts a concrete resource URI.

	 Arguments:
		aUri - <String> absolute resource URI.
	 Answers:
		<Boolean>."

	self subclassResponsibility
]

{ #category : 'Accessing' }
McpResourceTemplate >> meta [
	"Answer a detached copy of optional protocol extension metadata.

	 Answers:
		<KeyedCollection> or nil."

	meta ifNil: [^nil].
	^self detachedProtocolValue: meta
]

{ #category : 'Accessing' }
McpResourceTemplate >> meta: aDictionary [
	"Set optional protocol extension metadata serialized as `_meta`.

	 Arguments:
		aDictionary - <KeyedCollection> JSON-compatible metadata, or nil.
	 Answers:
		<McpResourceTemplate> the receiver."

	(aDictionary isNil or: [aDictionary isKindOf: KeyedCollection])
		ifFalse: [self error: 'Template metadata must be a keyed collection or nil'].
	meta := aDictionary ifNotNil: [self detachedProtocolValue: aDictionary].
	^self
]

{ #category : 'Accessing' }
McpResourceTemplate >> mimeType [
	"Answer a copy of the optional MIME type.

	 Answers:
		<String> or nil."

	mimeType ifNil: [^nil].
	^mimeType copy
]

{ #category : 'Accessing' }
McpResourceTemplate >> mimeType: aString [
	"Set the optional MIME type shared by matching resources.

	 Arguments:
		aString - <String> nonempty MIME type, or nil.
	 Answers:
		<McpResourceTemplate> the receiver."

	(aString isNil or: [aString isString and: [aString isEmpty not]])
		ifFalse: [self error: 'Template MIME type must be nonempty or nil'].
	mimeType := aString ifNotNil: [aString copy].
	^self
]

{ #category : 'Accessing' }
McpResourceTemplate >> name [
	"Answer a copy of the logical template name.

	 Answers:
		<String> or nil."

	name ifNil: [^nil].
	^name copy
]

{ #category : 'Accessing' }
McpResourceTemplate >> name: aString [
	"Set the logical template name.

	 Arguments:
		aString - <String> nonempty logical name.
	 Answers:
		<McpResourceTemplate> the receiver."

	(aString isString and: [aString isEmpty not])
		ifFalse: [self error: 'Template name must be a nonempty string'].
	name := aString copy.
	^self
]

{ #category : 'Execution' }
McpResourceTemplate >> readUri: aUri context: requestContext [
	"Read a matching concrete URI with optional request-scoped state.

	 Arguments:
		aUri - <String> matching absolute resource URI.
		requestContext - <McpServerRequestContext> or nil.
	 Answers:
		<KeyedCollection> MCP ReadResourceResult."

	self subclassResponsibility
]

{ #category : 'Accessing' }
McpResourceTemplate >> title [
	"Answer a copy of the optional human-readable display title.

	 Answers:
		<String> or nil."

	title ifNil: [^nil].
	^title copy
]

{ #category : 'Accessing' }
McpResourceTemplate >> title: aString [
	"Set the optional human-readable display title.

	 Arguments:
		aString - <String> nonempty title, or nil.
	 Answers:
		<McpResourceTemplate> the receiver."

	(aString isNil or: [aString isString and: [aString isEmpty not]])
		ifFalse: [self error: 'Template title must be a nonempty string or nil'].
	title := aString ifNotNil: [aString copy].
	^self
]

{ #category : 'Accessing' }
McpResourceTemplate >> uriTemplate [
	"Answer a copy of the advertised RFC 6570 URI template.

	 Answers:
		<String> or nil."

	uriTemplate ifNil: [^nil].
	^uriTemplate copy
]

{ #category : 'Accessing' }
McpResourceTemplate >> uriTemplate: aString [
	"Set and structurally validate the RFC 6570 URI template.

	 Arguments:
		aString - <String> absolute URI template.
	 Answers:
		<McpResourceTemplate> the receiver."

	(aString isString and: [aString isEmpty not])
		ifFalse: [self error: 'Resource template must be a nonempty string'].
	self validateUriTemplate: aString.
	uriTemplate := aString copy.
	^self
]

{ #category : 'Validation',
  #vaVisibility : 'private' }
McpResourceTemplate >> validateUriTemplate: aString [
	"Validate absolute scheme and balanced, nonempty template expressions.

	 Arguments:
		aString - <String> URI-template candidate.
	 Answers:
		<McpResourceTemplate> the receiver."

	| colonIndex scheme index insideExpression expressionHasContent |

	colonIndex := aString indexOf: $:.
	colonIndex > 1 ifFalse: [self error: 'Resource template must use an absolute URI scheme'].
	scheme := aString copyFrom: 1 to: colonIndex - 1.
	index := 0.
	(scheme allSatisfy: [:character |
		index := index + 1.
		self isValidUriSchemeCharacter: character first: index = 1])
			ifFalse: [self error: 'Resource template has an invalid URI scheme'].
	insideExpression := false.
	expressionHasContent := false.
	aString do: [:character |
		character = ${
			ifTrue: [
				insideExpression ifTrue: [self error: 'Resource template expressions cannot nest'].
				insideExpression := true.
				expressionHasContent := false]
			ifFalse: [
				character = $}
					ifTrue: [
						(insideExpression and: [expressionHasContent])
							ifFalse: [self error: 'Resource template expression is malformed'].
						insideExpression := false]
					ifFalse: [insideExpression ifTrue: [expressionHasContent := true]]]].
	insideExpression ifTrue: [self error: 'Resource template expression is not closed'].
	^self
]
