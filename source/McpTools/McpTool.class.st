"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# McpTool

`McpTool` describes one callable MCP tool, its schemas, and parameter resolvers.

## Responsibilities

- Validate identity, input and output schemas, metadata, and icons.
- Manage dynamic parameter resolvers via `resolvers` and `resolve:with:`.
- Execute through subclass-defined behavior under request context.

## Lifecycle and boundaries

Registries own tool identity; execution results are detached values.
"
Class {
	#name : 'McpTool',
	#superclass : 'Object',
	#instVars : [
		'name',
		'description',
		'inputSchema',
		'title',
		'outputSchema',
		'annotations',
		'icons',
		'meta',
		'execution',
		'resolvers'
	],
	#category : 'McpTools'
}

{ #category : 'Accessing' }
McpTool >> annotations [
	"Answer a detached copy of the optional behavioral annotations.

	 Answers:
		<KeyedCollection> or nil."

	annotations ifNil: [^nil].
	^self detachedProtocolValue: annotations
]

{ #category : 'Accessing' }
McpTool >> annotations: aDictionary [
	"Validate and set optional untrusted behavioral annotations.

	 Arguments:
		aDictionary - <KeyedCollection> tool annotations, or nil.
	 Answers:
		<McpTool> the receiver."

	| value |

	(aDictionary isNil or: [aDictionary isKindOf: KeyedCollection])
		ifFalse: [self error: 'Tool annotations must be a keyed collection or nil'].
	aDictionary ifNotNil: [
		value := aDictionary at: 'title' ifAbsent: [nil].
		(value isNil or: [value isString])
			ifFalse: [self error: 'Tool annotation title must be a string'].
		#('readOnlyHint' 'destructiveHint' 'idempotentHint' 'openWorldHint') do: [:field |
			value := aDictionary at: field ifAbsent: [nil].
			(value isNil or: [value isBoolean])
				ifFalse: [self error: 'Tool annotation ' , field , ' must be boolean']]].
	annotations := aDictionary ifNotNil: [self detachedProtocolValue: aDictionary].
	^self
]

{ #category : 'Serialization' }
McpTool >> asMcpDefinition [
	"Answer a detached MCP tool definition.

	 Answers:
		<KeyedCollection> JSON-compatible tool definition."

	| definition schema |

	definition :=
		EsOrderedDictionary new
			at: 'name' put: self name;
			yourself.
	self title ifNotNil: [:value | definition at: 'title' put: value].
	self description ifNotNil: [:value | definition at: 'description' put: value].
	schema := self inputSchema.
	schema ifNil: [schema := EsOrderedDictionary with: 'type' -> 'object'].
	definition at: 'inputSchema' put: schema.
	self outputSchema ifNotNil: [:value | definition at: 'outputSchema' put: value].
	self annotations ifNotNil: [:value | definition at: 'annotations' put: value].
	self icons ifNotNil: [:value | definition at: 'icons' put: value].
	self meta ifNotNil: [:value | definition at: '_meta' put: value].
	self execution ifNotNil: [:value | definition at: 'execution' put: value].
	^definition
]

{ #category : 'Accessing' }
McpTool >> description [
	"Answer a copy of the optional human-readable description.

	 Answers:
		<String> or nil."

	description ifNil: [^nil].
	^description copy
]

{ #category : 'Accessing' }
McpTool >> description: aString [
	"Set the optional human-readable description.

	 Arguments:
		aString - <String> description, or nil.
	 Answers:
		<McpTool> the receiver."

	(aString isNil or: [aString isString])
		ifFalse: [self error: 'Tool description must be a string or nil'].
	description := aString ifNotNil: [aString copy].
	^self
]

{ #category : 'Serialization',
  #vaVisibility : 'private' }
McpTool >> detachedProtocolValue: anObject [
	"Answer an isolated copy of a JSON-compatible protocol value.

	 Arguments:
		anObject - <Object> JSON-compatible value.
	 Answers:
		<Object> detached value."

	^self detachedProtocolValue: anObject visited: IdentitySet new
]

{ #category : 'Serialization',
  #vaVisibility : 'private' }
McpTool >> detachedProtocolValue: anObject visited: visitedObjects [
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
	self error: 'MCP tool metadata contains a non-JSON-compatible value'
]

{ #category : 'Execution' }
McpTool >> executeWithArguments: arguments context: requestContext [
	"Execute the tool using validated arguments and request context.

	 Subclasses must answer a raw JSON-compatible value or an MCP
	 CallToolResult candidate.

	 Arguments:
		arguments - <KeyedCollection> detached tool arguments.
		requestContext - <McpServerRequestContext> or nil.
	 Answers:
		<Object> tool-specific execution result."

	^self subclassResponsibility
]

{ #category : 'Accessing' }
McpTool >> execution [
	"Answer a detached copy of optional execution metadata.

	 Answers:
		<KeyedCollection> or nil."

	execution ifNil: [^nil].
	^self detachedProtocolValue: execution
]

{ #category : 'Accessing' }
McpTool >> execution: aDictionary [
	"Validate and set optional task-augmented execution metadata.

	 Arguments:
		aDictionary - <KeyedCollection> execution metadata, or nil.
	 Answers:
		<McpTool> the receiver."

	(aDictionary isNil or: [aDictionary isKindOf: KeyedCollection])
		ifFalse: [self error: 'Tool execution metadata must be keyed or nil'].
	aDictionary ifNotNil: [| taskSupport |
		taskSupport := aDictionary at: 'taskSupport' ifAbsent: [nil].
		(taskSupport isNil or: [#('forbidden' 'optional' 'required') includes: taskSupport])
			ifFalse: [self error: 'Tool taskSupport value is invalid']].
	execution := aDictionary ifNotNil: [self detachedProtocolValue: aDictionary].
	^self
]

{ #category : 'Accessing' }
McpTool >> icons [
	"Answer detached copies of the optional icon definitions.

	 Answers:
		<Array> of <KeyedCollection>, or nil."

	icons ifNil: [^nil].
	^self detachedProtocolValue: icons
]

{ #category : 'Accessing' }
McpTool >> icons: aCollection [
	"Set optional icon definitions.

	 Arguments:
		aCollection - <SequenceableCollection> of keyed icons, or nil.
	 Answers:
		<McpTool> the receiver."

	(aCollection isNil
		or: [(aCollection isKindOf: SequenceableCollection) and: [aCollection isString not]])
			ifFalse: [self error: 'Tool icons must be an array or nil'].
	aCollection ifNotNil: [
		(aCollection allSatisfy: [:icon | icon isKindOf: KeyedCollection])
			ifFalse: [self error: 'Tool icons must contain only keyed definitions']].
	icons := aCollection ifNotNil: [self detachedProtocolValue: aCollection].
	^self
]

{ #category : 'Accessing' }
McpTool >> inputSchema [
	"Answer a detached copy of the argument JSON Schema.

	 Answers:
		<KeyedCollection> or nil."

	inputSchema ifNil: [^nil].
	^self detachedProtocolValue: inputSchema
]

{ #category : 'Accessing' }
McpTool >> inputSchema: aDictionary [
	"Validate and set the object-rooted argument JSON Schema.

	 Arguments:
		aDictionary - <KeyedCollection> JSON Schema, or nil for default.
	 Answers:
		<McpTool> the receiver."

	self validateObjectSchema: aDictionary label: 'inputSchema'.
	inputSchema := aDictionary ifNotNil: [self detachedProtocolValue: aDictionary].
	^self
]

{ #category : 'Accessing' }
McpTool >> meta [
	"Answer a detached copy of the optional protocol extension metadata.

	 Answers:
		<KeyedCollection> or nil."

	meta ifNil: [^nil].
	^self detachedProtocolValue: meta
]

{ #category : 'Accessing' }
McpTool >> meta: aDictionary [
	"Set optional protocol extension metadata serialized as `_meta`.

	 Arguments:
		aDictionary - <KeyedCollection> JSON-compatible metadata, or nil.
	 Answers:
		<McpTool> the receiver."

	(aDictionary isNil or: [aDictionary isKindOf: KeyedCollection])
		ifFalse: [self error: 'Tool metadata must be a keyed collection or nil'].
	meta := aDictionary ifNotNil: [self detachedProtocolValue: aDictionary].
	^self
]

{ #category : 'Accessing' }
McpTool >> name [
	"Answer a copy of the case-sensitive protocol name.

	 Answers:
		<String> or nil."

	name ifNil: [^nil].
	^name copy
]

{ #category : 'Accessing' }
McpTool >> name: aString [
	"Set the case-sensitive protocol name.

	 Arguments:
		aString - <String> nonempty protocol name.
	 Answers:
		<McpTool> the receiver."

	(aString isString and: [aString isEmpty not])
		ifFalse: [self error: 'Tool name must be a nonempty string'].
	name := aString copy.
	^self
]

{ #category : 'Accessing' }
McpTool >> outputSchema [
	"Answer a detached copy of the optional structured-result schema.

	 Answers:
		<KeyedCollection> or nil."

	outputSchema ifNil: [^nil].
	^self detachedProtocolValue: outputSchema
]

{ #category : 'Validation' }
McpTool >> outputSchema: aDictionary [
	"Validate and set the optional object-rooted result JSON Schema.

	 Arguments:
		aDictionary - <KeyedCollection> JSON Schema, or nil.
	 Answers:
		<McpTool> the receiver."

	(aDictionary notNil and: [(aDictionary isKindOf: KeyedCollection) not])
		ifTrue: [self error: 'Tool outputSchema must be keyed'].
	outputSchema := aDictionary ifNotNil: [self detachedProtocolValue:
		aDictionary].
	^self

]

{ #category : 'Registration' }
McpTool >> resolve: aParameterName with: aBlock [
	"Register a parameter resolver for aParameterName.

	 Arguments:
		aParameterName - <String> parameter name to dynamically resolve.
		aBlock - <Block> [:context :arguments | ...] resolver block.
	 Answers:
		<McpTool> the receiver."

	| resolver |

	resolver := McpResolver named: aParameterName block: aBlock.
	self resolvers add: resolver.
	^self
]

{ #category : 'Accessing' }
McpTool >> resolvers [
	"Answer the collection of parameter resolvers configured on this tool.

	 Answers:
		<OrderedCollection> of <McpResolver>."

	resolvers ifNil: [resolvers := OrderedCollection new].
	^resolvers
]

{ #category : 'Accessing' }
McpTool >> title [
	"Answer the optional human-readable display title.

	 Answers:
		<String> or nil."

	^title
]

{ #category : 'Accessing' }
McpTool >> title: aString [
	"Set the optional human-readable display title.

	 Arguments:
		aString - <String> nonempty title, or nil.
	 Answers:
		<McpTool> the receiver."

	(aString isNil or: [aString isString and: [aString isEmpty not]])
		ifFalse: [self error: 'Tool title must be a nonempty string or nil'].
	title := aString ifNotNil: [aString copy].
	^self
]

{ #category : 'Validation',
  #vaVisibility : 'private' }
McpTool >> validateObjectSchema: aDictionary label: label [
	"Validate the MCP object-root restrictions for a tool schema.

	 Arguments:
		aDictionary - <KeyedCollection> schema, or nil.
		label - <String> diagnostic field name.
	 Answers:
		<McpTool> the receiver."

	| properties required names |

	aDictionary ifNil: [^self].
	(aDictionary isKindOf: KeyedCollection)
		ifFalse: [self error: 'Tool ' , label , ' must be keyed or nil'].
	(aDictionary at: 'type' ifAbsent: [nil]) = 'object'
		ifFalse: [self error: 'Tool ' , label , ' must declare object type'].
	properties := aDictionary at: 'properties' ifAbsent: [nil].
	(properties isNil or: [properties isKindOf: KeyedCollection])
		ifFalse: [self error: 'Tool ' , label , ' properties must be keyed'].
	required := aDictionary at: 'required' ifAbsent: [nil].
	(required isNil or: [
		(required isKindOf: SequenceableCollection)
			and: [required isString not and: [(required isKindOf: KeyedCollection) not]]])
				ifFalse: [self error: 'Tool ' , label , ' required must be an array'].
	required ifNotNil: [
		names := Set new.
		required do: [:requiredName |
			(requiredName isString and: [requiredName isEmpty not])
				ifFalse: [self error: 'Tool ' , label , ' required names must be strings'].
			(names includes: requiredName)
				ifTrue: [self error: 'Tool ' , label , ' has duplicate required names'].
			names add: requiredName]].
	^self
]
