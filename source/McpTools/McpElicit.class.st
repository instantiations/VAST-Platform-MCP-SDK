"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# McpElicit

`McpElicit` is a request marker indicating that a tool resolver requires user input.

## Responsibilities

- Hold prompt message and optional requested input schema.
- Convert to wire representation (`elicitation/create`).

## Lifecycle and boundaries

Transient value object returned by tool resolvers.
"
Class {
	#name : 'McpElicit',
	#superclass : 'Object',
	#instVars : [
		'message',
		'schema',
		'mode',
		'url'
	],
	#category : 'McpTools'
}

{ #category : 'Instance Creation' }
McpElicit class >> message: aString schema: aSchemaDictionary [
	"Answer a new form-mode elicitation marker with a prompt message and expected schema.

	 Arguments:
		aString - <String> question to prompt the user with.
		aSchemaDictionary - <KeyedCollection> flat object JSON schema.
	 Answers:
		<McpElicit>."

	^self new initializeMessage: aString schema: aSchemaDictionary
]

{ #category : 'Instance Creation' }
McpElicit class >> message: aString url: aUrlString [
	"Answer a new URL-mode elicitation marker with a prompt message and target URL.

	 Arguments:
		aString - <String> human-readable message explaining why the interaction is needed.
		aUrlString - <String> URL that the user should navigate to.
	 Answers:
		<McpElicit>."

	^self new initializeMessage: aString url: aUrlString
]

{ #category : 'Converting' }
McpElicit >> asInputRequest [
	"Answer the MCP wire representation of this elicitation request.

	 Answers:
		<KeyedCollection>."

	| params |

	params :=
		EsOrderedDictionary new
			at: 'mode' put: self mode;
			at: 'message' put: self message;
			yourself.
	self mode = 'url'
		ifTrue: [params at: 'url' put: self url]
		ifFalse: [params at: 'requestedSchema' put: self schema].
	^EsOrderedDictionary new
		at: 'method' put: 'elicitation/create';
		at: 'params' put: params;
		yourself
]

{ #category : 'Initialization',
  #vaVisibility : 'private' }
McpElicit >> initializeMessage: aString schema: aSchemaDictionary [
	"Initialize form-mode elicitation properties.

	 Arguments:
		aString - <String> prompt message.
		aSchemaDictionary - <KeyedCollection> flat object JSON Schema.
	 Answers:
		<McpElicit> the receiver."

	super initialize.
	self validateMessage: aString.
	self validateSchema: aSchemaDictionary.
	mode := 'form'.
	message := aString copy.
	schema := aSchemaDictionary.
	url := nil.
	^self
]

{ #category : 'Initialization',
  #vaVisibility : 'private' }
McpElicit >> initializeMessage: aString url: aUrlString [
	"Initialize URL-mode elicitation properties.

	 Arguments:
		aString - <String> prompt message.
		aUrlString - <String> target URL.
	 Answers:
		<McpElicit> the receiver."

	super initialize.
	self validateMessage: aString.
	self validateUrl: aUrlString.
	mode := 'url'.
	message := aString copy.
	url := aUrlString copy.
	schema := nil.
	^self
]

{ #category : 'Accessing' }
McpElicit >> message [
	"Answer the prompt message string.

	 Answers:
		<String>."

	^message
]

{ #category : 'Accessing' }
McpElicit >> mode [
	"Answer the elicitation mode ('form' or 'url').

	 Answers:
		<String>."

	^mode ifNil: ['form']
]

{ #category : 'Accessing' }
McpElicit >> schema [
	"Answer the requested schema, or nil.

	 Answers:
		<KeyedCollection> or nil."

	^schema
]

{ #category : 'Accessing' }
McpElicit >> url [
	"Answer the target URL for URL-mode elicitation, or nil for form mode.

	 Answers:
		<String> or nil."

	^url
]

{ #category : 'Validation',
  #vaVisibility : 'private' }
McpElicit >> validateMessage: aString [
	"Validate that the elicitation prompt message is a nonempty string.

	 Arguments:
		aString - <Object> candidate message.
	 Answers:
		<McpElicit> the receiver."

	(aString isString and: [aString isEmpty not])
		ifFalse: [self error: 'McpElicit requires a nonempty message string'].
	^self
]

{ #category : 'Validation',
  #vaVisibility : 'private' }
McpElicit >> validatePropertySchema: aPropertySchema [
	"Validate that a single property definition in a form-mode requestedSchema
	 conforms to the restricted MCP elicitation schema subset (primitive types and enums).

	 Arguments:
		aPropertySchema - <Object> property schema candidate.
	 Answers:
		<McpElicit> the receiver."

	| propType format items itemType anyOf oneOf |

	(aPropertySchema isKindOf: KeyedCollection)
		ifFalse: [self error: 'McpElicit property schema must be a keyed collection'].
	propType := aPropertySchema at: 'type' ifAbsent: [nil].
	(#('string' 'number' 'integer' 'boolean' 'array') includes: propType)
		ifFalse: [
			self error:
				'McpElicit property schema type must be string, number, integer, boolean, or array'].
	propType = 'string'
		ifTrue: [
			format := aPropertySchema at: 'format' ifAbsent: [nil].
			(format isNil or: [#('email' 'uri' 'date' 'date-time') includes: format])
				ifFalse: [self error: 'McpElicit string schema has unsupported format'].
			oneOf := aPropertySchema at: 'oneOf' ifAbsent: [nil].
			oneOf ifNotNil: [
				((oneOf isKindOf: SequenceableCollection)
					and: [oneOf isString not and: [oneOf allSatisfy: [:entry |
						(entry isKindOf: KeyedCollection) and: [entry includesKey: 'const']]]])
							ifFalse: [
								self error:
									'McpElicit string oneOf must be a collection of const option objects']]].
	propType = 'array'
		ifTrue: [
			items := aPropertySchema at: 'items' ifAbsent: [nil].
			(items isKindOf: KeyedCollection)
				ifFalse: [self error: 'McpElicit array property schema requires an items object'].
			itemType := items at: 'type' ifAbsent: [nil].
			anyOf := items at: 'anyOf' ifAbsent: [nil].
			(itemType = 'string' and: [items includesKey: 'enum'])
				ifFalse: [
					((anyOf isKindOf: SequenceableCollection)
						and: [anyOf isString not and: [anyOf allSatisfy: [:entry |
							(entry isKindOf: KeyedCollection) and: [entry includesKey: 'const']]]])
								ifFalse: [
									self error:
										'McpElicit array property schema is restricted to multi-select enums']]].
	^self
]

{ #category : 'Validation',
  #vaVisibility : 'private' }
McpElicit >> validateSchema: aSchemaDictionary [
	"Validate that aSchemaDictionary is a flat object JSON Schema conforming to
	 the MCP form-mode elicitation specification.

	 Arguments:
		aSchemaDictionary - <Object> candidate schema.
	 Answers:
		<McpElicit> the receiver."

	| properties required |

	(aSchemaDictionary isKindOf: KeyedCollection)
		ifFalse: [self error: 'McpElicit form mode requires a keyed requestedSchema'].
	(aSchemaDictionary at: 'type' ifAbsent: [nil]) = 'object'
		ifFalse: [self error: 'McpElicit requestedSchema must have type ''object'''].
	properties := aSchemaDictionary at: 'properties' ifAbsent: [nil].
	(properties isNil or: [properties isKindOf: KeyedCollection])
		ifFalse: [self error: 'McpElicit requestedSchema properties must be a keyed collection'].
	properties ifNotNil: [
		properties keysAndValuesDo: [:propName :propDef |
			(propName isString and: [propName isEmpty not])
				ifFalse: [self error: 'McpElicit property names must be nonempty strings'].
			self validatePropertySchema: propDef]].
	required := aSchemaDictionary at: 'required' ifAbsent: [nil].
	required ifNotNil: [
		((required isKindOf: SequenceableCollection)
			and: [required isString not and: [required allSatisfy: [:each | each isString]]])
				ifFalse: [self error: 'McpElicit requestedSchema required must be an array of strings']].
	^self
]

{ #category : 'Validation',
  #vaVisibility : 'private' }
McpElicit >> validateUrl: aUrlString [
	"Validate that aUrlString is a syntactically valid absolute URL for URL-mode elicitation.

	 Arguments:
		aUrlString - <Object> candidate URL.
	 Answers:
		<McpElicit> the receiver."

	| colonIndex scheme index |

	(aUrlString isString and: [aUrlString isEmpty not])
		ifFalse: [self error: 'McpElicit URL mode requires a nonempty URL string'].
	colonIndex := aUrlString indexOf: $:.
	colonIndex > 1
		ifFalse: [self error: 'McpElicit URL must include a valid URI scheme'].
	scheme := aUrlString copyFrom: 1 to: colonIndex - 1.
	index := 0.
	(scheme allSatisfy: [:ch | | code isLetter |
		index := index + 1.
		code := ch codePoint.
		isLetter :=
			(code between: $A codePoint and: $Z codePoint)
				or: [code between: $a codePoint and: $z codePoint].
		index = 1
			ifTrue: [isLetter]
			ifFalse: [
				isLetter
					or: [
						(code between: $0 codePoint and: $9 codePoint)
							or: [ch = $+ or: [ch = $- or: [ch = $.]]]]]])
								ifFalse: [self error: 'McpElicit URL has an invalid URI scheme'].
	^self
]
