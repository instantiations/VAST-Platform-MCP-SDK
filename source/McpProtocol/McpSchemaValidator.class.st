"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

Validates the native MCP JSON Schema subset and document-local references.
Each instance belongs to one synchronous validation. It owns the active
value/schema stack; it never retrieves a schema from a network or file.
"
Class {
	#name : 'McpSchemaValidator',
	#superclass : 'Object',
	#instVars : [
		'rootSchema',
		'activePairs'
	],
	#pools : [
		'McpJsonRpcConstants'
	],
	#category : 'McpProtocol'
}

{ #category : 'Validation',
  #vaVisibility : 'private' }
McpSchemaValidator >> anchor: anchorText in: aSchema [
	"Find anchors in schema-bearing keywords, excluding instance data.
	Arguments:
		anchorText - <String> anchor name.
		aSchema - <Object> schema node.
	Answers:
		<KeyedCollection> or nil."
	| found child |
	(aSchema isKindOf: KeyedCollection) ifFalse: [^nil].
	(aSchema at: '$anchor' ifAbsent: [nil]) = anchorText ifTrue: [^aSchema].
	#('$defs' 'definitions' 'properties' 'patternProperties' 'dependentSchemas')
		do: [:keyword |
			child := aSchema at: keyword ifAbsent: [nil].
			(child isKindOf: KeyedCollection) ifTrue: [
				child valuesDo: [:node |
					found := self anchor: anchorText in: node.
					found ifNotNil: [^found]]]].
	#('items' 'additionalProperties' 'contains' 'not' 'if' 'then' 'else')
		do: [:keyword |
			found := self anchor: anchorText
				in: (aSchema at: keyword ifAbsent: [nil]).
			found ifNotNil: [^found]].
	#('allOf' 'anyOf' 'oneOf' 'prefixItems') do: [:keyword |
		child := aSchema at: keyword ifAbsent: [nil].
		((child isKindOf: SequenceableCollection) and: [child isString not])
			ifTrue: [child do: [:node |
				found := self anchor: anchorText in: node.
				found ifNotNil: [^found]]]].
	^nil

]

