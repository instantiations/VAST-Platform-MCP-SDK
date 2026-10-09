"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# McpPrompt

`McpPrompt` describes one named MCP prompt and its argument schema.

## Responsibilities

- Validate prompt identity, metadata, icons, and argument definitions.
- Render through subclass-defined behavior and detach protocol output.

## Lifecycle and boundaries

Registries own prompt identity; accessors preserve value boundaries.
"
Class {
	#name : 'McpPrompt',
	#superclass : 'Object',
	#instVars : [
		'name',
		'title',
		'description',
		'arguments',
		'icons',
		'meta'
	],
	#category : 'McpPrompts'
}

{ #category : 'Accessing' }
McpPrompt >> arguments [
	"Answer detached copies of the optional argument definitions.

	 Answers:
		<Array> of <KeyedCollection>, or nil."

	arguments ifNil: [^nil].
	^self detachedProtocolValue: arguments
]

{ #category : 'Accessing' }
McpPrompt >> arguments: aCollection [
	"Set and validate optional prompt argument definitions.

	 Arguments:
		aCollection - <SequenceableCollection> of definitions, or nil.
	 Answers:
		<McpPrompt> the receiver."

	self validateArgumentDefinitions: aCollection.
	arguments := aCollection ifNotNil: [self detachedProtocolValue: aCollection].
	^self
]

{ #category : 'Serialization' }
McpPrompt >> asMcpDefinition [
	"Answer a detached MCP prompt definition.

	 Answers:
		<KeyedCollection> JSON-compatible prompt definition."

	| definition |

	definition :=
		EsOrderedDictionary new
			at: 'name' put: self name;
			yourself.
	self title ifNotNil: [:value | definition at: 'title' put: value].
	self description ifNotNil: [:value | definition at: 'description' put: value].
	self arguments ifNotNil: [:value | definition at: 'arguments' put: value].
	self icons ifNotNil: [:value | definition at: 'icons' put: value].
	self meta ifNotNil: [:value | definition at: '_meta' put: value].
	^definition
]

{ #category : 'Accessing' }
McpPrompt >> description [
	"Answer a copy of the optional human-readable description.

	 Answers:
		<String> or nil."

	description ifNil: [^nil].
	^description copy
]

{ #category : 'Accessing' }
McpPrompt >> description: aString [
	"Set the optional human-readable description.

	 Arguments:
		aString - <String> description, or nil.
	 Answers:
		<McpPrompt> the receiver."

	(aString isNil or: [aString isString])
		ifFalse: [self error: 'Prompt description must be a string or nil'].
	description := aString ifNotNil: [aString copy].
	^self
]

{ #category : 'Serialization',
  #vaVisibility : 'private' }
McpPrompt >> detachedProtocolValue: anObject [
	"Answer an isolated copy of a JSON-compatible protocol value.

	 Arguments:
		anObject - <Object> JSON-compatible value.
	 Answers:
		<Object> detached value."

	^self detachedProtocolValue: anObject visited: IdentitySet new
]

{ #category : 'Serialization',
  #vaVisibility : 'private' }
McpPrompt >> detachedProtocolValue: anObject visited: visitedObjects [
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
	self error: 'MCP prompt metadata contains a non-JSON-compatible value'
]

{ #category : 'Accessing' }
McpPrompt >> icons [
	"Answer detached copies of the optional icon definitions.

	 Answers:
		<Array> of <KeyedCollection>, or nil."

	icons ifNil: [^nil].
	^self detachedProtocolValue: icons
]

{ #category : 'Accessing' }
McpPrompt >> icons: aCollection [
	"Set optional icon definitions.

	 Arguments:
		aCollection - <SequenceableCollection> of keyed icons, or nil.
	 Answers:
		<McpPrompt> the receiver."

	(aCollection isNil
		or: [(aCollection isKindOf: SequenceableCollection) and: [aCollection isString not]])
			ifFalse: [self error: 'Prompt icons must be an array or nil'].
	aCollection ifNotNil: [
		(aCollection allSatisfy: [:icon | icon isKindOf: KeyedCollection])
			ifFalse: [self error: 'Prompt icons must contain keyed definitions']].
	icons := aCollection ifNotNil: [self detachedProtocolValue: aCollection].
	^self
]

{ #category : 'Accessing' }
McpPrompt >> meta [
	"Answer a detached copy of optional protocol extension metadata.

	 Answers:
		<KeyedCollection> or nil."

	meta ifNil: [^nil].
	^self detachedProtocolValue: meta
]

{ #category : 'Accessing' }
McpPrompt >> meta: aDictionary [
	"Set optional protocol extension metadata serialized as `_meta`.

	 Arguments:
		aDictionary - <KeyedCollection> JSON-compatible metadata, or nil.
	 Answers:
		<McpPrompt> the receiver."

	(aDictionary isNil or: [aDictionary isKindOf: KeyedCollection])
		ifFalse: [self error: 'Prompt metadata must be a keyed collection or nil'].
	meta := aDictionary ifNotNil: [self detachedProtocolValue: aDictionary].
	^self
]

{ #category : 'Accessing' }
McpPrompt >> name [
	"Answer a copy of the case-sensitive protocol name.

	 Answers:
		<String> or nil."

	name ifNil: [^nil].
	^name copy
]

{ #category : 'Accessing' }
McpPrompt >> name: aString [
	"Set the case-sensitive protocol name.

	 Arguments:
		aString - <String> nonempty protocol name.
	 Answers:
		<McpPrompt> the receiver."

	(aString isString and: [aString isEmpty not])
		ifFalse: [self error: 'Prompt name must be a nonempty string'].
	name := aString copy.
	^self
]

{ #category : 'Execution' }
McpPrompt >> renderWithArguments: argumentValues context: requestContext [
	"Render the prompt for validated argument values and request state.

	 Arguments:
		argumentValues - <KeyedCollection> prompt argument strings.
		requestContext - <McpServerRequestContext> or nil.
	 Answers:
		<KeyedCollection> MCP GetPromptResult."

	self subclassResponsibility
]

{ #category : 'Accessing' }
McpPrompt >> title [
	"Answer a copy of the optional human-readable display title.

	 Answers:
		<String> or nil."

	title ifNil: [^nil].
	^title copy
]

{ #category : 'Accessing' }
McpPrompt >> title: aString [
	"Set the optional human-readable display title.

	 Arguments:
		aString - <String> nonempty title, or nil.
	 Answers:
		<McpPrompt> the receiver."

	(aString isNil or: [aString isString and: [aString isEmpty not]])
		ifFalse: [self error: 'Prompt title must be a nonempty string or nil'].
	title := aString ifNotNil: [aString copy].
	^self
]

{ #category : 'Validation',
  #vaVisibility : 'private' }
McpPrompt >> validateArgumentDefinitions: aCollection [
	"Validate argument shape, field types, and unique names.

	 Arguments:
		aCollection - <SequenceableCollection> definitions, or nil.
	 Answers:
		<McpPrompt> the receiver."

	| names value |

	aCollection ifNil: [^self].
	((aCollection isKindOf: SequenceableCollection) and: [aCollection isString not])
		ifFalse: [self error: 'Prompt arguments must be an array or nil'].
	names := Set new.
	aCollection do: [:definition | | argumentName |
		(definition isKindOf: KeyedCollection)
			ifFalse: [self error: 'Prompt arguments must contain keyed definitions'].
		argumentName := definition at: 'name' ifAbsent: [nil].
		(argumentName isString and: [argumentName isEmpty not])
			ifFalse: [self error: 'Prompt argument name must be a nonempty string'].
		(names includes: argumentName)
			ifTrue: [self error: 'Duplicate prompt argument: ' , argumentName].
		names add: argumentName.
		#('title' 'description') do: [:field |
			value := definition at: field ifAbsent: [nil].
			(value isNil or: [value isString])
				ifFalse: [self error: 'Prompt argument ' , field , ' must be a string']].
		value := definition at: 'required' ifAbsent: [nil].
		(value isNil or: [value isBoolean])
			ifFalse: [self error: 'Prompt argument required must be boolean']].
	^self
]
