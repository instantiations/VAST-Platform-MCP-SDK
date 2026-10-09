"
(c) Copyright Instantiations Corporation 2005-2026. All Rights Reserved.

# TestMcpToolRegistry

`TestMcpToolRegistry` verifies tool definition and registration invariants.

## Responsibilities

- Verify unique, valid, case-sensitive tool names.
- Verify public lookup and duplicate-registration behavior.
- Verify required schema metadata and defensive copying.
- Verify unsupported execution claims are rejected.

Each test creates a fresh registry and shares no mutable tool metadata.
"
Class {
	#name : 'TestMcpToolRegistry',
	#superclass : 'TestCase',
	#instVars : [
		'registry'
	],
	#category : 'McpToolTests'
}

{ #category : 'Initialization' }
TestMcpToolRegistry >> setUp [
	"Create a fresh tool registry."

	super setUp.
	registry := McpToolRegistry new
]

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpToolRegistry >> strictEmptyObjectSchema [
	"Answer a schema accepting only an empty object."

	^EsOrderedDictionary new
		at: 'type' put: 'object';
		at: 'additionalProperties' put: false;
		yourself
]

{ #category : 'Serialization' }
TestMcpToolRegistry >> testDefaultInputSchemaIsAnObject [
	"A tool without an explicit schema advertises a non-null object schema."

	| definition schema |

	definition := (McpTool new name: 'default.schema') asMcpDefinition.
	schema := definition at: 'inputSchema'.
	self assert: (schema isKindOf: KeyedCollection).
	self assert: (schema at: 'type') equals: 'object'
]

{ #category : 'Registration' }
TestMcpToolRegistry >> testDuplicateRegistrationPreservesOriginalTool [
	"Duplicate names are rejected without replacing the registered tool."

	| original duplicate signaledError |

	original := self toolNamed: 'duplicate.tool' block: ['original'].
	duplicate := self toolNamed: 'duplicate.tool' block: ['replacement'].
	registry registerTool: original.
	signaledError := nil.
	[registry registerTool: duplicate]
		on: Error
		do: [:error |
			signaledError := error.
			error return].
	self assert: signaledError notNil.
	self assert: signaledError messageText equals: 'Tool already registered: duplicate.tool'.
	self assert: (registry toolNamed: 'duplicate.tool' ifAbsent: [nil]) equals: original.
	self assert: registry size equals: 1
]

{ #category : 'Validation' }
TestMcpToolRegistry >> testRegistrationRejectsInvalidToolName [
	"Registry validation rejects names outside the MCP tool-name alphabet."

	| tool |

	tool := self toolNamed: 'invalid tool' block: ['unused'].
	self should: [registry registerTool: tool] raise: Error.
	self assert: registry size equals: 0
]

{ #category : 'Validation' }
TestMcpToolRegistry >> testRegistrationRejectsUnsupportedTaskExecution [
	"A server that lacks task support rejects a tool claiming that support."

	| tool |

	tool := self toolNamed: 'task.claim' block: ['unused'].
	tool execution: (EsOrderedDictionary with: 'taskSupport' -> 'optional').
	self should: [registry registerTool: tool] raise: Error.
	self assert: registry size equals: 0
]

{ #category : 'Registration' }
TestMcpToolRegistry >> testRegistrationSupportsPublicLookup [
	"Registration exposes the same tool through the public lookup protocol."

	| tool lookedUp |

	tool := self toolNamed: 'lookup.tool' block: ['found'].
	self assert: (registry registerTool: tool) equals: tool.
	self assert: (registry includesToolNamed: 'lookup.tool').
	lookedUp := registry toolNamed: 'lookup.tool' ifAbsent: [nil].
	self assert: lookedUp == tool.
	self assert: registry size equals: 1
]

{ #category : 'Serialization' }
TestMcpToolRegistry >> testToolDefinitionIncludesConfiguredMetadata [
	"A tool definition includes configured descriptive and schema metadata."

	| tool definition schema |

	schema :=
		EsOrderedDictionary new
			at: 'type' put: 'object';
			at: 'additionalProperties' put: false;
			yourself.
	tool := self toolNamed: 'metadata.tool' block: ['unused'].
	tool
		title: 'Metadata Tool';
		description: 'Exercises tool metadata';
		inputSchema: schema.
	definition := tool asMcpDefinition.
	self assert: (definition at: 'name') equals: 'metadata.tool'.
	self assert: (definition at: 'title') equals: 'Metadata Tool'.
	self assert: (definition at: 'description') equals: 'Exercises tool metadata'.
	self assert: ((definition at: 'inputSchema') at: 'type') equals: 'object'.
	self assert: ((definition at: 'inputSchema') at: 'additionalProperties') equals: false
]

{ #category : 'Copying' }
TestMcpToolRegistry >> testToolInputSchemaIsDefensivelyCopied [
	"Schema mutation cannot cross the tool metadata boundary."

	| schema properties tool returnedSchema |

	properties := EsOrderedDictionary with: 'value' -> (EsOrderedDictionary with: 'type' -> 'string').
	schema :=
		EsOrderedDictionary new
			at: 'type' put: 'object';
			at: 'properties' put: properties;
			yourself.
	tool := self toolNamed: 'snapshot.tool' block: ['unused'].
	tool inputSchema: schema.
	(properties at: 'value') at: 'type' put: 'number'.
	self assert: (((tool inputSchema at: 'properties') at: 'value') at: 'type') equals: 'string'.
	returnedSchema := tool inputSchema.
	((returnedSchema at: 'properties') at: 'value') at: 'type' put: 'boolean'.
	self assert: (((tool inputSchema at: 'properties') at: 'value') at: 'type') equals: 'string'
]

{ #category : 'Validation' }
TestMcpToolRegistry >> testToolRejectsNonObjectInputSchema [
	"Tool input schemas must have an object root."

	| tool schema |

	tool := self toolNamed: 'invalid.schema' block: ['unused'].
	schema := EsOrderedDictionary with: 'type' -> 'array'.
	self should: [tool inputSchema: schema] raise: Error
]

{ #category : 'Test Support',
  #vaVisibility : 'private' }
TestMcpToolRegistry >> toolNamed: toolName block: executionBlock [
	"Answer a block tool with a valid strict object input schema."

	^McpBlockTool new
		name: toolName;
		inputSchema: self strictEmptyObjectSchema;
		block: executionBlock;
		yourself
]