{ #category : 'Validation',
  #vaVisibility : 'private' }
McpSchemaValidator >> decodeFragment: fragmentText [
	"Decode percent-encoded UTF-8 without treating plus as a space.
	Arguments:
		fragmentText - <String> URI fragment.
	Answers:
		<String | UnicodeString> decoded fragment."
	| bytes index digits high low encoded |
	bytes := OrderedCollection new.
	encoded := fragmentText asUtf8Bytes.
	digits := '0123456789abcdef'.
	index := 1.
	[index <= encoded size] whileTrue: [
		(encoded at: index) = 37 ifTrue: [
			index + 2 > encoded size
				ifTrue: [self error: 'Incomplete schema fragment escape'].
			high := digits indexOf:
				(Character value: (encoded at: index + 1)) asLowercase.
			low := digits indexOf:
				(Character value: (encoded at: index + 2)) asLowercase.
			(high = 0 or: [low = 0])
				ifTrue: [self error: 'Invalid schema fragment escape'].
			bytes add: ((high - 1) * 16) + (low - 1).
			index := index + 3
		] ifFalse: [
			bytes add: (encoded at: index).
			index := index + 1]].
	^UnicodeString utf8: bytes asByteArray

]

{ #category : 'Validation',
  #vaVisibility : 'private' }
McpSchemaValidator >> decodePointerToken: tokenText [
	"Decode the two JSON Pointer escapes and reject malformed ones.
	Arguments:
		tokenText - <String> pointer token.
	Answers:
		<String> property name."
	| index out |
	index := 1.
	out := UnicodeString new.
	[
		[index <= tokenText size] whileTrue: [| character |
			character := tokenText at: index.
			character = $~ ifTrue: [
				index := index + 1.
				index > tokenText size
					ifTrue: [self error: 'Incomplete JSON Pointer escape'].
				character := tokenText at: index.
				(#($0 $1) includes: character)
					ifFalse: [self error: 'Invalid JSON Pointer escape'].
				character := character = $0 ifTrue: [$~] ifFalse: [$/]].
			out add: character.
			index := index + 1]] value.
	^out asEsString ifNil: [out]

]

{ #category : 'Validation',
  #vaVisibility : 'private' }
McpSchemaValidator >> pointerTokens: pointerText [
	"Split a pointer, retaining empty property names.
	Arguments:
		pointerText - <String> decoded fragment starting with slash.
	Answers:
		<OrderedCollection> raw pointer tokens."
	| tokens start |
	tokens := OrderedCollection new.
	start := 2.
	2 to: pointerText size do: [:index |
		(pointerText at: index) = $/ ifTrue: [
			tokens add: (pointerText copyFrom: start to: index - 1).
			start := index + 1]].
	tokens add: (pointerText copyFrom: start to: pointerText size).
	^tokens

]

{ #category : 'Validation',
  #vaVisibility : 'private' }
McpSchemaValidator >> resolveReference: referenceText [
	"Resolve a JSON Pointer or anchor strictly inside this document.
	Arguments:
		referenceText - <String> fragment reference or root-ID reference.
	Answers:
		<KeyedCollection | Boolean> referenced schema.
	Raises:
		<Error> malformed or unresolvable reference. No I/O is performed."
	| fragment rootId hashIndex target tokens |
	(referenceText isString and: [referenceText isSymbol not])
		ifFalse: [self error: 'MCP schema reference must be text'].
	fragment := referenceText.
	(fragment beginsWithSubCollection: '#') ifFalse: [
		rootId := rootSchema at: '$id' ifAbsent: [nil].
		hashIndex := fragment indexOf: $#.
		(rootId notNil and: [
			(hashIndex = 0 ifTrue: [fragment]
				ifFalse: [fragment copyFrom: 1 to: hashIndex - 1]) = rootId])
			ifFalse: [self error:
				'MCP schema reference is outside the document'].
		fragment := hashIndex = 0 ifTrue: ['#']
			ifFalse: [fragment copyFrom: hashIndex to: fragment size]].
	fragment := self decodeFragment: (fragment copyFrom: 2 to: fragment size).
	fragment isEmpty ifTrue: [^rootSchema].
	fragment first = $/ ifFalse: [
		target := self anchor: fragment in: rootSchema.
		target ifNil: [self error: 'MCP schema anchor does not resolve'].
		^target].
	target := rootSchema.
	tokens := self pointerTokens: fragment.
	tokens do: [:token | | key index |
		key := self decodePointerToken: token.
		(target isKindOf: KeyedCollection)
			ifTrue: [target := target at: key
				ifAbsent: [self error: 'MCP schema pointer does not resolve']]
			ifFalse: [
				((target isKindOf: SequenceableCollection)
					and: [target isString not])
					ifFalse: [self error:
				'MCP schema pointer crosses a scalar'].
				(key isEmpty or: [
					(key allSatisfy: [:c | c between: $0 and: $9]) not])
					ifTrue: [self error: 'MCP schema pointer index is invalid'].
				(key size > 1 and: [key first = $0])
					ifTrue: [self error:
				'MCP schema pointer index has a zero prefix'].
				index := key asNumber + 1.
				(index between: 1 and: target size)
					ifFalse: [self error:
				'MCP schema pointer index is outside array'].
				target := target at: index]].
	(target isBoolean or: [target isKindOf: KeyedCollection])
		ifFalse: [self error: 'MCP schema reference is not a schema'].
	^target

]

{ #category : 'Validation' }
McpSchemaValidator >> validate: aValue against: aSchema [
	"Validate one value using a fresh document and recursion stack.
	Arguments:
		aValue - <Object> JSON value.
		aSchema - <KeyedCollection> schema document.
	Answers:
		<McpSchemaValidator> the receiver.
	Raises:
		<Error> invalid schema; <McpJsonRpcError> invalid value."
	rootSchema := aSchema.
	activePairs := OrderedCollection new.
	self validateArguments: aValue againstSchema: aSchema

]

{ #category : 'Validation' }
McpSchemaValidator >> validateArguments: aValue againstSchema: aSchema [
	"Follow references without allowing a non-progressing reference cycle.
	Arguments:
		aValue - <Object> JSON value.
		aSchema - <KeyedCollection | Boolean | nil> schema.
	Answers:
		<McpSchemaValidator> the receiver."
	| pair reference |
	aSchema == true ifTrue: [^self].
	aSchema == false ifTrue: [
		McpJsonRpcError signalCode: McpJsonRpcInvalidParamsCode
			message: 'Invalid params: false schema' data: nil].
	aSchema ifNil: [^self].
	(aSchema isKindOf: KeyedCollection)
		ifFalse: [self error: 'MCP schema must be keyed or boolean'].
	(activePairs anySatisfy: [:each |
		each key == aSchema and: [each value == aValue]])
			ifTrue: [self error:
				'MCP schema reference cycle makes no progress'].
	activePairs size >= 256
		ifTrue: [self error: 'MCP schema validation nesting limit exceeded'].
	(aSchema ~~ rootSchema and: [aSchema includesKey: '$id'])
		ifTrue: [self error: 'Embedded schema resource IDs are not supported'].
	pair := aSchema -> aValue.
	activePairs add: pair.
	[
		reference := aSchema at: '$ref' ifAbsent: [nil].
		reference ifNotNil: [
			self validateArguments: aValue
				againstSchema: (self resolveReference: reference)].
		self validateLocalValue: aValue againstSchema: aSchema
	] ensure: [activePairs removeLast]

]

{ #category : 'Validation' }
McpSchemaValidator >> validateLocalValue: value againstSchema: schema [
	"Validate a JSON value against the supported JSON Schema subset.

	 Supported constraints are type, required, properties,
	 additionalProperties, items, enum, and const. Malformed local schemas
	 produce an internal error; argument mismatches produce an invalid-params
	 error.

	 Arguments:
		value - <Object> decoded JSON-compatible value.
		schema - <KeyedCollection> JSON Schema object, or nil.
	 Answers:
		<McpSchemaValidator> the receiver."

	| type required properties additionalProperties items enumeration constant
		arrayValue
	  constantPresent |

	schema ifNil: [^self].
	(schema isKindOf: KeyedCollection)
		ifFalse: [self error: 'MCP tool schema must be a keyed collection'].
	type := schema at: 'type' ifAbsent: [nil].
	type ifNotNil: [
		type isString ifFalse: [self error:
			'MCP tool schema type must be a string'].
		(#('object' 'array' 'string' 'number' 'integer' 'boolean' 'null')
			includes: type)
			ifFalse: [self error:
				'MCP tool schema contains an unsupported type'].
		type = 'object'
			ifTrue: [
				(value isKindOf: KeyedCollection)
					ifFalse: [
						McpJsonRpcError
							signalCode: McpJsonRpcInvalidParamsCode
							message: 'Invalid params: expected object'
							data: nil]].
		type = 'array'
			ifTrue: [
				((value isKindOf: SequenceableCollection)
					and: [value isString not and: [(value isKindOf:
				KeyedCollection) not]])
						ifFalse: [
							McpJsonRpcError
								signalCode: McpJsonRpcInvalidParamsCode
								message: 'Invalid params: expected array'
								data: nil]].
		type = 'string'
			ifTrue: [
				(value isString and: [value isSymbol not])
					ifFalse: [
						McpJsonRpcError
							signalCode: McpJsonRpcInvalidParamsCode
							message: 'Invalid params: expected string'
							data: nil]].
		type = 'number'
			ifTrue: [
				value isNumber
					ifFalse: [
						McpJsonRpcError
							signalCode: McpJsonRpcInvalidParamsCode
							message: 'Invalid params: expected number'
							data: nil]].
		type = 'integer'
			ifTrue: [
				value isInteger
					ifFalse: [
						McpJsonRpcError
							signalCode: McpJsonRpcInvalidParamsCode
							message: 'Invalid params: expected integer'
							data: nil]].
		type = 'boolean'
			ifTrue: [
				value isBoolean
					ifFalse: [
						McpJsonRpcError
							signalCode: McpJsonRpcInvalidParamsCode
							message: 'Invalid params: expected boolean'
							data: nil]].
		type = 'null'
			ifTrue: [
				value isNil
					ifFalse: [
						McpJsonRpcError
							signalCode: McpJsonRpcInvalidParamsCode
							message: 'Invalid params: expected null'
							data: nil]]].
	(value isKindOf: KeyedCollection)
		ifTrue: [
			required := schema at: 'required' ifAbsent: [#()].
			((required isKindOf: SequenceableCollection) and: [
				required isString not and: [
					(required isKindOf: KeyedCollection) not and: [
						required allSatisfy: [:requiredPropertyName |
				requiredPropertyName isString]]]])
							ifFalse: [
								self error:
				'MCP tool schema required must be an array of strings'].
			required do: [:requiredName |
				(value includesKey: requiredName)
					ifFalse: [
						McpJsonRpcError
							signalCode: McpJsonRpcInvalidParamsCode
							message:
				'Invalid params: missing required property ' , requiredName
							data: nil]].
			properties := schema at: 'properties' ifAbsent: [EsOrderedDictionary
				new].
			(properties isKindOf: KeyedCollection)
				ifFalse: [self error:
				'MCP tool schema properties must be keyed'].
			additionalProperties := schema at: 'additionalProperties' ifAbsent:
				[true].
			(additionalProperties isBoolean or: [additionalProperties isKindOf:
				KeyedCollection])
				ifFalse: [self error:
				'MCP tool schema additionalProperties is invalid'].
			value keysAndValuesDo: [:propertyName :propertyValue | |
				propertySchema |
				propertySchema := properties at: propertyName ifAbsent: [nil].
				propertySchema
					ifNotNil: [self validateArguments: propertyValue
				againstSchema: propertySchema]
					ifNil: [
						additionalProperties == false
							ifTrue: [
								McpJsonRpcError
									signalCode: McpJsonRpcInvalidParamsCode
									message:
										'Invalid params: extraneous property ' ,
											propertyName asString
									data: nil].
						(additionalProperties isKindOf: KeyedCollection)
							ifTrue: [
								self
									validateArguments: propertyValue
									againstSchema: additionalProperties]]]].
	arrayValue :=
		(value isKindOf: SequenceableCollection)
			and: [value isString not and: [(value isKindOf: KeyedCollection)
				not]].
	arrayValue
		ifTrue: [
			items := schema at: 'items' ifAbsent: [nil].
			items ifNotNil: [
				(items isBoolean or: [items isKindOf: KeyedCollection])
					ifFalse: [self error:
				'MCP tool schema items must be keyed'].
				value do: [:item | self validateArguments: item againstSchema:
				items]]].
	enumeration := schema at: 'enum' ifAbsent: [nil].
	enumeration ifNotNil: [
		((enumeration isKindOf: SequenceableCollection)
			and: [enumeration isString not and: [(enumeration isKindOf:
				KeyedCollection) not]])
				ifFalse: [self error: 'MCP tool schema enum must be an array'].
		(enumeration includes: value)
			ifFalse: [
				McpJsonRpcError
					signalCode: McpJsonRpcInvalidParamsCode
					message: 'Invalid params: value is not in enum'
					data: nil]].
	constantPresent := schema includesKey: 'const'.
	constantPresent
		ifTrue: [
			constant := schema at: 'const'.
			constant = value
				ifFalse: [
					McpJsonRpcError
						signalCode: McpJsonRpcInvalidParamsCode
						message: 'Invalid params: value does not match const'
						data: nil]].
	^self

]
