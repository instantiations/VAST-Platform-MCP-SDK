"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# McpBlockResourceTemplate

`McpBlockResourceTemplate` matches and reads templated MCP resources through
blocks or compiled RFC 6570 URI templates, and optionally computes variable
autocompletions.

## Responsibilities

- Match incoming resource URIs using either a configured `matchBlock` or
  automatically via `McpUriTemplate` (RFC 6570 Level 1-2).
- Extract URI template variables into `requestContext metadata at: 'variables'`
  prior to reader block evaluation.
- Read matched concrete URIs via `readBlock:`.
- Provide dynamic autocompletions for template variables via `completionBlock:`.
- Preserve template metadata and request-context boundaries.

## Lifecycle and boundaries

Configuration is mutable; callers own block thread-safety.
"
Class {
	#name : 'McpBlockResourceTemplate',
	#superclass : 'McpResourceTemplate',
	#instVars : [
		'matchBlock',
		'readBlock',
		'completionBlock'
	],
	#category : 'McpResources'
}

{ #category : 'Protocol Operations' }
McpBlockResourceTemplate >> completeArgument: anArgumentName value: aCurrentValue context: aContextDictionary [
	"Compute completion values for a template variable using the configured completion block.

	 Arguments:
		anArgumentName - <String> variable name.
		aCurrentValue - <String> current prefix or value.
		aContextDictionary - <KeyedCollection> optional context, or nil.
	 Answers:
		<Collection of String> or <KeyedCollection>."

	self completionBlock ifNil: [^#()].
	^self completionBlock cull: anArgumentName cull: aCurrentValue cull: aContextDictionary
]

{ #category : 'Accessing' }
McpBlockResourceTemplate >> completionBlock [
	"Answer the completion handler block for template variables.

	 Answers:
		<Block> or nil."

	^completionBlock
]

{ #category : 'Accessing' }
McpBlockResourceTemplate >> completionBlock: aBlock [
	"Set the completion handler block for template variables.

	 Arguments:
		aBlock - <Block> [:argName :currentVal :contextDict | ...], or nil.
	 Answers:
		<McpBlockResourceTemplate> the receiver."

	(aBlock isNil or: [aBlock isKindOf: Block])
		ifFalse: [self error: 'Completion handler must be a block or nil'].
	completionBlock := aBlock.
	^self
]

{ #category : 'Accessing' }
McpBlockResourceTemplate >> matchBlock [
	"Answer the block used to recognize concrete resource URIs.

	 Answers:
		<Block>."

	^matchBlock
]

{ #category : 'Accessing' }
McpBlockResourceTemplate >> matchBlock: aBlock [
	"Set a URI matcher accepting exactly one argument.

	 Arguments:
		aBlock - <Block> concrete URI matcher.
	 Answers:
		<McpBlockResourceTemplate> the receiver."

	(aBlock isBlock and: [aBlock numArgs = 1])
		ifFalse: [self error: 'MCP resource-template matcher must accept one URI'].
	matchBlock := aBlock.
	^self
]

{ #category : 'Validation' }
McpBlockResourceTemplate >> matchesUri: aUri [
	"Answer whether the template accepts a concrete URI.

	 Uses the configured matchBlock if present, or evaluates McpUriTemplate against uriTemplate.

	 Arguments:
		aUri - <String> absolute resource URI.
	 Answers:
		<Boolean>."

	matchBlock ifNotNil: [| answer |
		answer := matchBlock value: aUri.
		answer isBoolean ifFalse: [self error: 'MCP resource-template matcher must answer Boolean'].
		^answer].
	self uriTemplate ifNotNil: [:tpl | ^(McpUriTemplate template: tpl) matchesUri: aUri].
	self error: 'MCP resource-template matcher is not configured'
]

{ #category : 'Accessing' }
McpBlockResourceTemplate >> readBlock [
	"Answer the block used to read matching concrete resource URIs.

	 Answers:
		<Block>."

	^readBlock
]

{ #category : 'Accessing' }
McpBlockResourceTemplate >> readBlock: aBlock [
	"Set a reader accepting the URI and optional request context.

	 Arguments:
		aBlock - <Block> accepting one or two arguments.
	 Answers:
		<McpBlockResourceTemplate> the receiver."

	(aBlock isBlock and: [aBlock numArgs between: 1 and: 2])
		ifFalse: [self error: 'MCP resource-template reader must accept URI and context'].
	readBlock := aBlock.
	^self
]

{ #category : 'Execution' }
McpBlockResourceTemplate >> readUri: aUri context: requestContext [
	"Read a concrete URI by evaluating the configured reader and extracting template variables.

	 Arguments:
		aUri - <String> matching absolute resource URI.
		requestContext - <McpServerRequestContext> or nil.
	 Answers:
		<KeyedCollection> MCP ReadResourceResult."

	readBlock ifNil: [self error: 'MCP resource-template reader is not configured'].
	(requestContext notNil and: [self uriTemplate notNil])
		ifTrue: [| vars |
			vars := (McpUriTemplate template: self uriTemplate) matchUri: aUri.
			vars ifNotNil: [requestContext metadata at: 'variables' put: vars]].
	^readBlock cull: aUri cull: requestContext
]
